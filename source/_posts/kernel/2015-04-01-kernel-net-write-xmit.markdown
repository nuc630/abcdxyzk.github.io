---
layout: post
title: "Linux TCP发送数据tcp_write_xmit"
date: 2015-04-01 23:20:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/youxin2012/article/details/27175253

`__tcp_push_pending_frames` 该函数将所有pending的数据，全部发送出去。
```
	void __tcp_push_pending_frames(struct sock *sk, unsigned int cur_mss,
				 int nonagle)
	{
		/* If we are closed, the bytes will have to remain here.
		 * In time closedown will finish, we empty the write queue and
		 * all will be happy.
		 */
		/* 该socket已经关闭，那么直接返回 */
		if (unlikely(sk->sk_state == TCP_CLOSE))
			return;

		/* 发送数据 */
		if (tcp_write_xmit(sk, cur_mss, nonagle, 0, GFP_ATOMIC))
			tcp_check_probe_timer(sk); //发送数据失败，使用probe timer进行检查。
	}
```

#### 发送端 tcp_write_xmit 函数
版本：2.6.33.4

```
	/* This routine writes packets to the network.  It advances the
	 * send_head.  This happens as incoming acks open up the remote
	 * window for us.
	 *
	 * LARGESEND note: !tcp_urg_mode is overkill, only frames between
	 * snd_up-64k-mss .. snd_up cannot be large. However, taking into
	 * account rare use of URG, this is not a big flaw.
	 *
	 * Returns 1, if no segments are in flight and we have queued segments, but
	 * cannot send anything now because of SWS or another problem.
	 */
	static int tcp_write_xmit(struct sock *sk, unsigned int mss_now, int nonagle,
				  int push_one, gfp_t gfp)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;
		unsigned int tso_segs, sent_pkts;
		int cwnd_quota;
		int result;

		/* sent_pkts用来统计函数中已发送报文总数。*/
		sent_pkts = 0;

		/* 检查是不是只发送一个skb buffer，即push one */
		if (!push_one) {
			/* 如果要发送多个skb，则需要检测MTU。
			 * 这时会检测MTU，希望MTU可以比之前的大，提高发送效率。
			 */
			/* Do MTU probing. */
			result = tcp_mtu_probe(sk);
			if (!result) {
				return 0;
			} else if (result > 0) {
				sent_pkts = 1;
			}
		}

		while ((skb = tcp_send_head(sk))) {
			unsigned int limit;

			/* 设置有关TSO的信息，包括GSO类型，GSO分段的大小等等。
			 * 这些信息是准备给软件TSO分段使用的。
			 * 如果网络设备不支持TSO，但又使用了TSO功能，
			 * 则报文在提交给网络设备之前，需进行软分段，即由代码实现TSO分段。
			 */
			tso_segs = tcp_init_tso_segs(sk, skb, mss_now);
			BUG_ON(!tso_segs);

			/* 检查congestion windows， 可以发送几个segment */
			/* 检测拥塞窗口的大小，如果为0，则说明拥塞窗口已满，目前不能发送。
			 * 拿拥塞窗口和正在网络上传输的包数目相比，如果拥塞窗口还大，
			 * 则返回拥塞窗口减掉正在网络上传输的包数目剩下的大小。
			 * 该函数目的是判断正在网络上传输的包数目是否超过拥塞窗口，
			 * 如果超过了，则不发送。
			 */
			cwnd_quota = tcp_cwnd_test(tp, skb);
			if (!cwnd_quota)
				break;

			/* 检测当前报文是否完全处于发送窗口内，如果是则可以发送，否则不能发送 */
			if (unlikely(!tcp_snd_wnd_test(tp, skb, mss_now)))
				break;

			/* tso_segs=1表示无需tso分段 */
			if (tso_segs == 1) {
				/* 根据nagle算法，计算是否需要发送数据 */
				if (unlikely(!tcp_nagle_test(tp, skb, mss_now,
								 (tcp_skb_is_last(sk, skb) ?
								  nonagle : TCP_NAGLE_PUSH))))
					break;
			} else {
				/* 当不止一个skb时，通过TSO计算是否需要延时发送 */
				/* 如果需要TSO分段，则检测该报文是否应该延时发送。
			 	 * tcp_tso_should_defer()用来检测GSO段是否需要延时发送。
				 * 在段中有FIN标志，或者不处于open拥塞状态，或者TSO段延时超过2个时钟滴答，
				 * 或者拥塞窗口和发送窗口的最小值大于64K或三倍的当前有效MSS，在这些情况下会立即发送，
				 * 而其他情况下会延时发送，这样主要是为了减少软GSO分段的次数，以提高性能。
				 */
				if (!push_one && tcp_tso_should_defer(sk, skb))
					break;
			}

			limit = mss_now;
			/* 在TSO分片大于1的情况下，且TCP不是URG模式。通过MSS计算发送数据的limit
			 * 以发送窗口和拥塞窗口的最小值作为分段段长*/
			 */
			if (tso_segs > 1 && !tcp_urg_mode(tp))
				limit = tcp_mss_split_point(sk, skb, mss_now,
								cwnd_quota);
			/* 当skb的长度大于限制时，需要调用tso_fragment分片,如果分段失败则暂不发送 */
			if (skb->len > limit &&
				unlikely(tso_fragment(sk, skb, limit, mss_now)))
				break;

			/* 以上6行：根据条件，可能需要对SKB中的报文进行分段处理，分段的报文包括两种：
			 * 一种是普通的用MSS分段的报文，另一种则是TSO分段的报文。
			 * 能否发送报文主要取决于两个条件：一是报文需完全在发送窗口中，而是拥塞窗口未满。
			 * 第一种报文，应该不会再分段了，因为在tcp_sendmsg()中创建报文的SKB时已经根据MSS处理了，
			 * 而第二种报文，则一般情况下都会大于MSS，因为通过TSO分段的段有可能大于拥塞窗口的剩余空间，
			 * 如果是这样，就需要以发送窗口和拥塞窗口的最小值作为段长对报文再次分段。
			 */

			/* 更新tcp的时间戳，记录此报文发送的时间 */
			TCP_SKB_CB(skb)->when = tcp_time_stamp;

			if (unlikely(tcp_transmit_skb(sk, skb, 1, gfp)))
				break;

			/* Advance the send_head.  This one is sent out.
			 * This call will increment packets_out.
			 */
			/* 更新统计，并启动重传计时器 */
			/* 调用tcp_event_new_data_sent()-->tcp_advance_send_head()更新sk_send_head，
			 * 即取发送队列中的下一个SKB。同时更新snd_nxt，即等待发送的下一个TCP段的序号，
			 * 然后统计发出但未得到确认的数据报个数。最后如果发送该报文前没有需要确认的报文，
			 * 则复位重传定时器，对本次发送的报文做重传超时计时。
			 */
			tcp_event_new_data_sent(sk, skb);

			/* 更新struct tcp_sock中的snd_sml字段。snd_sml表示最近发送的小包(小于MSS的段)的最后一个字节序号，
			 * 在发送成功后，如果报文小于MSS，即更新该字段，主要用来判断是否启动nagle算法
			 */
			tcp_minshall_update(tp, mss_now, skb);
			sent_pkts++;

			if (push_one)
				break;
		}
		/* 如果本次有数据发送，则对TCP拥塞窗口进行检查确认。*/
		if (likely(sent_pkts)) {
			tcp_cwnd_validate(sk);
			return 0;
		}
		/*
		 * 如果本次没有数据发送，则根据已发送但未确认的报文数packets_out和sk_send_head返回，
		 * packets_out不为零或sk_send_head为空都视为有数据发出，因此返回成功。
		 */
		return !tp->packets_out && tcp_send_head(sk);
	}
```

