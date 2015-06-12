---
layout: post
title: "Socket层实现系列 — 睡眠驱动的同步等待"
date: 2015-06-12 17:16:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/45770323

主要内容：Socket的同步等待机制，connect和accept等待的实现。

内核版本：3.15.2

#### 概述

socket上定义了几个IO事件：状态改变事件、有数据可读事件、有发送缓存可写事件、有IO错误事件。对于这些事件，socket中分别定义了相应的事件处理函数，也称回调函数。

Socket I/O事件的处理过程中，要使用到sock上的两个队列：等待队列和异步通知队列，这两个队列中都保存着等待该Socket I/O事件的进程。


Q：为什么要使用两个队列，等待队列和异步通知队列有什么区别呢？  
A：等待队列上的进程会睡眠，直到Socket I/O事件的发生，然后在事件处理函数中被唤醒。异步通知队列上的进程则不需要睡眠，Socket I/O事件发时，事件处理函数会给它们发送到信号，这些进程事先注册的信号处理函数就能够被执行。


#### 等待队列

Socket层使用等待队列来进行阻塞等待，在等待期间，阻塞在此socket上的进程会睡眠。

```
	struct sock {
		...
		struct socket_wq __rcu *sk_wq; /* socket的等待队列和异步通知队列 */
		...
	}

	struct socket_wq {
		/* Note: wait MUST be first field of socket_wq */
		wait_queue_head_t wait; /* 等待队列头 */
		struct fasync_struct *fasync_list; /* 异步通知队列 */
		struct rcu_head *rcu;
	};
```

###### (1)  socket的等待队列头

```
	struct __wait_queue_head {
		spinlock_t lock;
		struct list_head task_list;
	};
	typedef struct __wait_queue_head wait_queue_head_t;
```


##### (2) 进程的等待任务

```
	struct __wait_queue {
		unsigned int flags;
	#define WQ_FLAG_EXCLUSIVE 0x01
		void *private; /* 指向当前的进程控制块 */
		wait_queue_func_t func; /* 唤醒函数 */
		struct list_head task_list; /* 用于链接入等待队列 */
	};
	typedef struct __wait_queue wait_queue_t;
	typedef int (*wait_queue_func_t) (wait_queue_t *wait, unsigned mode, int flags, void *key);
	int default_wake_function(wait_queue_t *wait, unsigned mode, int flags, void *key);
```


##### (3) 初始化等待任务

```
	#define DEFINE_WAIT(name) DEFINE_WAIT_FUNC(name, autoremove_wake_function)

	#define DEFINE_WAIT_FUNC(name, function)    \
		wait_queue_t name = {    \
			.private = current,    \
			.func = function,    \
			.task_list = LIST_HEAD_INIT((name).task_list),    \
		}

	int autoremove_wake_function(wait_queue_t *wait, unsigned mode, int sync, void *key)
	{
		int ret = default_wake_function(wait, mode, sync, key); /* 默认的唤醒函数 */

		if (ret)
			list_del_init(&wait->task_list); /* 从等待队列中删除 */

		return ret;
	}

	int default_wake_function(wait_queue_t *curr, unsigned mode, int wake_flags, void *key)
	{
		return try_to_wake_up(curr->private, mode, wake_flags);
	}
```

try_to_wake_up()通过把进程的状态设置为TASK_RUNNING，并把进程插入CPU运行队列，来唤醒睡眠的进程。

##### (4) 把等待任务插入到等待队列中

获取sock的等待队列。

```
	static inline wait_queue_head_t *sk_sleep(struct sock *sk)
	{
		BUILD_BUG_ON(offsetof(struct socket_wq, wait) != 0);
		return &rcu_dereference_raw(sk->sk_wq)->wait;
	}
```

把等待任务加入到等待队列中，同时设置当前进程的状态，TASK_INTERRUPTIBLE或TASK_UNINTERRUPTIBLE。

```
	void prepare_to_wait(wait_queue_head_t *q, wait_queue_t *wait, int state)
	{
		unsigned long flags;
		wait->flags &= ~WQ_FLAG_EXCLUSIVE; /* 可以同时唤醒多个等待进程 */

		spin_lock_irqsave(&q->lock, flags);

		if (list_empty(&wait->task_list))
			__add_wait_queue(q, wait); /* 把等待任务加入到等待队列的头部，会最先被唤醒 */

		set_current_state(state); /* 设置进程的状态 */

		spin_unlock_irqrestore(&q->lock, flags);
	}
```

prepare_to_wait()和prepare_to_wait_exclusive()都是用来把等待任务加入到等待队列中，不同之处在于使用prepare_to_wait_exclusive()时，会在等待任务中添加WQ_FLAG_EXCLUSIVE标志，表示一次只能唤醒一个等待任务，目的是为了避免惊群现象。

```
	void prepare_to_wait_exclusive(wait_queue_head_t *q, wait_queue_t *wait, int state)
	{
		unsigned long flags;

		/* 这个标志表示一次只唤醒一个等待任务，避免惊群现象 */
		wait->flags |= WQ_FLAG_EXCLUSIVE;

		spin_lock_irqsave(&q->lock, flags);

		if (list_empty(&wait->task_list))
			__add_wait_queue_tail(q, wait); /* 把此等待任务加入到等待队列尾部 */

		set_current_state(state); /* 设置当前进程的状态 */

		spin_unlock_irqrestore(&q->lock, flags);
	}

	static inline void __add_wait_queue_tail(wait_queue_head_t *head, wait_queue_t *new)
	{
		list_add_tail(&new->task_list, &head->task_list);
	}

	#define set_current_state(state_value)    \
		set_mb(current->state, (state_value))
```

##### (5) 删除等待任务

从等待队列中删除等待任务，同时把等待进程的状态置为可运行状态，即TASK_RUNNING。

```
	/**
	 * finish_wait - clean up after waiting in a queue
	 * @q: waitqueue waited on，等待队列头
	 * @wait: wait descriptor，等待任务
	 *
	 * Sets current thread back to running state and removes the wait
	 * descriptor from the given waitqueue if still queued.
	 */
	void finish_wait(wait_queue_head_t *q, wait_queue_t *wait)
	{
		unsigned long flags;
		__set_current_state(TASK_RUNNING);

		if (! list_empty_careful(&wait->task_list)) {
			spin_lock_irqsave(&q->lock, flags);

			list_del_init(&wait->task_list); /* 从等待队列中删除 */

			spin_unlock_irqrestore(&q->lock, flags);
		}
	}
```

#### connect等待

##### (1) 睡眠

connect()的超时时间为sk->sk_sndtimeo，在sock_init_data()中初始化为MAX_SCHEDULE_TIMEOUT，表示无限等待，可以通过SO_SNDTIMEO选项来修改。

```
	static long inet_wait_for_connect(struct sock *sk, long timeo, int writebias)
	{
		DEFINE_WAIT(wait);  /* 初始化等待任务 */

		/* 把等待任务加入到socket的等待队列头部，把进程的状态设为TASK_INTERRUPTIBLE */
		prepare_to_wait(sk_sleep(sk), &wait, TASK_INTERRUPTIBLE);
		sk->sk_write_pending += writebias;

		/* Basic assumption: if someone sets sk->sk_err, he _must_ change state of the socket
		 * from TCP_SYN_*. Connect() does not allow to get error notifications without closing
		 * the socket.
		 */

		/* 完成三次握手后，状态就会变为TCP_ESTABLISHED，从而退出循环 */
		while ((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV)) {
			release_sock(sk); /* 等下要睡觉了，先释放锁 */

			/* 进入睡眠，直到超时或收到信号，或者被I/O事件处理函数唤醒。
			 * 1. 如果是收到信号退出的，timeo为剩余的jiffies。
			 * 2. 如果使用了SO_SNDTIMEO选项，超时退出后，timeo为0。
			 * 3. 如果没有使用SO_SNDTIMEO选项，timeo为无穷大，即MAX_SCHEDULE_TIMEOUT，
			 *      那么返回值也是这个，而超时时间不定。为了无限阻塞，需要上面的while循环。
			 */
			timeo = schedule_timeout(timeo);

			lock_sock(sk); /* 被唤醒后重新上锁 */

			/* 如果进程有待处理的信号，或者睡眠超时了，退出循环，之后会返回错误码 */
			if (signal_pending(current) || !timeo)
				break;

			/* 继续睡眠吧 */
			prepare_to_wait(sk_sleep(sk), &wait, TASK_INTERRUPTIBLE);
		}

		/* 等待结束时，把等待进程从等待队列中删除，把当前进程的状态设为TASK_RUNNING */
		finish_wait(sk_sleep(sk), &wait);
		sk->sk_write_pending -= writebias;
		return timeo;
	}
```

##### (2) 唤醒

三次握手中，当客户端收到SYNACK、发出ACK后，连接就成功建立了。此时连接的状态从TCP_SYN_SENT或TCP_SYN_RECV变为TCP_ESTABLISHED，sock的状态发生变化，会调用sock_def_wakeup()来处理连接状态变化事件，唤醒进程，connect()就能成功返回了。

sock_def_wakeup()的函数调用路径如下：
```
	tcp_v4_rcv
		tcp_v4_do_rcv
			tcp_rcv_state_process
				tcp_rcv_synsent_state_process
					tcp_finish_connect
						sock_def_wakeup
							wake_up_interruptible_all
								__wake_up
									__wake_up_common
```

```
	void tcp_finish_connect(struct sock *sk, struct sk_buff *skb)
	{
		...
		tcp_set_state(sk, TCP_ESTABLISHED); /* 在这里设置为连接已建立的状态 */
		...
		if (! sock_flag(sk, SOCK_DEAD)) {
			sk->sk_state_change(sk); /* 指向sock_def_wakeup，会唤醒调用connect()的进程，完成连接的建立 */
			sk_wake_async(sk, SOCK_WAKE_IO, POLL_OUT); /* 如果使用了异步通知，则发送SIGIO通知进程可写 */
		}
	}
```

#### accept等待

(1) 睡眠

accept()超时时间为sk->sk_rcvtimeo，在sock_init_data()中初始化为MAX_SCHEDULE_TIMEOUT，表示无限等待。

```
	/* Wait for an incoming connection, avoid race conditions.
	 * This must be called with the socket locked.
	 */
	static int inet_csk_wait_for_connect(struct sock *sk, long timeo)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		DEFINE_WAIT(wait); /* 初始化等待任务 */
		int err;

		for (; ;) {
			/* 把等待任务加入到socket的等待队列中，把进程状态设置为TASK_INTERRUPTIBLE */
			prepare_to_wait_exclusive(sk_sleep(sk), &wait, TASK_INTERRUPTIBLE);

			release_sock(sk); /* 等下可能要睡觉了，先释放 */

			if (reqsk_queue_empty(&icsk->icsk_accept_queue)) /* 如果全连接队列为空 */
				timeo = schedule_timeout(timeo); /* 进入睡眠直到超时或收到信号，或被IO事件处理函数唤醒 */

			lock_sock(sk); /* 醒来后重新上锁 */
			err = 0;
			/* 全连接队列不为空时，说明有新的连接建立了，成功返回 */
			if (! reqsk_queue_empty(&icsk->icsk_accept_queue))
				break;

			err = -EINVAL;
			if (sk->sk_state != TCP_LISTEN) /* 如果sock不处于监听状态了，退出，返回错误码 */
				break;

			err = sock_intr_errno(timeo);

			/* 如果进程有待处理的信号，退出，返回错误码。
			 * 因为timeo默认为MAX_SCHEDULE_TIMEOUT，所以err默认为-ERESTARTSYS。
			 * 接下来会重新调用此函数，所以accept()依然阻塞。
			 */
			if (signal_pending(current))
				break;

			err = -EAGAIN;
			if (! timeo) /* 如果等待超时，即超过用户设置的sk->sk_rcvtimeo，退出 */
				break;
		}

		/* 从等待队列中删除等待任务，把等待进程的状态设为TASK_RUNNING */
		finish_wait(sk_sleep(sk), &wait);
		return err;
	}
```

##### (2) 唤醒

三次握手中，当服务器端接收到ACK完成连接建立的时候，会把新的连接链入全连接队列中，然后唤醒监听socket上的等待进程，accept()就能成功返回了。

三次握手时，当收到客户端的ACK后，经过如下调用：

```
	tcp_v4_rcv
		tcp_v4_do_rcv
			tcp_child_process
				sock_def_readable
					wake_up_interruptible_sync_poll
						__wake_up_sync_key
							__wake_up_common
```

最终调用我们给等待任务注册的唤醒函数。

我们来看下accept()是如何避免惊群现象的。

```
	static void __wake_up_common(wait_queue_head_t *q, unsigned int mode, int nr_exclusive,
								 int wake_flags, void *key)
	{
		wait_queue_t *curr, *next;

		list_for_each_entry_safe(curr, next, &q->task_list, task_list) {
			unsigned flags = curr->flags;

			if (curr->func(curr, mode, wake_flags, key) && (flags & WQ_FLAG_EXCLUSIVE)
				!--nr_exclusive)
				break;
		}
	}
```

初始化等待任务时，flags |= WQ_FLAG_EXCLUSIVE。传入的nr_exclusive为1，表示只允许唤醒一个等待任务。

所以这里只会唤醒一个等待的进程，不会导致惊群现象。

