---
layout: post
title: "linux内核中tcp连接的断开处理"
date: 2015-06-12 17:21:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://simohayha.iteye.com/blog/503856

我们这次主要来分析相关的两个断开函数close和shotdown以及相关的套接口选项SO_LINGER。这里要注意SO_LINGER对shutdown无任何影响。它只对close起作用。

先来坎SO_LINGER所对应的数据结构：

```
	struct linger {
		//linger的开关
		int     l_onoff;    /* Linger active        */
		//所等待的时间。
		int     l_linger;   /* How long to linger for   */
	};
```


这里对这个套接口选项就不详细介绍了，在unix网络编程中有详细的介绍，我们这里只会分析内核的处理代码。

首先来看close函数，我们知道缺醒情况下,close是立即返回，但是如果套接口的发送缓冲区还有未发送的数据，系统将会试着把这些数据发送给对端。而这个缺醒情况我们是可以通过SO_LINGER来改变的。还有一个要注意就是close调用并不一定会引发tcp的断开连接。因为close只是将这个socket的引用计数减一(主要是针对多个进程)，而真正要直接引发断开，则需要用shutdown函数。

内核中socket的close的系统调用是sock_close，而在sock_close中，直接调用sock_release来实现功能，因此这里我们直接看sock_release的源码：

```
	void sock_release(struct socket *sock)
	{
		if (sock->ops) {
			struct module *owner = sock->ops->owner;

			//调用inet_stream_ops的inet_release函数
			sock->ops->release(sock);
			//将ops致空。
			sock->ops = NULL;
			module_put(owner);
		}

		//这个域貌似是26.31新加的，具体做什么的还不知道。
		if (sock->fasync_list)
			printk(KERN_ERR "sock_release: fasync list not empty!\n");

		//更新全局的socket数目
		percpu_sub(sockets_in_use, 1);
		if (!sock->file) {
			//更新inode的引用计数
			iput(SOCK_INODE(sock));
			return;
		}
		sock->file = NULL;
	}
```


然后来看inet_release的实现，这个函数主要用来通过SO_LINGER套接字来得到超时时间，然后调用tcp_close来关闭sock。

```
	int inet_release(struct socket *sock)
	{
		struct sock *sk = sock->sk;

		if (sk) {
			long timeout;

			/* Applications forget to leave groups before exiting */
			ip_mc_drop_socket(sk);

			timeout = 0;
			//判断是否设置SO_LINGER并且不是处于正在shutdowning，则设置timeout为l_linger(也就是我们设置的值).
			if (sock_flag(sk, SOCK_LINGER) &&
				!(current->flags & PF_EXITING))
				timeout = sk->sk_lingertime;
			sock->sk = NULL;
			//调用tcp_close.
			sk->sk_prot->close(sk, timeout);
		}
		return 0;
	}
```

tcp_close函数比较长我们这里分段来分析它,首先来看第一部分。这里要注意几点：

1 当close掉一个服务端的父socket的时候，内核会先处理半连接队列然后是已经accept了的队列，最后才会处理父sock。

2 处理接收缓冲区的数据的时候，直接遍历receive_queue(前面blog有介绍)，然后统计未发送的socket。我们知道close是不管接收buf的，也就是他会把接收buf释放掉，然后发送rst给对端的。

3 当so_linger有设置并且超时时间为0,则发送rst给对端，并且清空发送和接收buf。这个也不会引起最终的四分组终止序列。

4 当接收缓冲区有未读数据，则直接发送rst给对端。这个也不会引起最终的四分组终止序列。

5 当so_linger有设置，并且超时不为0,或者so_linger没有设置，此时都会引起最终的四分组终止序列来终止连接。(通过send_fin来发送fin,并引发四分组终止序列).而在send_fin中会发送掉发送缓冲区中的数据。


来看代码：

```
	void tcp_close(struct sock *sk, long timeout)
	{
		struct sk_buff *skb;
		int data_was_unread = 0;
		int state;

		lock_sock(sk);
		sk->sk_shutdown = SHUTDOWN_MASK;

		//如果处于tcp_listen说明将要关闭的这个socket是一个服务端的主socket。
		if (sk->sk_state == TCP_LISTEN) {
			//设置sock状态.
			tcp_set_state(sk, TCP_CLOSE);

			//这个函数主要用来清理半连接队列(下面会简要分析这个函数)
			/* Special case. */
			inet_csk_listen_stop(sk);
			//处理要关闭的sock
			goto adjudge_to_death;
		}

		//遍历sk_receive_queue也就是输入buf队列。然后统计还没有读取的数据。
		while ((skb = __skb_dequeue(&sk->sk_receive_queue)) != NULL) {
			u32 len = TCP_SKB_CB(skb)->end_seq - TCP_SKB_CB(skb)->seq -
				  tcp_hdr(skb)->fin;
			data_was_unread += len;
			//free这个skb
			__kfree_skb(skb);
		}

		sk_mem_reclaim(sk);


		//第一个if主要是实现了rfc2525的2.17,也就是关闭的时候，如果接收buf中有未读数据，则发送一个rst给对端。(下面有摘抄相关内容)
		if (data_was_unread) {
			/* Unread data was tossed, zap the connection. */
			NET_INC_STATS_USER(sock_net(sk), LINUX_MIB_TCPABORTONCLOSE);
			//设置状态
			tcp_set_state(sk, TCP_CLOSE);
			//发送rst
			tcp_send_active_reset(sk, GFP_KERNEL);
		}
		//第二个if主要是判断so_linger套接字,并且超时时间为0。此时我们就直接丢掉所有的发送缓冲区中的数据
		else if (sock_flag(sk, SOCK_LINGER) && !sk->sk_lingertime) {
			/* Check zero linger _after_ checking for unread data. */
			//调用tcp_disconnect，这个函数主要用来断开和对端的连接，这个函数下面会介绍。
			sk->sk_prot->disconnect(sk, 0);
			NET_INC_STATS_USER(sock_net(sk), LINUX_MIB_TCPABORTONDATA);
		}
		//这个函数主要用来判断是否需要发送fin，也就是判断状态。下面我会详细介绍这个函数。
		else if (tcp_close_state(sk)) {

			//发送fin.
			tcp_send_fin(sk);
		}

		//等待一段时间。这里的timeout，如果有设置so_linger的话就是l_linger.这里主要是等待发送缓冲区的buf发送(如果超时时间不为0).
		sk_stream_wait_close(sk, timeout);
		........................

	}
```

##### rfc2525的2.17的介绍：

```
	When an application closes a connection in such a way that it can no longer read any received data, 
	the TCP SHOULD, per section 4.2.2.13 of RFC 1122, send a RST if there is any unread received data, 
	or if any new data is received. A TCP that fails to do so exhibits "Failure to RST on close with data pending".
```

ok，现在来看上面遇到的3个函数，一个是inet_csk_listen_stop,一个是tcp_close_state,一个是tcp_disconnect.我们一个个来看他们。

首先是inet_csk_listen_stop函数。我们知道这个函数主要用来清理所有的半连接队列。

```
	void inet_csk_listen_stop(struct sock *sk)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct request_sock *acc_req;
		struct request_sock *req;

		//首先删除keepalive定时器。
		inet_csk_delete_keepalive_timer(sk);

		/* make all the listen_opt local to us */
		//得到accept 队列。
		acc_req = reqsk_queue_yank_acceptq(&icsk->icsk_accept_queue);

		//然后销毁掉所有的半连接队列，也就是listen_sock队列
		reqsk_queue_destroy(&icsk->icsk_accept_queue);


		//遍历accept队列断开与对端的连接。
		while ((req = acc_req) != NULL) {
		...............................................

			//调用tcp_disconnect来断开与对端的连接。这里注意是非阻塞的。
			sk->sk_prot->disconnect(child, O_NONBLOCK);

			sock_orphan(child);

			percpu_counter_inc(sk->sk_prot->orphan_count);

			//销毁这个sock。
			inet_csk_destroy_sock(child);

			........................................
		}
		WARN_ON(sk->sk_ack_backlog);
	}
```

接下来来看tcp_disconnect函数。这个函数主要用来断开和对端的连接.它会释放读写队列，发送rst，清除定时器等等一系列操作。

```
	int tcp_disconnect(struct sock *sk, int flags)
	{
		struct inet_sock *inet = inet_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);
		int err = 0;
		int old_state = sk->sk_state;

		if (old_state != TCP_CLOSE)
			tcp_set_state(sk, TCP_CLOSE);
		...................

		//清除定时器，重传，delack等。
		tcp_clear_xmit_timers(sk);
		//直接free掉接收buf。
		__skb_queue_purge(&sk->sk_receive_queue);
		//free掉写buf。
		tcp_write_queue_purge(sk);
		__skb_queue_purge(&tp->out_of_order_queue);
	#ifdef CONFIG_NET_DMA
		__skb_queue_purge(&sk->sk_async_wait_queue);
	#endif

		inet->dport = 0;

		if (!(sk->sk_userlocks & SOCK_BINDADDR_LOCK))
			inet_reset_saddr(sk);
			..........................................
		//设置状态。
		tcp_set_ca_state(sk, TCP_CA_Open);
		//清理掉重传的一些标记
		tcp_clear_retrans(tp);
		inet_csk_delack_init(sk);
		tcp_init_send_head(sk);
		memset(&tp->rx_opt, 0, sizeof(tp->rx_opt));
		__sk_dst_reset(sk);

		WARN_ON(inet->num && !icsk->icsk_bind_hash);

		sk->sk_error_report(sk);
		return err;
	}
```

紧接着是tcp_close_state函数这个函数就是用来判断是否应该发送fin:

```
	//这个数组表示了当close后，tcp的状态变化，可以看到注释很清楚，包含了3部分。这里也就是通过current也就是tcp的状态取得new state也就是close的状态，然后再和TCP_ACTION_FIN按位于，得到action
	static const unsigned char new_state[16] = {
	  /* current state:        new state:      action:  */
	  /* (Invalid)      */ TCP_CLOSE,
	  /* TCP_ESTABLISHED    */ TCP_FIN_WAIT1 | TCP_ACTION_FIN,
	  /* TCP_SYN_SENT   */ TCP_CLOSE,
	  /* TCP_SYN_RECV   */ TCP_FIN_WAIT1 | TCP_ACTION_FIN,
	  /* TCP_FIN_WAIT1  */ TCP_FIN_WAIT1,
	  /* TCP_FIN_WAIT2  */ TCP_FIN_WAIT2,
	  /* TCP_TIME_WAIT  */ TCP_CLOSE,
	  /* TCP_CLOSE      */ TCP_CLOSE,
	  /* TCP_CLOSE_WAIT */ TCP_LAST_ACK  | TCP_ACTION_FIN,
	  /* TCP_LAST_ACK   */ TCP_LAST_ACK,
	  /* TCP_LISTEN     */ TCP_CLOSE,
	  /* TCP_CLOSING    */ TCP_CLOSING,
	};

	static int tcp_close_state(struct sock *sk)
	{
		//取得new state
		int next = (int)new_state[sk->sk_state];
		int ns = next & TCP_STATE_MASK;

		tcp_set_state(sk, ns);

		//得到action
		return next & TCP_ACTION_FIN;
	}
```

接下来来看tcp_close的剩余部分的代码，剩下的部分就是处理一些状态以及通知这里只有一个要注意的就是TCP_LINGER2这个套接字，这个套接字能够设置等待fin的超时时间，也就是tcp_sock的域linger2.我们知道系统还有一个sysctl_tcp_fin_timeout，也就是提供了一个sys文件系统的接口来修改这个值，不过我们如果设置linger2为一个大于0的值的话，内核就会取linger2这个值。

```
	adjudge_to_death:

		//得到sock的状态。
		state = sk->sk_state;
		sock_hold(sk);
		sock_orphan(sk);

		//唤醒阻塞在这个sock的队列(前面有详细介绍这个函数)
		release_sock(sk);

		local_bh_disable();
		bh_lock_sock(sk);
		WARN_ON(sock_owned_by_user(sk));

		//全局的cpu变量引用计数减一。
		percpu_counter_inc(sk->sk_prot->orphan_count);

		/* Have we already been destroyed by a softirq or backlog? */
		if (state != TCP_CLOSE && sk->sk_state == TCP_CLOSE)
			goto out;

		//如果状态为TCP_FIN_WAIT2,说明接收了ack，在等待对端的fin。
		if (sk->sk_state == TCP_FIN_WAIT2) {
			struct tcp_sock *tp = tcp_sk(sk);
			//超时时间小于0,则说明马上超时，设置状态为tcp_close,然后发送rst给对端。
			if (tp->linger2 < 0) {
				tcp_set_state(sk, TCP_CLOSE);
				tcp_send_active_reset(sk, GFP_ATOMIC);
				NET_INC_STATS_BH(sock_net(sk),
						LINUX_MIB_TCPABORTONLINGER);
			} else {
				//得到等待fin的超时时间。这里主要也就是在linger2和sysctl_tcp_fin_timeout中来取得。
				const int tmo = tcp_fin_time(sk);
				//如果超时时间太长，则启动keepalive定时器发送探测报。
				if (tmo > TCP_TIMEWAIT_LEN) {
					inet_csk_reset_keepalive_timer(sk,
							tmo - TCP_TIMEWAIT_LEN);
				} else {
					//否则进入time_wait状态。
					tcp_time_wait(sk, TCP_FIN_WAIT2, tmo);
					goto out;
				}
			}
		}
		......................................

		//如果sk的状态为tcp_close则destroy掉这个sk
		if (sk->sk_state == TCP_CLOSE)
			inet_csk_destroy_sock(sk);
		/* Otherwise, socket is reprieved until protocol close. */

	out:
		bh_unlock_sock(sk);
		local_bh_enable();
		sock_put(sk);
	}
```

然后来看send_fin的实现，这个函数用来发送一个fin，并且尽量发送完发送缓冲区中的数据：

```
	void tcp_send_fin(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		//取得写bufer的尾部。
		struct sk_buff *skb = tcp_write_queue_tail(sk);
		int mss_now;

		/* Optimization, tack on the FIN if we have a queue of
		 * unsent frames.  But be careful about outgoing SACKS
		 * and IP options.
		 */
		mss_now = tcp_current_mss(sk);
		//如果发送队列不为空，此时我们只需要设置sk buffer的标记位(也就是tcp报文的控制位为fin)，可以看到我们是加到写buffer的尾部，这里是为了能尽量将写buffer中的数据全部传出)
		if (tcp_send_head(sk) != NULL) {
			TCP_SKB_CB(skb)->flags |= TCPCB_FLAG_FIN;
			TCP_SKB_CB(skb)->end_seq++;
			tp->write_seq++;
		} else {
		..................................
			//到这里标明发送缓冲区位空，因此我们需要新建一个sk buffer，然后设置标记位，并加入到写buffer。
			skb_reserve(skb, MAX_TCP_HEADER);
			/* FIN eats a sequence byte, write_seq advanced by tcp_queue_skb(). */
			tcp_init_nondata_skb(skb, tp->write_seq,
						 TCPCB_FLAG_ACK | TCPCB_FLAG_FIN);
			tcp_queue_skb(sk, skb);
		}
		//发送写缓冲区中的数据。
		__tcp_push_pending_frames(sk, mss_now, TCP_NAGLE_OFF);
	}
	void __tcp_push_pending_frames(struct sock *sk, unsigned int cur_mss,
					   int nonagle)
	{
		struct sk_buff *skb = tcp_send_head(sk);

		if (!skb)
			return;

		/* If we are closed, the bytes will have to remain here.
		 * In time closedown will finish, we empty the write queue and
		 * all will be happy.
		 */
		if (unlikely(sk->sk_state == TCP_CLOSE))
			return;
		//发送数据，这里关闭了nagle。也就是立即将数据全部发送出去(我前面的blog有详细解释这个函数).
		if (tcp_write_xmit(sk, cur_mss, nonagle, 0, GFP_ATOMIC))
			tcp_check_probe_timer(sk);
	}
```

#### 接下来来看shutdown的实现。在2.26.31中，系统调用的实现有些变化。

这里我们要知道shutdown会将写缓冲区的数据发出，然后唤醒阻塞的进程，来读取读缓冲区中的数据。


这个系统调用所对应的内核函数就是os_shutdown_socket。

```
	#define SHUT_RD 0
	#define SHUT_WR 1
	#define SHUT_RDWR 2

	int os_shutdown_socket(int fd, int r, int w)
	{
		int what, err;

		if (r && w)
			what = SHUT_RDWR;
		else if (r)
			what = SHUT_RD;
		else if (w)
			what = SHUT_WR;
		else
			return -EINVAL;

		//调用socket的shutdown也就是kernel_sock_shutdown
		err = shutdown(fd, what);
		if (err < 0)
			return -errno;
		return 0;
	}


	int kernel_sock_shutdown(struct socket *sock, enum sock_shutdown_cmd how)
	{
		//他最终会调用inet_shutdown
		return sock->ops->shutdown(sock, how);
	}
```

来看inet_shutdown的实现.这个函数的主要工作就是通过判断sock的状态不同来调用相关的函数：

```
	int inet_shutdown(struct socket *sock, int how)
	{
		struct sock *sk = sock->sk;
		int err = 0;

		/* This should really check to make sure
		 * the socket is a TCP socket. (WHY AC...)
		 */
		//这里要注意每个how都是加1的，这说明在内核里读写是为1,2,3
		how++; /* maps 0->1 has the advantage of making bit 1 rcvs and
				   1->2 bit 2 snds.
				   2->3 */
		//判断how的合法性。
		if ((how & ~SHUTDOWN_MASK) || !how) /* MAXINT->0 */
			return -EINVAL;
		//锁住sock
		lock_sock(sk);

		//SS_CONNECTING说明这个sock的连接正在处理中。state域表示socket当前的内部状态
		if (sock->state == SS_CONNECTING) {
			//如果状态为这几个状态，说明是处于半连接处理阶段，此时设置状态为SS_DISCONNECTING
			if ((1 << sk->sk_state) &
				(TCPF_SYN_SENT | TCPF_SYN_RECV | TCPF_CLOSE))
				sock->state = SS_DISCONNECTING;
			else
				//否则设置为连接完毕
				sock->state = SS_CONNECTED;
		}

		//除过TCP_LISTEN以及TCP_SYN_SENT状态外的其他状态最终都会进入sk->sk_prot->shutdown也就是tcp_shutdown函数。

		switch (sk->sk_state) {
		//如果状态为tco_close则设置错误号，然后进入default处理
		case TCP_CLOSE:
			err = -ENOTCONN;
			/* Hack to wake up other listeners, who can poll for
			   POLLHUP, even on eg. unconnected UDP sockets -- RR */
		default:
			sk->sk_shutdown |= how;
			if (sk->sk_prot->shutdown)
				sk->sk_prot->shutdown(sk, how);
			break;

		/* Remaining two branches are temporary solution for missing
		 * close() in multithreaded environment. It is _not_ a good idea,
		 * but we have no choice until close() is repaired at VFS level.
		 */
		case TCP_LISTEN:
			//如果不为SHUT_RD则跳出switch，否则进入tcp_syn_sent的处理。
			if (!(how & RCV_SHUTDOWN))
				break;
			/* Fall through */
		case TCP_SYN_SENT:
			//断开连接，然后设置state
			err = sk->sk_prot->disconnect(sk, O_NONBLOCK);
			sock->state = err ? SS_DISCONNECTING : SS_UNCONNECTED;
			break;
		}

		/* Wake up anyone sleeping in poll. */
		//唤醒阻塞在这个socket上的进程，这里是为了将读缓冲区的数据尽量读完。
		sk->sk_state_change(sk);
		release_sock(sk);
		return err;
	}
```

来看tcp_shutdown函数。

这里要注意，当只关闭读的话，并不会引起发送fin，也就是只会设置个标记，然后在读取数据的时候返回错误。而关闭写端，则就会引起发送fin。
```
	void tcp_shutdown(struct sock *sk, int how)
	{
		/*  We need to grab some memory, and put together a FIN,
		 *  and then put it into the queue to be sent.
		 *      Tim MacKenzie(tym@dibbler.cs.monash.edu.au) 4 Dec '92.
		 */
		//如果为SHUT_RD则直接返回。
		if (!(how & SEND_SHUTDOWN))
			return;

		/* If we've already sent a FIN, or it's a closed state, skip this. */
		//这里英文注释很详细我就不多解释了。
		if ((1 << sk->sk_state) &
			(TCPF_ESTABLISHED | TCPF_SYN_SENT |
			 TCPF_SYN_RECV | TCPF_CLOSE_WAIT)) {
			/* Clear out any half completed packets.  FIN if needed. */
			//和tcp_close那边处理一样
			if (tcp_close_state(sk))
				tcp_send_fin(sk);
		}
	}
```

最后来看sock_def_readable它就是sk->sk_state_change。也就是用来唤醒阻塞的进程。

```
	static void sock_def_readable(struct sock *sk, int len)
	{
		read_lock(&sk->sk_callback_lock);
		//判断是否有进程在等待这个sk
		if (sk_has_sleeper(sk))
		//有的话，唤醒进程，这里可以看到递交给上层的是POLLIN,也就是读事件。
		wake_up_interruptible_sync_poll(sk->sk_sleep, POLLIN |
							POLLRDNORM | POLLRDBAND);

		//这里异步唤醒，可以看到这里也是POLL_IN.
		sk_wake_async(sk, SOCK_WAKE_WAITD, POLL_IN);
		read_unlock(&sk->sk_callback_lock);
	}
```

可以看到shutdown函数只会处理SEND_SHUTDOWN。并且当调用shutdown之后，读缓冲区，还可以继续读取。


