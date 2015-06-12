---
layout: post
title: "Socket层实现系列 — 信号驱动的异步等待"
date: 2015-06-12 17:13:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/45932775

主要内容：Socket的异步通知机制。

内核版本：3.15.2

#### 概述

socket上定义了几个IO事件：状态改变事件、有数据可读事件、有发送缓存可写事件、有IO错误事件。对于这些事件，socket中分别定义了相应的事件处理函数，也称回调函数。

Socket I/O事件的处理过程中，要使用到sock上的两个队列：等待队列和异步通知队列，这两个队列中都保存着等待该Socket I/O事件的进程。

Q：为什么要使用两个队列，等待队列和异步通知队列有什么区别呢？  
A：等待队列上的进程会睡眠，直到Socket I/O事件的发生，然后在事件处理函数中被唤醒。异步通知队列上的进程则不需要睡眠，Socket I/O事件发时，事件处理函数会给它们发送到信号，这些进程事先注册的信号处理函数就能够被执行。


#### 异步通知队列

Socket层使用异步通知队列来实现异步等待，此时等待Socket I/O事件的进程不用睡眠。

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

```
	struct fasync_struct {
		spinlock_t fa_lock;
		int magic;
		int fa_fd; /* 文件描述符 */
		struct fasync_struct *fa_next; /* 用于链入单向链表 */
		struct file *fa_file; /* fa_file->f_owner记录接收信号的进程 */
		struct rcu_head fa_rcu;
	};
```

通过之前的blog《linux的异步通知机制》，我们知道为了能处理协议栈发出的SIGIO信号，

用户程序需要做的事情有：  
1. 通过signal()指定SIGIO的处理函数。  
2. 设置sockfd的拥有者为本进程，如此一来本进程才能收到协议栈发出的SIGIO信号。  
3. 设置sockfd支持异步通知，即设置O_ASYNC标志。  


对应的用户程序函数调用大概如下：
```
	signal(SIGIO, my_handler); /* set new SIGIO handler */
	fcntl(sockfd, F_SETOWN, getpid()); /* set sockfd's owner process */
	oflags = fcntl(sockfd, F_GETFL); /* get old sockfd flags */
	fcntl(sockfd, F_SETFL, oflags | O_ASYNC); /* set new sockfd flags */
```

下文关注的是内核层面的一些工作：  
1. 如何把进程加入Socket的异步通知队列，或者把进程从Socket的异步通知队列中删除。  
2. 协议栈何时发送信号给Socket异步通知队列上的进程。  

#### 插入和删除

首先来看下fcntl()的系统调用。

```
	SYSCALL_DEFINE3(fcntl, unsigned int, fd, unsigned int, cmd, unsigned long, arg)
	{
		struct fd f = fdget_raw(fd);
		long err = -EBADF; /* Bad file number */

		if (! f.file)
			goto out;

		/* File is opened with O_PATH, almost nothing can be done with it */
		if (unlikely(f.file->f_mode & FMODE_PATH)) {
			if (! check_fcntl_cmd(cmd))
				goto out1;
		}

		err = security_file_fcntl(f.file, cmd, arg);
		if (! err)
			err = do_fcntl(fd, cmd, arg, f.file); /* 实际的处理函数 */

	out1:
		fdput(f);
	out:
		return err;
	}
```

```
	static long do_fcntl(int fd, unsigned int cmd, unsigned long arg, struct fil *filp)
	{
		long err = -EINVAL;

		switch(cmd) {
		...
		case F_SETFL: /* 在这里设置O_ASYNC标志 */
			err = setfl(fd, filp, arg);
			break;
		...
		case F_SETOWN: /* 在这里设置所有者进程 */
			err = f_setown(filp, arg, 1);
			break;
		....
		}

		return err;
	}
```

```
	static int setfl(int fd, struct file *filp, unsigned long arg)
	{
		...
		/* ->fasync() is responsible for setting the FASYNC bit. */
		if (((arg ^ filp->f_flags) & FASYNC) && filp->f_op->fasync) {
			error = filp->f_op->fasync(fd, filp, (arg & FASYNC) != 0);

			if (error < 0)
				goto out;
			if (error > 0)
				error = 0;
		}
		...
	}
```

Socket文件的操作函数集为socket_file_ops。

```
	static const struct file_operations socket_file_ops = {
		...
		.fasync = sock_fasync,
		...
	};
```

```
	/* Update the socket async list. */
	static int sock_fasync(int fd, struct file *filp, int on)
	{
		struct socket *sock = filp->private_data;
		struct sock *sk = sock->sk;
		struct socket_wq *wq; /* Socket的等待队列和异步通知队列 */

		if (sk == NULL)
			return -EINVAL;

		lock_sock(sk);
		wq = rcu_dereference_protected(sock->wq, sock_owned_by_user(sk));

		fasync_helper(fd, filp, on, &wq->fasync_list); /* 使用此函数来插入或删除 */

		/* 设置或取消SOCK_FASYNC标志 */
		if (! wq->fasync_list)
			sock_reset_flag(sk, SOCK_FASYNC);
		else
			sock_set_flag(sk, SOCK_FASYNC);

		release_sock(sk);

		return 0;
	}
```

和设备驱动一样，最终调用fasync_helper()来把进程插入异步通知队列，或者把进程从异步通知队列中删除。

```
	/*
	 * fasync_helper() is used by almost all character device drivers to set up the fasync
	 * queue, and for regular files by the file lease code. It returns negative on error, 0 if
	 * it did no changes and positive if it added / deleted the entry.
	 */

	int fasync_helper(int fd, struct file *filp, int on, struct fasync_struct **fapp)
	{
		if (! on)
			return fasync_remove_entry(filp, fapp); /* 插入 */

		return fasync_add_entry(fd, filp, fapp); /* 删除 */
	}
```

#### 发送信号

当Socket I/O事件触发时，协议栈会调用sk_wake_async()来进行异步通知。

函数的处理方式：

```
	enum {
		SOCK_WAKE_IO, /* 直接发送SIGIO信号 */
		SOCK_WAKE_WAITD, /* 检测应用程序是否通过recv()类调用来等待接收数据，如果没有才发送SIGIO信号 */
		SOCK_WAKE_SPACE, /* 检测sock的发送队列是否曾经到达上限，如果有的话发送SIGIO信号 */
		SOCK_WAKE_URG, /* 直接发送SIGURG信号 */
	};
```

通告的IO类型，常用的有：

```
	#define __SI_POLL 0
	#define POLL_IN (__SI_POLL | 1) /* data input available, 有接收数据可读 */
	#define POLL_OUT (__SI_POLL | 2) /* output buffers available, 有输出缓存可写 */
	#define POLL_MSG (__SI_POLL | 3) /* input message available, 有输入消息可读 */
	#define POLL_ERR (__SI_POLL | 4) /* i/0 error, I/O错误 */
	#define POLL_PRI (__SI_POLL | 5) /* high priority input available, 有紧急数据可读 */
	#define POLL_HUP (__SI_POLL | 6) /* device disconnected, 设备关闭或文件关闭，无法继续读写 */
```

how为函数的处理方式，band为通告的IO类型。

```
	static inline void sk_wake_async(struct sock *sk, int how, int band)
	{
		if (sock_flag(sk, SOCK_FASYNC)) /* sock需要支持异步通知 */
			sock_wake_async(sk->sk_socket, how, band);
	}
```

```
	int sock_wake_async(struct socket *sock, int how, int band)
	{
		struct socket_wq *wq;

		if (! sock)
			return -1;

		rcu_read_lock();
		wq = rcu_dereference(sock->wq); /* socket的等待队列和异步通知队列 */

		if (! wq || !wq->fasync_list) { /* 如果有队列没有实例 */
			rcu_read_unlock();
			return -1;
		}

		switch(how) {
		/* 检测应用程序是否通过recv()类调用来等待接收数据，如果没有才发送SIGIO信号 */
		case SOCK_WAKE_WAITD:
			if (test_bit(SOCK_ASYNC_WAITDATA, &sock->flags))
				break;
			goto call_kill;

		/* 检测sock的发送队列是否曾经到达上限，如果有的话发送SIGIO信号 */
		case SOCK_WAKE_SPACE:
			if (! test_and_clear_bit(SOCK_ASYNC_NOSPACE, &sock->flags))
				break;
		/* fall_through */

		case SOCK_WAKE_IO: /* 直接发送SIGIO信号 */
	call_kill:
				/* 发送SIGIO信号给异步通知队列上的进程，告知IO消息 */
				kill_fasync(&wq->fasync_list, SIGIO, band);
				break;

		case SOCK_WAKE_URG:
				/* 发送SIGURG信号给异步通知队列上的进程 */
				kill_fasync(&wq->fasync_list, SIGURG, band);
		}

		rcu_read_unlock();
		return 0;
	}
```

和设备驱动一样，最终调用kill_fasync()来发送信号给用户进程。

```
	void kill_fasync(struct fasync_struct **fp, int sig, int band)
	{
		/* First a quick test without locking: usually the list is empty. */
		if (*f) {
			rcu_read_lock();
			kill_fasync_rcu(rcu_dereference(*fp), sig, band);
			rcu_read_unlock();
		}
	}
```

```
	static void kill_fasync_rcu(struct fasync_struct *fa, int sig, int band)
	{
		while (fa) {
			struct fown_struct *fown;
			unsigned long flags;

			if (fa->magic != FASYNC_MAGIC) {
				printk(KERN_ERR "kill_fasync: bad magic number in fasync_struct!\n");
				return;
			}

			spin_lock_irqsave(&fa->fa_lock, flags);
			if (fa->fa_file) {
				fown = &fa->file->f_owner; /* 持有文件的进程 */

				/* Don't send SIGURG to processes which have not set a queued signum:
				 * SIGURG has its own default signalling mechanism. */

				if (! (sig == SIGURG && fown->signum == 0))
					send_sigio(fown, fa->fa_fd, band); /* 发送信号给持有文件的进程 */
			}
			spin_unlock_irqrestore(&fa->fa_lock, flags);

			fa = rcu_dereference(fa->fa_next); /* 指向下一个异步通知结构体 */
		}
	}
```

