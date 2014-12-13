---
layout: post
title: "内核tcp的定时器管理"
date: 2013-09-27 16:11:00 +0800
comments: false
categories:
- 2013
- 2013~09
- kernel
- kernel~net
tags:
---
##### 在内核中tcp协议栈有6种类型的定时器：
```
1 重传定时器。
2 delayed ack定时器
3 零窗口探测定时器
上面三种定时器都是作为tcp状态机的一部分来实现的。
4 keep-alive 定时器 主要是管理established状态的连接。
5 time_wait定时器 主要是用来客户端关闭时的time_wait状态用到。
6 syn-ack定时器(主要是用在listening socket) 管理新的连接请求时所用到。
```

##### 而在内核中，tcp协议栈管理定时器主要有下面4个函数：
```
inet_csk_reset_xmit_timer	这个函数是用来重启定时器
inet_csk_clear_xmit_timer	这个函数用来删除定时器。
上面两个函数都是针对状态机里面的定时器。
tcp_set_keepalive	这个函数是用来管理keepalive 定时器的接口。
tcp_synack_timer	这个函数是用来管理syn_ack定时器的接口。
```

##### 先来看定时器的初始化。
首先是在tcp_v4_init_sock中对定时器的初始化，它会调用tcp_init_xmit_timers，我们就先来看这个函数：
```
	void tcp_init_xmit_timers(struct sock *sk)
	{
		inet_csk_init_xmit_timers(sk, &tcp_write_timer, &tcp_delack_timer, &tcp_keepalive_timer);
	}
```
可以看到这个函数很简单，就是调用inet_csk_init_xmit_timers,然后把3个定时器的回掉函数传递进去，下面我们来看inet_csk_init_xmit_timers。
```
	void inet_csk_init_xmit_timers(struct sock *sk,
						void (*retransmit_handler)(unsigned long),
						void (*delack_handler)(unsigned long),
						void (*keepalive_handler)(unsigned long))
	{
		struct inet_connection_sock *icsk = inet_csk(sk);

		//安装定时器，设置定时器的回掉函数。
		setup_timer(&icsk->icsk_retransmit_timer, retransmit_handler, (unsigned long)sk);
		setup_timer(&icsk->icsk_delack_timer, delack_handler, (unsigned long)sk);
		setup_timer(&sk->sk_timer, keepalive_handler, (unsigned long)sk);
		icsk->icsk_pending = icsk->icsk_ack.pending = 0;
	}
```
我 们可以看到icsk->icsk_retransmit_timer定时器，也就是重传定时器的回调函数是tcp_write_timer,而 icsk->icsk_delack_timer定时器也就是delayed-ack 定时器的回调函数是tcp_delack_timer,最后sk->sk_timer也就是keepalive定时器的回掉函数是 tcp_keepalive_timer.  
这里还有一个要注意的，tcp_write_timer还会处理0窗口定时器。  
这里有关内核定时器的一些基础的东西我就不介绍了，想了解的可以去看下ldd第三版。  
接下来我们就来一个个的分析这6个定时器，首先是重传定时器。  
我们知道4层最终调用tcp_xmit_write来讲数据发送到3层，并且tcp是字节流的，因此每次他总是发送一段数据到3层，而每次当它发送完毕(返回正确),则它就会启动重传定时器，我们来看代码：
```
	static int tcp_write_xmit(struct sock *sk, unsigned int mss_now, int nonagle,
				  int push_one, gfp_t gfp)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;
		unsigned int tso_segs, sent_pkts;
		int cwnd_quota;
		int result;

	.............................................

		while ((skb = tcp_send_head(sk))) {
	..................................................

			//可以看到只有当传输成功，我们才会走到下面的函数。
			if (unlikely(tcp_transmit_skb(sk, skb, 1, gfp)))
				break;

			/* Advance the send_head.  This one is sent out.
			 * This call will increment packets_out.
			 */
			//最终在这个函数中启动重传定时器。
			tcp_event_new_data_sent(sk, skb);

			tcp_minshall_update(tp, mss_now, skb);
			sent_pkts++;

			if (push_one)
				break;
		}
	...........................
	}
```
现在我们来看tcp_event_new_data_sent,如何启动定时器的.
```
	static void tcp_event_new_data_sent(struct sock *sk, struct sk_buff *skb)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		unsigned int prior_packets = tp->packets_out;

		tcp_advance_send_head(sk, skb);
		tp->snd_nxt = TCP_SKB_CB(skb)->end_seq;

		/* Don't override Nagle indefinately with F-RTO */
		if (tp->frto_counter == 2)
			tp->frto_counter = 3;
		//关键在这里.
		tp->packets_out += tcp_skb_pcount(skb);
		if (!prior_packets)
			inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS, inet_csk(sk)->icsk_rto, TCP_RTO_MAX);
	}
```
可以看到只有当prior_packets为0时才会重启定时器,而prior_packets则是发送未确认的段的个数,也就是说如果发送了很多段,如果前面的段没有确认,那么后面发送的时候不会重启这个定时器.  
我们要知道，定时器的间隔是通过rtt来得到的，具体的算法，可以看下tcp/ip详解。  
当 启动了重传定时器，我们就会等待ack的到来，如果超时还没到来，那么就调用重传定时器的回调函数，否则最终会调用tcp_rearm_rto来删除或者 重启定时器，这个函数是在tcp_ack()->tcp_clean_rtx_queue()中被调用的。tcp_ack是专门用来处理ack。  
这个函数很简单，就是通过判断packets_out，这个值表示当前还未确认的段的个数。然后来进行相关操作。  
```
	static void tcp_rearm_rto(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);

		//为0说明所有的传输的段都已经acked。此时remove定时器。否则重启定时器。
		if (!tp->packets_out) {
			inet_csk_clear_xmit_timer(sk, ICSK_TIME_RETRANS);
		} else {
			inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS,
						  inet_csk(sk)->icsk_rto, TCP_RTO_MAX);
		}
	}
```
  接下来来看tcp_write_timer的实现。这个函数主要是通过icsk->icsk_pending来判断是那个定时器导致超时，这里只有两 种，一种是ICSK_TIME_RETRANS，也就是重传定时器，另一种是ICSK_TIME_PROBE0也就是0窗口定时器。
```
	#define ICSK_TIME_RETRANS   1   /* Retransmit timer */
	#define ICSK_TIME_PROBE0    3   /* Zero window probe timer */
	static void tcp_write_timer(unsigned long data)
	{
		struct sock *sk = (struct sock *)data;
		struct inet_connection_sock *icsk = inet_csk(sk);
		int event;

		//首先加锁。
		bh_lock_sock(sk);
		//如果是进程空间则什么也不做。
		if (sock_owned_by_user(sk)) {
			/* Try again later */
			sk_reset_timer(sk, &icsk->icsk_retransmit_timer, jiffies + (HZ / 20));
			goto out_unlock;
		}

		//如果状态为close或者icsk_pending为空，则什么也不做。
		if (sk->sk_state == TCP_CLOSE || !icsk->icsk_pending)
			goto out;
		//如果超时时间已经过了，则重启定时器。

		if (time_after(icsk->icsk_timeout, jiffies)) {
			sk_reset_timer(sk, &icsk->icsk_retransmit_timer, icsk->icsk_timeout);
			goto out;
		}
		//取出定时器类型。
		event = icsk->icsk_pending;
		icsk->icsk_pending = 0;

		//通过判断event来确定进入那个函数进行处理。
		switch (event) {
		case ICSK_TIME_RETRANS:
			tcp_retransmit_timer(sk);
			break;
		case ICSK_TIME_PROBE0:
			tcp_probe_timer(sk);
			break;
		}
		TCP_CHECK_TIMER(sk);

	out:
		sk_mem_reclaim(sk);
	out_unlock:
		bh_unlock_sock(sk);
		sock_put(sk);
	}
```
我们这里只看重传定时器，0窗口定时器后面紧接着会介绍。  
tcp_retransmit_timer,这个函数用来处理数据段的重传。  
这里要注意，重传的时候为了防止确认二义性，使用karn算法，也就是定时器退避策略。下面的代码最后部分会修改定时器的值，这里是增加一倍。
```
	static void tcp_retransmit_timer(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);

		//如果没有需要确认的段，则什么也不做。
		if (!tp->packets_out)
			goto out;

		WARN_ON(tcp_write_queue_empty(sk));

		/**首先进行一些合法性判断，其中:
		 * snd_wnd为窗口大小。
		 * sock_flag用来判断sock的状态。
		 * 最后一个判断是当前的连接状态不能处于syn_sent和syn_recv状态,也就是连接还未建
		 * 立状态.
		if (!tp->snd_wnd && !sock_flag(sk, SOCK_DEAD) &&
			!((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV))) {
			//tcp_time_stamp也就是jifes，而rcv_tstamp表示最后一个ack接收的时间，也就是最后一次对端确认的时间。因此这两个时间之差不能大于tcp_rto_max,因为tcp_rto_max为我们重传定时器的间隔时间的最大值。
			if (tcp_time_stamp - tp->rcv_tstamp > TCP_RTO_MAX) {
				tcp_write_err(sk);
				goto out;
			}
			//这个函数用来进入loss状态，也就是进行一些拥塞以及流量的控制。
			tcp_enter_loss(sk, 0);
			//现在开始重传skb。
			tcp_retransmit_skb(sk, tcp_write_queue_head(sk));
			__sk_dst_reset(sk);
			//然后重启定时器，继续等待ack的到来。
			goto out_reset_timer;
		}

		//程序到达这里说明上面的校验失败，因此下面这个函数用来判断我们重传需要的次数。如果超过了重传次数，直接跳转到out。
		if (tcp_write_timeout(sk))
			goto out;

		//到达这里说明我们重传的次数还没到。icsk->icsk_retransmits表示重传的次数。
		if (icsk->icsk_retransmits == 0) {
			//这里其实也就是收集一些统计信息。
			int mib_idx;

			if (icsk->icsk_ca_state == TCP_CA_Disorder) {
				if (tcp_is_sack(tp))
					mib_idx = LINUX_MIB_TCPSACKFAILURES;
				else
					mib_idx = LINUX_MIB_TCPRENOFAILURES;
			} else if (icsk->icsk_ca_state == TCP_CA_Recovery) {
				if (tcp_is_sack(tp))
					mib_idx = LINUX_MIB_TCPSACKRECOVERYFAIL;
				else
					mib_idx = LINUX_MIB_TCPRENORECOVERYFAIL;
			} else if (icsk->icsk_ca_state == TCP_CA_Loss) {
				mib_idx = LINUX_MIB_TCPLOSSFAILURES;
			} else {
				mib_idx = LINUX_MIB_TCPTIMEOUTS;
			}
			NET_INC_STATS_BH(sock_net(sk), mib_idx);
		}

		//是否使用f-rto算法。
		if (tcp_use_frto(sk)) {
			tcp_enter_frto(sk);
		} else {
			//否则处理sack.
			tcp_enter_loss(sk, 0);
		}

		// 再次尝试重传队列的第一个段。
		if (tcp_retransmit_skb(sk, tcp_write_queue_head(sk)) > 0) {
			//重传失败。
			if (!icsk->icsk_retransmits)
				icsk->icsk_retransmits = 1;
			inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS,
						  min(icsk->icsk_rto, TCP_RESOURCE_PROBE_INTERVAL),
						  TCP_RTO_MAX);
			goto out;
		}
		//icsk->icsk_backoff主要用在零窗口定时器。
		icsk->icsk_backoff++;
		//icsk_retransmits也就是重试次数。
		icsk->icsk_retransmits++;

	out_reset_timer:
		//计算rto，并重启定时器，这里使用karn算法，也就是下次超时时间增加一倍/
		icsk->icsk_rto = min(icsk->icsk_rto << 1, TCP_RTO_MAX);
		//重启定时器，可以看到超时时间就是我们上面的icsk_rto.
		inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS, icsk->icsk_rto, TCP_RTO_MAX);
		if (icsk->icsk_retransmits > sysctl_tcp_retries1)
			__sk_dst_reset(sk);

	out:;
	}
```
下面我们来看tcp_write_timeout，它用来判断重传次数是否已经到了。这里主要分为两个分支，一个是状态为syn_sent或者syn_recv状态，一个是另外的状态。而这里系统设置的重传次数一共有4种。  
1 sysctl_tcp_syn_retries，它表示syn分节的重传次数。  
2 sysctl_tcp_retries1 它表示的是最大的重试次数，当超过了这个值，我们就需要检测路由表了。  
3 sysctl_tcp_retries2 这个值也是表示重试最大次数，只不过这个值一般要比上面的值大。和上面那个不同的是，当重试次数超过这个值，我们就必须放弃重试了。  
4 sysctl_tcp_orphan_retries 主要是针对孤立的socket(也就是已经从进程上下文中删除了，可是还有一些清理工作没有完成).对于这种socket，我们重试的最大的次数就是它。  
下面来看代码：
```
	static int tcp_write_timeout(struct sock *sk)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		//retry_untry表示我们需要重传的最大次数。
		int retry_until;

		//判断socket状态。
		if ((1 << sk->sk_state) & (TCPF_SYN_SENT | TCPF_SYN_RECV)) {
			if (icsk->icsk_retransmits)
				dst_negative_advice(&sk->sk_dst_cache);
			//设置重传最大值
			retry_until = icsk->icsk_syn_retries ? : sysctl_tcp_syn_retries;
		} else {
			//是否需要检测路由表。
			if (icsk->icsk_retransmits >= sysctl_tcp_retries1) {
				/* Black hole detection */
				tcp_mtu_probing(icsk, sk);

				dst_negative_advice(&sk->sk_dst_cache);
			}
			//设置重传最大次数为sysctl_tcp_retries2
			retry_until = sysctl_tcp_retries2;
			if (sock_flag(sk, SOCK_DEAD)) {
				//表示是一个孤立的socket。
				const int alive = (icsk->icsk_rto < TCP_RTO_MAX);

				//从tcp_orphan_retries(这个函数中会通过sysctl_tcp_orphan_retries来进行计算)中取得重传最大次数。
				retry_until = tcp_orphan_retries(sk, alive);

				if (tcp_out_of_resources(sk, alive || icsk->icsk_retransmits < retry_until))
					return 1;
			}
		}

		//最终进行判断，如果重传次数已到则返回1,否则为0.
		if (icsk->icsk_retransmits >= retry_until) {
			/* Has it gone just too far? */
			tcp_write_err(sk);
			return 1;
		}
		return 0;
	}
```
下面来介绍下tcp_enter_loss，这个函数主要用来标记丢失的段(也就是没有acked的段),然后通过执行slow start来降低传输速率.  
有关slow start以及Congestion avoidance算法描述可以看rfc2001:  
http://www.faqs.org/rfcs/rfc2001.html

下面4个算法主要是用来对拥塞进行控制的，这四个算法其实都是彼此相连的。slow start和Congestion avoidance使用了相同的机制，他们都涉及到了拥塞窗口的定义。其中拥塞窗口限制着传输的长度，它的大小根据拥塞程度上升或者下降。  
```
Slow start
Congestion avoidance
Fast re-transmit
Fast recovery
```
然后下面主要是介绍了slow start和Congestion avoidance的一些实现细节。
```
CWND - Sender side limit
RWND - Receiver side limit
Slow start threshold ( SSTHRESH ) - Used to determine whether slow start is used or congestion avoidance
When starting, probe slowly - IW <= 2 * SMSS
Initial size of SSTHRESH can be arbitrarily high, as high as the RWND
Use slow start when SSTHRESH > CWND. Else, use Congestion avoidance
Slow start - CWND is increased by an amount less than or equal to the SMSS for every ACK
Congestion avoidance - CWND += SMSS*SMSS/CWND
When loss is detected - SSTHRESH = max( FlightSize/2, 2*SMSS )
```
这里要注意在slow start中，窗口的大小是指数级的增长的。并且当cwnd(拥塞窗口)小于等于ssthresh，就是slow start模式，否则就执行Congestion avoidance。

##### 现在我们来看tcp_enter_loss的实现。
首先来介绍下下面要用到的几个关键域的含义。  
1 icsk->icsk_ca_state 这个域表示拥塞控制的状态。  
2 tp->snd_una 这个域表示tcp滑动窗口中的发送未确认的第一个字节的序列号。  
3 tp->prior_ssthresh 这个域表示前一个snd_ssthresh得大小，也就是说每次改变snd_ssthresh前都要保存老的snd_ssthresh到这个域。  
4 tp->snd_ssthresh  slow start开始时的threshold大小  
5 tp->snd_cwnd_cnt 这个域表示拥塞窗口的大小。  
6 TCP_SKB_CB(skb)->sacked tcp数据中的sack标记。  
7 tp->high_seq 拥塞开始时，snd_nxt的大小。  
```
	void tcp_enter_loss(struct sock *sk, int how)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;


		/* 1 拥塞控制状态小于TCP_CA_Disorder
		 * 2 发送未确认的序列号等于拥塞开始时的下一个将要发送的序列号
		 * 3 状态为TCP_CA_Loss，并且还未重新传输过。
		 * 如果有一个满足说明有数据丢失,因此降低threshold。
		 */
		if (icsk->icsk_ca_state <= TCP_CA_Disorder || tp->snd_una == tp->high_seq ||
			(icsk->icsk_ca_state == TCP_CA_Loss && !icsk->icsk_retransmits)) {
			//保存老的snd_ssthresh。
			tp->prior_ssthresh = tcp_current_ssthresh(sk);
			//减小snd_ssthresh
			tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk);
			//设置拥塞状态。
			tcp_ca_event(sk, CA_EVENT_LOSS);
		}

		//设置拥塞窗口大小
		tp->snd_cwnd    = 1;
		tp->snd_cwnd_cnt   = 0;
		//设置时间
		tp->snd_cwnd_stamp = tcp_time_stamp;

		tp->bytes_acked = 0;
		//清空所有相关的计数器。
		tcp_clear_retrans_partial(tp);

		if (tcp_is_reno(tp))
			tcp_reset_reno_sack(tp);

		if (!how) {
			/* Push undo marker, if it was plain RTO and nothing
			 * was retransmitted. */
			tp->undo_marker = tp->snd_una;
		} else {
			tp->sacked_out = 0;
			tp->fackets_out = 0;
		}
		tcp_clear_all_retrans_hints(tp);

		//遍历sock的write队列。
		tcp_for_write_queue(skb, sk) {
			if (skb == tcp_send_head(sk))
				break;
			//判断sack段。
			if (TCP_SKB_CB(skb)->sacked & TCPCB_RETRANS)
				tp->undo_marker = 0;
			TCP_SKB_CB(skb)->sacked &= (~TCPCB_TAGBITS)|TCPCB_SACKED_ACKED;

			//如果how为1,则说明不管sack段，此时标记所有的段为丢失(sack的意思去看tcp/ip详解).
			if (!(TCP_SKB_CB(skb)->sacked&TCPCB_SACKED_ACKED) || how) {
				//设置sack段。
				TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_ACKED;
				TCP_SKB_CB(skb)->sacked |= TCPCB_LOST;
				//update 相关的域。
				tp->lost_out += tcp_skb_pcount(skb);
				tp->retransmit_high = TCP_SKB_CB(skb)->end_seq;
			}
		}
		tcp_verify_left_out(tp);
		//设置当前的reordering的长度
		tp->reordering = min_t(unsigned int, tp->reordering,
					   sysctl_tcp_reordering);
		//设置拥塞状态。
		tcp_set_ca_state(sk, TCP_CA_Loss);
		tp->high_seq = tp->snd_nxt;
		//由于我们修改了拥塞窗口，因此设置ecn状态。
		TCP_ECN_queue_cwr(tp);
		/* Abort F-RTO algorithm if one is in progress */
		tp->frto_counter = 0;
	}
```
接 下来来看零窗口探测定时器。至于为什么会出现零窗口，这里就不阐述了，详细的可以去看tcp/ip详解。我们知道当0窗口之后,客户机会等待服务器端的窗 口打开报文，可是由于ip是不可靠的，有可能这个报文会丢失，因此就需要客户机发送一个探测段，用来提醒服务器及时汇报当前的窗口大小。这里我们知道当对 端接收窗口关闭后，我们这边的发送窗口也会关闭，此时不能发送任何一般的数据，除了探测段。  
在内核中是通过tcp_ack_probe来控制零窗口的定时器的。也就是说接收到对端的窗口报告数据后，会进入这个函数。我们来看实现：  
```
	static void tcp_ack_probe(struct sock *sk)
	{
		const struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);


		//首先判断是否对端的接收窗口是否已经有空间。
		if (!after(TCP_SKB_CB(tcp_send_head(sk))->end_seq, tcp_wnd_end(tp))) {
			//如果有空间则删除零窗口探测定时器。
			icsk->icsk_backoff = 0;
			inet_csk_clear_xmit_timer(sk, ICSK_TIME_PROBE0);
			/* Socket must be waked up by subsequent tcp_data_snd_check().
			 * This function is not for random using!
			 */
		} else {
			//否则启动定时器。
			inet_csk_reset_xmit_timer(sk, ICSK_TIME_PROBE0,
						  min(icsk->icsk_rto << icsk->icsk_backoff, TCP_RTO_MAX),
						  TCP_RTO_MAX);
		}
	}
```
我们知道零窗口定时器和重传的定时器是一个定时器，只不过在回调函数中，进行event判断，从而进入不同的处理。而它调用的是tcp_probe_timer函数。  
这个函数主要就是用来发送探测包，我们来看它的实现：  
```
	static void tcp_probe_timer(struct sock *sk)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);
		int max_probes;
		/* 1 tp->packets_out不为0说明，当定时器被安装之后，对端的接收窗口已经被打开。这* 时就不需要传输探测包。
		 * 2 tcp_send_head用来检测是否有新的段被传输。
		 * 如果上面有一个满足，则不需要发送探测包，并直接返回。
		 */
		if (tp->packets_out || !tcp_send_head(sk)) {
			icsk->icsk_probes_out = 0;
			return;
		}

		//设置最大的重试次数。
		max_probes = sysctl_tcp_retries2;

		//这里的处理和上面的tcp_write_timeout很类似。
		if (sock_flag(sk, SOCK_DEAD)) {
			const int alive = ((icsk->icsk_rto << icsk->icsk_backoff) < TCP_RTO_MAX);

			max_probes = tcp_orphan_retries(sk, alive);

			if (tcp_out_of_resources(sk, alive || icsk->icsk_probes_out <= max_probes))
				return;
		}

		//如果重试次数大于最大的重试次数，则报错。
		if (icsk->icsk_probes_out > max_probes) {
			tcp_write_err(sk);
		} else {
			/* Only send another probe if we didn't close things up. */
		//否则发送探测包。这个函数里面会发送探测包，并重启定时器。
			tcp_send_probe0(sk);
		}
	}
```
然 后来看delay ack定时器。所谓的delay ack也就是ack不会马上发送，而是等待一段时间和数据一起发送，这样就减少了一个数据包的发送。这里一般是将ack包含在tcp option中发送的。这里的定时器就是用来控制这段时间，如果定时器到期，都没有数据要发送给对端，此时单独发送这个ack。如果在定时器时间内，有数 据要发送，此时这个ack和数据一起发送给对端。  
前面我们知道delay ack定时器的回调函数是tcp_delack_timer。在分析这个函数之前，我们先来看下这个定时器是什么时候被启动的。  
首先我们知道内核接收数据都是在tcp_rcv_eastablished实现的，当我们接收完数据后，此时进入是否进行delay ack.  
在tcp_rcv_eastablished最终会调用__tcp_ack_snd_check进行判断。  
可以看到这个函数很简单，就是判断是否需要发送delay ack，如果是则tcp_send_delayed_ack，否则直接发送ack恢复给对端。
```
	static void __tcp_ack_snd_check(struct sock *sk, int ofo_possible)
	{
		struct tcp_sock *tp = tcp_sk(sk);

	/* 1 第一个判断表示多于一个的段在等待ack，并且我们的receive buf有足够的空间，
	 *   这是因为这种情况，表明应用程序读取比较快，而对端的发送速度依赖于ack的到达时间，* 因此我们不希望对端减慢速度。
	 * 2 这个sock处在quickack 模式
	 * 3 我们有 out-of-order数据,此时必须马上给对端以确认。
	 *   当上面的任意一个为真，则立即发送ack。
	**/
		if (((tp->rcv_nxt - tp->rcv_wup) > inet_csk(sk)->icsk_ack.rcv_mss
			 /* ... and right edge of window advances far enough.
			  * (tcp_recvmsg() will send ACK otherwise). Or...
			  */
			 && __tcp_select_window(sk) >= tp->rcv_wnd) ||
			/* We ACK each frame or... */
			tcp_in_quickack_mode(sk) ||
			/* We have out of order data. */
			(ofo_possible && skb_peek(&tp->out_of_order_queue))) {
			/* Then ack it now */
			tcp_send_ack(sk);
		} else {
			/* Else, send delayed ack. */
			//在这里启动定时器。
			tcp_send_delayed_ack(sk);
		}
	}
```
上面还有一个tcp_in_quickack_mode，这个函数我们说了，它是用来判断是否处在quickack 模式。  
来看这个函数：
```
	static inline int tcp_in_quickack_mode(const struct sock *sk)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		return icsk->icsk_ack.quick && !icsk->icsk_ack.pingpong;
	}
```
其中icsk->icsk_ack.pingpong域被设置的情况只有当tcp连接是交互式的，比如telnet等等。icsk->icsk_ack.quick表示能够 quickack的数量。
然后我们来看tcp_delack_timer的实现。  
在看之前，我们要知道icsk->icsk_ack.pending表示的是当前的ack的状态。
```
	static void tcp_delack_timer(unsigned long data)
	{
		struct sock *sk = (struct sock *)data;
		struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);

		bh_lock_sock(sk);
		//用户进程正在使用，则等会再尝试。
		if (sock_owned_by_user(sk)) {
			/* Try again later. */
			icsk->icsk_ack.blocked = 1;
			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_DELAYEDACKLOCKED);
			sk_reset_timer(sk, &icsk->icsk_delack_timer, jiffies + TCP_DELACK_MIN);
			goto out_unlock;
		}

		sk_mem_reclaim_partial(sk);

		//判断sock状态 以及ack的状态。如果是close或者已经处在ICSK_ACK_TIMER，则直接跳出。
		if (sk->sk_state == TCP_CLOSE || !(icsk->icsk_ack.pending & ICSK_ACK_TIMER))
			goto out;

		//如果已经超时，则重启定时器，并退出。
		if (time_after(icsk->icsk_ack.timeout, jiffies)) {
			sk_reset_timer(sk, &icsk->icsk_delack_timer, icsk->icsk_ack.timeout);
			goto out;
		}
		//清除ack状态。
		icsk->icsk_ack.pending &= ~ICSK_ACK_TIMER;

		//开始遍历prequeue。此时主要的目的是为了调用tcp_rcv_eastablished.这里会调用tcp_ack_snd_check来发送ack。
		if (!skb_queue_empty(&tp->ucopy.prequeue)) {
			struct sk_buff *skb;

			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPSCHEDULERFAILED);

			//遍历prequeue队列，发送未发送的ack。
			while ((skb = __skb_dequeue(&tp->ucopy.prequeue)) != NULL)
				sk_backlog_rcv(sk, skb);

			tp->ucopy.memory = 0;
		}

		//检测是否有ack还需要被发送。也就是处于ICSK_ACK_SCHED状态的ack
		if (inet_csk_ack_scheduled(sk)) {

			if (!icsk->icsk_ack.pingpong) {
				/* Delayed ACK missed: inflate ATO. */
				icsk->icsk_ack.ato = min(icsk->icsk_ack.ato << 1, icsk->icsk_rto);
			} else {
				//到这里说明已经长时间没有通信，并且处于交互模式。这个时候我们需要关闭pingpong模式。
				icsk->icsk_ack.pingpong = 0;
				icsk->icsk_ack.ato      = TCP_ATO_MIN;
			}
			//立即发送ack。
			tcp_send_ack(sk);
			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_DELAYEDACKS);
		}
		TCP_CHECK_TIMER(sk);

	out:
		if (tcp_memory_pressure)
			sk_mem_reclaim(sk);
	out_unlock:
		bh_unlock_sock(sk);
		sock_put(sk);
	}
```

