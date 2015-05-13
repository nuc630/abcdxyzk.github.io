---
layout: post
title: "拥塞避免处理函数 tcp_reno_cong_avoid"
date: 2015-03-04 17:35:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/shanshanpt/article/details/22201847

慢启动和快速重传拥塞避免算法，函数tcp_reno_cong_avoid  
在“慢开始”阶段，每收到一个ACK，cwnd++一次，那么一个RTT之后，cwnd就会加倍  
拥塞避免阶段，其实就是在一个RTT时间内将cwnd++一次( 注意在不丢包的情况下 )  

```
	/*
	 * TCP Reno congestion control
	 * This is special case used for fallback as well.
	 */
	/* This is Jacobson's slow start and congestion avoidance.
	 * SIGCOMM '88, p. 328.
	 */
	void tcp_reno_cong_avoid(struct sock *sk, u32 ack, u32 in_flight)
	{
		struct tcp_sock *tp = tcp_sk(sk);         // 获取tcp_sock
		// 函数返回1说明拥塞窗口被限制，我们需要增加拥塞窗口，否则的话，就不需要增加拥塞窗口。
		if (!tcp_is_cwnd_limited(sk, in_flight))  // 是否已经达到拥塞窗口的限制值（1）
			return;

		/* In "safe" area, increase. */
		if (tp->snd_cwnd <= tp->snd_ssthresh)     // 如果发送窗口大小还 比 慢开始门限小，那么还是慢开始处理
			tcp_slow_start(tp);                   // 下面进入慢开始处理 (2)
		/* In dangerous area, increase slowly. */
		else if (sysctl_tcp_abc) {                // 否则进入拥塞避免阶段！！每个RTT时间就加1
			/* RFC3465: Appropriate Byte Count
			 * increase once for each full cwnd acked              // 基本思想就是：经过一个RTT时间就将snd_cwnd增加一个单位！
			 */                                                    // 一个RTT时间可以认为是当前拥塞窗口发送出去的数据的所有ACK都被接收到
			if (tp->bytes_acked >= tp->snd_cwnd*tp->mss_cache) {   // 当前的拥塞窗口的所有段都被ack了，窗口才被允许增加。
				tp->bytes_acked -= tp->snd_cwnd*tp->mss_cache;     // ACK处理过的及删除去了
				if (tp->snd_cwnd < tp->snd_cwnd_clamp)             // 不允许发送窗口大小超过snd_cwnd_clamp值
					tp->snd_cwnd++;
			}
		} else {                                       // 每接收到一个ACK，窗口增大(1/snd_cwnd)，使用cnt计数
			/* In theory this is tp->snd_cwnd += 1 / tp->snd_cwnd */
			if (tp->snd_cwnd_cnt >= tp->snd_cwnd) {    // 线性增长计数器 >= 阈值
				if (tp->snd_cwnd < tp->snd_cwnd_clamp) // 如果窗口还没有达到阈值
					tp->snd_cwnd++;                    // 那么++增大窗口
				tp->snd_cwnd_cnt = 0;
			} else
				tp->snd_cwnd_cnt++;                    // 否则仅仅是增大线性递增计数器
		}
	}
```

下面看一下“慢开始”算法：
```
	void tcp_slow_start(struct tcp_sock *tp)           // 每到达一个ACK，snd_cwnd就加1。这意味着每个RTT，拥塞窗口就会翻倍。
	{
		int cnt; /* increase in packets */

		/* RFC3465: ABC Slow start
		 * Increase only after a full MSS of bytes is acked
		 *
		 * TCP sender SHOULD increase cwnd by the number of
		 * previously unacknowledged bytes ACKed by each incoming
		 * acknowledgment, provided the increase is not more than L
		 */
		if (sysctl_tcp_abc && tp->bytes_acked < tp->mss_cache)                     // 如果ack确认的数据少于一个MSS大小，不需要增大窗口
			return;
		// 限制cnt的值
		if (sysctl_tcp_max_ssthresh > 0 && tp->snd_cwnd > sysctl_tcp_max_ssthresh) // 发送窗口超过最大门限值
			cnt = sysctl_tcp_max_ssthresh >> 1;     /* limited slow start */       // 窗口减半~~~~~
		else
			cnt = tp->snd_cwnd;          /* exponential increase */                // 否则还是原来的窗口

		/* RFC3465: ABC
		 * We MAY increase by 2 if discovered delayed ack
		 */
		if (sysctl_tcp_abc > 1 && tp->bytes_acked >= 2*tp->mss_cache) // 如果启动了延迟确认，那么当接收到的ACK大于等于两个MSS的时候才加倍窗口大小
			cnt <<= 1;
		tp->bytes_acked = 0;  // 清空

		tp->snd_cwnd_cnt += cnt;
		while (tp->snd_cwnd_cnt >= tp->snd_cwnd) {  // 这里snd_cwnd_cnt是snd_cwnd的几倍，拥塞窗口就增加几。
			tp->snd_cwnd_cnt -= tp->snd_cwnd;       // ok
			if (tp->snd_cwnd < tp->snd_cwnd_clamp)  // 判断窗口大小
				tp->snd_cwnd++;  // + +
		}
	}
```

最后看一下这个函数：tcp_is_cwnd_limited，基本的意思就是判断需不需要增大拥塞窗口。

关于gso：主要功能就是尽量的延迟数据包的传输，以便与在最恰当的时机传输数据包。如果支持gso，就有可能是tso 延迟了数据包，因此这里会进行几个相关的判断，来看需不需要增加拥塞窗口。

关于burst：主要用来控制网络流量的突发性增大，也就是说当left数据(还能发送的数据段数)大于burst值的时候，我们需要暂时停止增加窗口，因为此时有可能我们这边数据发送过快。其实就是一个平衡权值。

```
	int tcp_is_cwnd_limited(const struct sock *sk, u32 in_flight)  // 第二个参数是正在网络中传输，还没有收到确认的报数量
	{
		const struct tcp_sock *tp = tcp_sk(sk);
		u32 left;

		if (in_flight >= tp->snd_cwnd)    // 比较发送未确认和发送拥塞窗口的大小
			return 1;                     // 如果未确认的大，那么需要增大拥塞窗口

		if (!sk_can_gso(sk))              // 如果没有gso延时处理所有包，不需要增大窗口
			return 0;

		left = tp->snd_cwnd - in_flight;  // 得到还能发送的数据包的数量
		if (sysctl_tcp_tso_win_divisor)
			return left * sysctl_tcp_tso_win_divisor < tp->snd_cwnd;
		else
			return left <= tcp_max_burst(tp); // 如果还可以发送的数量>burst，说明发送太快，不需要增大窗口。
	}
```

