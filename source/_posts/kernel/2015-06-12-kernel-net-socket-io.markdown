---
layout: post
title: "Socket层实现系列 — I/O事件及其处理函数"
date: 2015-06-12 17:18:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/45787989

主要内容：Socket I/O事件的定义、I/O处理函数的实现。

内核版本：3.15.2

#### I/O事件定义

sock中定义了几个I/O事件，当协议栈遇到这些事件时，会调用它们的处理函数。

```
	struct sock {
		...
		struct socket_wq __rcu *sk_wq; /* socket的等待队列和异步通知队列 */
		...
		/* callback to indicate change in the state of the sock.
		 * sock状态改变时调用，比如从TCP_SYN_SENT或TCP_SYN_RECV变为TCP_ESTABLISHED，
		 * 导致connect()的唤醒。比如从TCP_ESTABLISHED变为TCP_CLOSE_WAIT。
		 */
		void (*sk_state_change) (struct sock *sk);

		/* callback to indicate there is data to be processed.
		 * sock上有数据可读时调用，比如服务器端收到第三次握手的ACK时会调用，导致accept()的唤醒。
		 */
		void (*sk_data_ready) (struct sock *sk);

		/* callback to indicate there is buffer sending space available.
		 * sock上有发送空间可写时调用，比如发送缓存变得足够大了。
		 */
		void (*sk_write_space) (struct sock *sk);

		/* callback to indicate errors (e.g. %MSG_ERRQUEUE)
		 * sock上有错误发生时调用，比如收到RST包。
		 */
		void (*sk_error_report) (struct sock *sk);
		...
	};
```
Socket I/O事件的默认处理函数在sock初始化时赋值。

对于SOCK_STREAM类型的Socket，sock有发送缓存可写事件会被更新为sk_stream_write_space。

```
	void sock_init_data(struct socket *sock, struct sock *sk)
	{
		...
		sk->sk_state_change = sock_def_wakeup; /* sock状态改变事件 */
		sk->sk_data_ready = sock_def_readable; /* sock有数据可读事件 */
		sk->sk_write_space = sock_def_write_space; /* sock有发送缓存可写事件 */
		sk->sk_error_report = sock_def_error_report; /* sock有IO错误事件 */
		...
	}
```

判断socket的等待队列上是否有进程。

```
	static inline bool wq_has_sleeper(struct socket_wq *wq)
	{
		smp_mb();
		return wq && waitqueue_active(&wq->wait);
	}
```

#### 状态改变事件

sk->sk_state_change的实例为sock_def_wakeup()，当sock的状态发生改变时，会调用此函数来进行处理。
```
	static void sock_def_wakeup(struct sock *sk)
	{
		struct socket_wq *wq; /* socket的等待队列和异步通知队列 */

		rcu_read_lock();
		wq = rcu_dereference(sk->sk_wq);
		if (wq_has_sleeper(wq)) /* 有进程阻塞在此socket上 */
			wake_up_interruptible_all(&wq->wait); /* 唤醒此socket上的所有睡眠进程 */
		rcu_read_unlock();
	}
```
```
	#define wake_up_interruptible_all(x) __wake_up(x, TASK_INTERRUPTIBLE, 0, NULL)

	void __wake_up(wait_queue_head_t *q, unsigned int mode, int nr_exclusive, void *key)
	{
		unsigned long flags;
		spin_lock_irqsave(&q->lock, flags);
		__wake_up_common(q, mode, nr_exclusive, 0, key);
		spin_unlock_irqrestore(&q->lock, flags);
	}
```
初始化等待任务时，如果flags设置了WQ_FLAG_EXCLUSIVE，那么传入的nr_exclusive为1，

表示只允许唤醒一个等待任务，这是为了避免惊群现象。否则会把t等待队列上的所有睡眠进程都唤醒。
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

最终调用的是等待任务中的处理函数，默认为autoremove_wake_function()。

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


#### 有数据可读事件

sk->sk_data_ready的实例为sock_def_readable()，当sock有输入数据可读时，会调用此函数来处理。
```
	static void sock_def_readable(struct sock *sk)
	{
		struct socket_wq *wq; /* socket的等待队列和异步通知队列 */

		rcu_read_lock();
		wq = rcu_dereference(sk->sk_wq);

		if (wq_has_sleeper(wq)) /* 有进程在此socket的等待队列 */
			wake_up_interruptible_sync_poll(&wq->wait, POLLIN | POLLPRI |
				POLLRDNORM | POLLRDBAND); /* 唤醒等待进程 */

		/* 异步通知队列的处理。
		 * 检查应用程序是否通过recv()类调用来等待接收数据，如果没有就发送SIGIO信号，
		 * 告知它有数据可读。
		 * how为函数的处理方式，band为用来告知的IO类型。
		 */
		sk_wake_async(sk, SOCK_WAKE_WAITD, POLL_IN);
	}
```

```
	#define wake_up_interruptible_sync_poll(x, m) \
		__wake_up_sync_key((x), TASK_INTERRUPTIBLE, 1, (void *) (m))

	void __wake_up_sync_key(wait_queue_head_t *q, unsigned int mode, int nr_exclusive, void *key)
	{
		unsigned long flags;
		int wake_flags = 1; /* XXX WF_SYNC */

		if (unlikely(!q))
			return;
		if (unlikely(nr_exclusive != 1))
			wake_flags = 0;

		spin_lock_irqsave(&q->lock, flags);
		__wake_up_common(q, mode, nr_exclusive, wake_flags, key);
		spin_unlock_irqrestore(&q->lock, flags);
	}
```

最终也是调用`__wake_up_common()`。初始化等待任务时，flags |= WQ_FLAG_EXCLUSIVE。

传入的nr_exclusive为1，表示只允许唤醒一个等待任务。所以这里只会唤醒一个等待的进程。


#### 有缓存可写事件

sk->sk_write_space的实例为sock_def_write_space()。

如果socket是SOCK_STREAM类型的，那么函数指针的值会更新为sk_stream_write_space()。

sk_stream_write_space()在TCP中的调用路径为：

```
	tcp_rcv_established / tcp_rcv_state_process
		tcp_data_snd_check
			tcp_check_space
				tcp_new_space
```

```
	/* When incoming ACK allowed to free some skb from write_queue,
	 * we remember this event in flag SOCK_QUEUE_SHRUNK and wake up socket
	 * on the exit from tcp input handler.
	 */
	static void tcp_new_space(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);

		if (tcp_should_expand_sndbuf(sk)) {
			tcp_sndbuf_expand(sk);
			tp->snd_cwnd_stamp = tcp_time_stamp;
		}

		/* 检查是否需要触发有缓存可写事件 */
		sk->sk_write_space(sk);
	}
```

```
	void sk_stream_write_space(struct sock *sk)
	{
		struct socket *sock = sk->sk_socket;
		struct socket_wq *wq; /* 等待队列和异步通知队列 */

		/* 如果剩余的发送缓存不低于发送缓存上限的1/3，且尚未发送的数据不高于一定值时 */
		if (sk_stream_is_writeable(sk) && sock) {
			clear_bit(SOCK_NOSPACE, &sock->flags); /* 清除发送缓存不够的标志 */

			rcu_read_lock();
			wq = rcu_dereference(sk->sk_wq); /* socket的等待队列和异步通知队列 */
			if (wq_has_sleeper(wq)) /* 如果等待队列不为空，则唤醒一个睡眠进程 */
				wake_up_interruptible_poll(&wq->wait, POLLOUT | POLLWRNORM | POLLWRBAND);

			/* 异步通知队列不为空，且允许发送数据时。
			 * 检测sock的发送队列是否曾经到达上限，如果有的话发送SIGIO信号，告知异步通知队列上
			 * 的进程有发送缓存可写。
			 */
			if (wq && wq->fasync_list && !(sk->sk_shutdown & SEND_SHUTDOWN))
				sock_wake_async(sock, SOCK_WAKE_SPACE, POLL_OUT);

			rcu_read_unlock();
		}
	}

	#define wake_up_interruptible_poll(x, m) \
		__wake_up(x, TASK_INTERRUPTIBLE, 1, (void *) (m))
```

最终也是调用`__wake_up_common()`。初始化等待任务时，flags |= WQ_FLAG_EXCLUSIVE。

传入的nr_exclusive为1，表示只允许唤醒一个等待进程。

```
	struct sock {
		...
		/* 发送队列中，skb数据区的总大小 */
		atomic_t sk_wmem_alloc;
		...
		int sk_sndbuf; /* 发送缓冲区大小的上限 */
		struct sk_buff_head sk_write_queue; /* 发送队列 */
		...
		/* 发送队列的总大小，包含发送队列中skb数据区的总大小，
		 * 以及sk_buff、sk_shared_info结构体、协议头的额外开销。
		 */
		int sk_wmem_queued;
		...
	};
```
如果剩余的发送缓存大于发送缓存上限的1/3，且尚未发送的数据少于一定值时，才会触发有发送

缓存可写的事件。

```
	static inline bool sk_stream_is_writeable(const struct sock *sk)
	{
		return sk_stream_wspace(sk) >= sk_stream_min_wspace(sk) &&
	}

	static inline int sk_stream_wspace(const struct sock *sk)
	{
		return sk->sk_sndbuf - sk->sk_wmem_queued;
	}

	static inline int sk_stream_min_wspace(const struct sock *sk)
	{
		return sk->sk_wmem_queued >> 1;
	}
```

检查尚未发送的数据是否已经够多了，如果超过了用户设置的值，就不用触发有发送缓存可写事件，

以免使用过多的内存。

```
	static inline bool sk_stream_memory_free(const struct sock *sk)
	{
		if (sk->sk_wmem_queued >= sk->sk_sndbuf)
			return false;

		return sk->sk_prot->stream_memory_free ? sk->sk_prot->stream_memory_free(sk) : true;
	}

	struct proto tcp_prot = {
		...
		.stream_memory_free = tcp_stream_memory_free,
		...
	};

	static inline bool tcp_stream_memory_free(const struct sock *sk)
	{
		const struct tcp_sock *tp = tcp_sk(sk);
		u32 notsent_bytes = tp->write_seq - tp->snd_nxt; /* 尚未发送的数据大小 */

		/* 当尚未发送的数据，少于配置的值时，才触发有发送缓存可写的事件。
		 * 这是为了避免发送缓存占用过多的内存。
		 */
		return notsent_bytes < tcp_notsent_lowat(tp);
	}
```
如果有使用TCP_NOTSENT_LOWAT选项，则使用用户设置的值。

否则使用sysctl_tcp_notsent_lowat，默认为无穷大。
```
	static inline u32 tcp_notsent_lowat(const struct tcp_sock *tp)
	{
		return tp->notsent_lowat ?: sysctl_tcp_notsent_lowat;
	}
```

#### 有I/O错误事件

sk->sk_error_report的实例为sock_def_error_report()。

在以下函数中会调用I/O错误事件处理函数：
```
	tcp_disconnect
	tcp_reset
	tcp_v4_err
	tcp_write_err
```

```
	static void sock_def_error_report(struct sock *sk)
	{
		struct socket_wq *wq; /* 等待队列和异步通知队列 */

		rcu_read_lock();
		wq = rcu_dereference(sk->sk_wq);
		if (wq_has_sleeper(wq)) /* 有进程阻塞在此socket上 */
			wake_up_interruptible_poll(&wq->wait, POLLERR);

		/* 如果使用了异步通知，则发送SIGIO信号通知进程有错误 */
		sk_wake_async(sk, SOCK_WAKE_IO, POLL_ERR);
	}

	#define wake_up_interruptible_poll(x, m) \
		__wake_up(x, TASK_INTERRUPTIBLE, 1, (void *) (m))
```
最终也是调用`__wake_up_common()`，由于nr_exclusive为1，只会唤醒socket上的一个等待进程。

