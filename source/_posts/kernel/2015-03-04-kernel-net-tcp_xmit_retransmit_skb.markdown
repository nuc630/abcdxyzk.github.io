---
layout: post
title: "tcp重传数据包 tcp_xmit_retransmit_skb"
date: 2015-03-04 17:40:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/shanshanpt/article/details/22202743

当知道需要重传数据结的时候执行这个函数：  
对于函数tcp_xmit_retransmit_queue：需要重传哪些包呢到底？  
首先是lost、标记的包；  
然后还需要处理：之前发送过的但是尚未收到确认的包（向前重传），或者新数据，在这两者之间有一个选择  

```
	/* This gets called after a retransmit timeout, and the initially
	 * retransmitted data is acknowledged.  It tries to continue
	 * resending the rest of the retransmit queue, until either
	 * we've sent it all or the congestion window limit is reached.
	 * If doing SACK, the first ACK which comes back for a timeout
	 * based retransmit packet might feed us FACK information again.
	 * If so, we use it to avoid unnecessarily retransmissions.
	 */
	void tcp_xmit_retransmit_queue(struct sock *sk)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;
		int packet_cnt;

		if (tp->retransmit_skb_hint) {                      // 如果有重传信息
			skb = tp->retransmit_skb_hint;
			packet_cnt = tp->retransmit_cnt_hint;           // 保存cnt值
		} else {
			skb = tcp_write_queue_head(sk);                 // 发送队列
			packet_cnt = 0;
		}
		// 第一步，如果有丢失的包，那么需要重传
		/* First pass: retransmit lost packets. */
		if (tp->lost_out) {  // lost_out > 0
			tcp_for_write_queue_from(skb, sk) {             // 遍历
				__u8 sacked = TCP_SKB_CB(skb)->sacked;      // 获得sacked标识

				if (skb == tcp_send_head(sk))
					   break;
				/* we could do better than to assign each time */
				tp->retransmit_skb_hint = skb;              // 更新两个值
				tp->retransmit_cnt_hint = packet_cnt;

				/* Assume this retransmit will generate
				 * only one packet for congestion window
				 * calculation purposes.  This works because
				 * tcp_retransmit_skb() will chop up the
				 * packet to be MSS sized and all the
				 * packet counting works out.
				 */
				if (tcp_packets_in_flight(tp) >= tp->snd_cwnd)  // 如果传输中的报文数量 > 窗口数量，那么没有必要再发送数据
					return;

				if (sacked & TCPCB_LOST) {                      // 如果是LOST标识
					if (!(sacked & (TCPCB_SACKED_ACKED|TCPCB_SACKED_RETRANS))) {  // 如果丢失了 && 没有被选择确认或者重传
						if (tcp_retransmit_skb(sk, skb)) {      // 重传该数据函数！！！最后再看（1）
							tp->retransmit_skb_hint = NULL;     // 重传之后重置这个值
							return;                             // 返回
						}
						if (icsk->icsk_ca_state != TCP_CA_Loss)
							NET_INC_STATS_BH(LINUX_MIB_TCPFASTRETRANS);
						else
							NET_INC_STATS_BH(LINUX_MIB_TCPSLOWSTARTRETRANS);

						if (skb == tcp_write_queue_head(sk))    // 如果是第一个重传数据，那么重置重传计数器！！！
							inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS,
										  inet_csk(sk)->icsk_rto,
										  TCP_RTO_MAX);
					}

					packet_cnt += tcp_skb_pcount(skb);          // 重传数量
					if (packet_cnt >= tp->lost_out)             // 大于lost的数量，那么break；下面就不是lost数据问题了
						break;
				}
			}
		}

		/* OK, demanded retransmission is finished. */
		// 上面的是必须要重传的，下面的在前向重传和发送新数据之间进行选择
		/* Forward retransmissions are possible only during Recovery. */
		if (icsk->icsk_ca_state != TCP_CA_Recovery)  // 只有在恢复状态才可以这样做，在丢失状态不可以；
			return;                                  // 原因：在丢失状态希望通过可控制的方式进行重传？这一块不是很懂

		/* No forward retransmissions in Reno are possible. */
		if (tcp_is_reno(tp))                         // 前向选择重传只能是SACK下，reno下是不可能的~
			return;

		/* Yeah, we have to make difficult choice between forward transmission
		 * and retransmission... Both ways have their merits...
		 *
		 * For now we do not retransmit anything, while we have some new
		 * segments to send. In the other cases, follow rule 3 for
		 * NextSeg() specified in RFC3517.
		 */ // 下面还是需要选择考虑传输新数据还是前向重传，优先考虑新数据

		if (tcp_may_send_now(sk))                    // 检查是否有新的数据在等待传输（1）
			return;                                  // 以及这些新数据是否可以发送，可以的话返回，不需要做下面事

		/* If nothing is SACKed, highest_sack in the loop won't be valid */
		if (!tp->sacked_out)
			return;
		// 下面开始就是“前向重传”处理
		if (tp->forward_skb_hint)                    // 是否已经缓存这个队列
			skb = tp->forward_skb_hint;
		else
			skb = tcp_write_queue_head(sk);          // 没有

		tcp_for_write_queue_from(skb, sk) {          // 需要遍历
			if (skb == tcp_send_head(sk))            // 到头了
				break;
			tp->forward_skb_hint = skb;

			if (!before(TCP_SKB_CB(skb)->seq, tcp_highest_sack_seq(tp)))   // 不可以超过最大的即highest_sack_seq
				break;

			if (tcp_packets_in_flight(tp) >= tp->snd_cwnd)   // 如果传输中的包数量 > 窗口大小
				break;                                       // 不能再发了

			if (sacked & (TCPCB_SACKED_ACKED|TCPCB_SACKED_RETRANS))     // 已经被sack了或者在sack时已经被重传了
				continue;

			/* Ok, retransmit it. */
			if (tcp_retransmit_skb(sk, skb)) {               // 下面就是传输这个包
				tp->forward_skb_hint = NULL;
				break;
			}

			if (skb == tcp_write_queue_head(sk))             // 如果是第一个重传的包，那么启动设置定时器
				inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS,
							  inet_csk(sk)->icsk_rto,
							  TCP_RTO_MAX);

			NET_INC_STATS_BH(LINUX_MIB_TCPFORWARDRETRANS);
		}
	}
```

看一下检查是否有新的数据需要传输的函数：tcp_may_send_now

因为此处涉及到Nagle算法，所以先简介一下：

Nagle算法：如果发送端欲多次发送包含少量字符的数据包（一般情况下，后面统一称长度小于MSS的数据包为小包，称长度等于MSS的数据包为大包），则发送端会先将第一个小包发送出去，而将后面到达的少量字符数据都缓存起来而不立即发送，直到收到接收端对前一个数据包报文段的ACK确认、或当前字符属于紧急数据，或者积攒到了一定数量的数据（比如缓存的字符数据已经达到数据包报文段的最大长度）等多种情况才将其组成一个较大的数据包发送出去。

```
	int tcp_may_send_now(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb = tcp_send_head(sk);                 // 获得需要发送的数据头部

		return (skb &&                                           // 尚有新数据需要传输
			tcp_snd_test(sk, skb, tcp_current_mss(sk, 1),        // 看下面这个函数：检查是否这些新的数据需要尽快发送出去
					 (tcp_skb_is_last(sk, skb) ?     // 是否是最后一个包
					  tp->nonagle : TCP_NAGLE_PUSH)));
	}
```

```
	/* This checks if the data bearing packet SKB (usually tcp_send_head(sk))
	 * should be put on the wire right now.  If so, it returns the number of
	 * packets allowed by the congestion window.
	 */
	static unsigned int tcp_snd_test(struct sock *sk, struct sk_buff *skb,
					 unsigned int cur_mss, int nonagle)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		unsigned int cwnd_quota;

		tcp_init_tso_segs(sk, skb, cur_mss);                     // 看看这个包的tso信息，便于后期和其他包一起处理

		if (!tcp_nagle_test(tp, skb, cur_mss, nonagle))          // 使用Nagle测试是不是数据现在就允许被发送，看下面函数（1）
			return 0;                                            // 如果不可以就返回了

		cwnd_quota = tcp_cwnd_test(tp, skb);                     // 返回还可以发送几个窗口的数据
		if (cwnd_quota && !tcp_snd_wnd_test(tp, skb, cur_mss))   // 如果有窗口数据可以发送 &&
			cwnd_quota = 0;                                      // 不可发送，设置=0

		return cwnd_quota;
	}
```

看Nagle测试函数tcp_nagle_test：
```
	/* Return non-zero if the Nagle test allows this packet to be
	 * sent now.
	 */
	static inline int tcp_nagle_test(struct tcp_sock *tp, struct sk_buff *skb,
					 unsigned int cur_mss, int nonagle)	        // 注意：测试返回1就是说明那个数据包现在允许直接发送出去
	{									  	// 而Nagle对于小包是缓存一起发送的，除了第一个包、最后一个包
		/* Nagle rule does not apply to frames, which sit in the middle of the
		 * write_queue (they have no chances to get new data).
		 *
		 * This is implemented in the callers, where they modify the 'nonagle'
		 * argument based upon the location of SKB in the send queue.
		 */
		if (nonagle & TCP_NAGLE_PUSH)                // 设置了这个标识是因为说明可能是第一个包或者第二个包，或者其他一些允许的原因呢
			return 1;                                // Nagle允许直接发送包出去

		/* Don't use the nagle rule for urgent data (or for the final FIN).
		 * Nagle can be ignored during F-RTO too (see RFC4138).
		 */
		if (tp->urg_mode || (tp->frto_counter == 2) ||          // 注意对于紧急数据来说不可以使用Nagle规则！上面说过Nagle是缓存处理数据，紧急数据不可以！
			(TCP_SKB_CB(skb)->flags & TCPCB_FLAG_FIN))          // 注意结束包(FIN)和F-RTO标识包都需要立马发送出去
			return 1;

		if (!tcp_nagle_check(tp, skb, cur_mss, nonagle))        // 在Nagle算法下，是否允许发送这个包？返回0则允许立刻发送
			return 1;

		return 0;
	}
```

tcp_nagle_check函数：
```
	/* Return 0, if packet can be sent now without violation Nagle's rules:   Nagle算法允许下面条件的包可以正常发送
	 * 1. It is full sized.                                          // 大小等于MSS，即缓存满，或者是大包
	 * 2. Or it contains FIN. (already checked by caller)            // 是结束包FIN
	 * 3. Or TCP_NODELAY was set.                                    // 不允许延迟的包
	 * 4. Or TCP_CORK is not set, and all sent packets are ACKed.    // TCP_CORK没有设置
	 *    With Minshall's modification: all sent small packets are ACKed.
	 */
	static inline int tcp_nagle_check(const struct tcp_sock *tp,
					 const struct sk_buff *skb,
					  unsigned mss_now, int nonagle)
	{
		return (skb->len < mss_now &&                           // 检查在Nagle算法情况下，是不是可以发送这个包
			((nonagle & TCP_NAGLE_CORK) ||                      // 满足上面四个条件就OK
			 (!nonagle && tp->packets_out && tcp_minshall_check(tp))));
	}
```

tcp_cwnd_test函数用于测试在当前的拥塞窗口情况下，最多还可以发送几个新数据
```
	/* Can at least one segment of SKB be sent right now, according to the
	 * congestion window rules?  If so, return how many segments are allowed.
	 */
	static inline unsigned int tcp_cwnd_test(struct tcp_sock *tp,   // 根据当前的拥塞窗口，返回当前还可以发送几个segs
						 struct sk_buff *skb)
	{
		u32 in_flight, cwnd;

		/* Don't be strict about the congestion window for the final FIN.  */
		if ((TCP_SKB_CB(skb)->flags & TCPCB_FLAG_FIN) &&   	// 如果是最后的FIN包
			tcp_skb_pcount(skb) == 1)
			return 1;                                       // 返回一个OK

		in_flight = tcp_packets_in_flight(tp);              // 获得还在传输中的包
		cwnd = tp->snd_cwnd;                                // 获得当前窗口大小
		if (in_flight < cwnd)
			return (cwnd - in_flight);                      // 剩下的部分都是可以发送的

		return 0;
	}
```

主要是用于测试最后一个数据是不是在窗口内，在则可以发送，不在则不可以发送
```
	/* Does at least the first segment of SKB fit into the send window? */
	static inline int tcp_snd_wnd_test(struct tcp_sock *tp, struct sk_buff *skb,
					   unsigned int cur_mss)
	{
		u32 end_seq = TCP_SKB_CB(skb)->end_seq;

		if (skb->len > cur_mss)   // skb数据长度比MSS长
			end_seq = TCP_SKB_CB(skb)->seq + cur_mss;       // 最后一个seq

		return !after(end_seq, tcp_wnd_end(tp));            // 最后一个seq是不是在窗口内，不在则不可以发送
	}
```

