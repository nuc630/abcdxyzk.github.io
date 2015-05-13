---
layout: post
title: "清理重传队列中函数 tcp_clean_rtx_queue"
date: 2015-03-04 17:25:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/shanshanpt/article/details/22194029

如果重传队列中的一些数据已经被确认，那么， 需要从重传队列中清除出去，需要使用这个函数：tcp_clean_rtx_queue
```
	/* Remove acknowledged frames from the retransmission queue. If our packet
	 * is before the ack sequence we can discard it as it's confirmed to have
	 * arrived at the other end.
	 */
	static int tcp_clean_rtx_queue(struct sock *sk, int prior_fackets)
	{
		struct tcp_sock *tp = tcp_sk(sk);   // 获得tcp_sock
		const struct inet_connection_sock *icsk = inet_csk(sk); // 获得连接sock
		struct sk_buff *skb;
		u32 now = tcp_time_stamp;           // 当前时间，用于计算RTT
		int fully_acked = 1;                // 表示数据段是否完全被确认
		int flag = 0;
		u32 pkts_acked = 0;
		u32 reord = tp->packets_out;        // 发送出去，还在网络上跑，但是还没有被确认的数据包们
		s32 seq_rtt = -1;
		s32 ca_seq_rtt = -1;
		ktime_t last_ackt = net_invalid_timestamp();    // 把last_ackt设置位0
		// 下面就是遍历sk_write_queue队列，遇到snd_una就停止，如果没有更新过，开始就直接退出了
		while ((skb = tcp_write_queue_head(sk)) && skb != tcp_send_head(sk)) {
			struct tcp_skb_cb *scb = TCP_SKB_CB(skb);   // 获得这个重传队列的一个skb的cb字段
			u32 end_seq;
			u32 acked_pcount;
			u8 sacked = scb->sacked;

			/* Determine how many packets and what bytes were acked, tso and else */
			if (after(scb->end_seq, tp->snd_una)) {     // 注意这个scb是我们发出去的数据的skb中的一个scb哦！，不是接受到的数据！小心
				if (tcp_skb_pcount(skb) == 1 ||         // 这里的意思就是发出去的数据最后一个字节在已经确认的snd_una之后，说明还有没有确认的字节
				!after(tp->snd_una, scb->seq))          // 如果没有设置了TSO 或者 seq不在snd_una之前，即不是 seq---snd_una---end_seq这样情况
					break;                              // 那么说明没有必要把重传元素去掉，(如果是seq---snd_una---end_seq)那么前面半部分的就可以从队列中删除！！！

				acked_pcount = tcp_tso_acked(sk, skb);  // 如果只确认了TSO段中的一部分，则从skb删除已经确认的segs，并统计确认了多少段( 1 )
				if (!acked_pcount)                      // 处理出错
					break;

				fully_acked = 0;                        // 表示TSO只处理了一部分，其他还没处理完
				end_seq = tp->snd_una;
			} else {
				acked_pcount = tcp_skb_pcount(skb);     // 即 !after(scb->end_seq, tp->snd_una)，说明已经完全确认OK！
				end_seq = scb->end_seq;
			}

			/* MTU probing checks */
			if (fully_acked && icsk->icsk_mtup.probe_size &&      // 探测mtu，暂时不多说
			!after(tp->mtu_probe.probe_seq_end, scb->end_seq)) {
				tcp_mtup_probe_success(sk, skb);
			}
			// 下面通过sack的信息得到这是一个被重传的过包
			if (sacked & TCPCB_RETRANS) {
				if (sacked & TCPCB_SACKED_RETRANS)      // 如果之前重传过，&& 之前还没收到回复
					tp->retrans_out -= acked_pcount;    // 现在需要更新重传的且没有收到ACK的包
				flag |= FLAG_RETRANS_DATA_ACKED;        // 重传包收到ACK
				ca_seq_rtt = -1;
				seq_rtt = -1;
				if ((flag & FLAG_DATA_ACKED) || (acked_pcount > 1))
					flag |= FLAG_NONHEAD_RETRANS_ACKED;
			} else { // 如果此数据段没有被重传过
				ca_seq_rtt = now - scb->when;           // 通过ACK确认获得RTT值
				last_ackt = skb->tstamp;                // 获得skb的发送时间
				if (seq_rtt < 0) {
					seq_rtt = ca_seq_rtt;
				}
				if (!(sacked & TCPCB_SACKED_ACKED))     // 如果SACK存在一段没有被确认，那么保存其中序号最小号的
					reord = min(pkts_acked, reord);
			}

			if (sacked & TCPCB_SACKED_ACKED)            // 如果是有sack标识
				tp->sacked_out -= acked_pcount;         // 那么更新sack的发出没有接受到确认的数量
			if (sacked & TCPCB_LOST)                    // 如果是丢包标识，那么更新数量
				tp->lost_out -= acked_pcount;

			if (unlikely(tp->urg_mode && !before(end_seq, tp->snd_up)))  // 紧急模式
				tp->urg_mode = 0;

			tp->packets_out -= acked_pcount;            // 发送的包没有确认的数量-=acked_pcount
			pkts_acked += acked_pcount;                 // 接收到确认的包数量+=acked_pcount

			/* Initial outgoing SYN's get put onto the write_queue
			 * just like anything else we transmit.  It is not
			 * true data, and if we misinform our callers that
			 * this ACK acks real data, we will erroneously exit
			 * connection startup slow start one packet too
			 * quickly.  This is severely frowned upon behavior.
			 */
			if (!(scb->flags & TCPCB_FLAG_SYN)) {       // 如果不是SYN握手包
				flag |= FLAG_DATA_ACKED;                // 标识是数据确认
			} else {
				flag |= FLAG_SYN_ACKED;                 // 标识是SYN包标识
				tp->retrans_stamp = 0;                  // 清除重传戳
			}

			if (!fully_acked)                           // 如果TSO段没被完全确认，则到此为止
				break;

			tcp_unlink_write_queue(skb, sk);            // 从发送队列上移除这个skb！！！这个函数其实很简单，其实就是从链表中移除这个skb而已
			sk_wmem_free_skb(sk, skb);                  // 删除skb内存对象
			tcp_clear_all_retrans_hints(tp);
		}                                               // while循环结束

		if (skb && (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED))  // 虚假的SACK
			flag |= FLAG_SACK_RENEGING;

		if (flag & FLAG_ACKED) {                        // 如果ACK更新了数据，是的snd_una更新了
			const struct tcp_congestion_ops *ca_ops
				= inet_csk(sk)->icsk_ca_ops;            // 拥塞信息

			tcp_ack_update_rtt(sk, flag, seq_rtt);      // 更新RTT
			tcp_rearm_rto(sk);                          // 重置超时重传计时器

			if (tcp_is_reno(tp)) {                      // 如果没有SACK处理
				tcp_remove_reno_sacks(sk, pkts_acked);  // 处理乱序的包
			} else {
				/* Non-retransmitted hole got filled? That's reordering */
				if (reord < prior_fackets)
					tcp_update_reordering(sk, tp->fackets_out - reord, 0);  // 更新乱序队列大小
			}

			tp->fackets_out -= min(pkts_acked, tp->fackets_out);    // 更新提前确认算法得出的尚未得到确认的包的数量

			if (ca_ops->pkts_acked) {   // 这是一个钩子函数
				s32 rtt_us = -1;

				/* Is the ACK triggering packet unambiguous? */
				if (!(flag & FLAG_RETRANS_DATA_ACKED)) {            // 如果是确认了非重传的包
					/* High resolution needed and available? */
					if (ca_ops->flags & TCP_CONG_RTT_STAMP &&       // 下面都是测量RTT，精读不同而已
					!ktime_equal(last_ackt,
							 net_invalid_timestamp()))
						rtt_us = ktime_us_delta(ktime_get_real(),
									last_ackt);
					else if (ca_seq_rtt > 0)
						rtt_us = jiffies_to_usecs(ca_seq_rtt);
				}

				ca_ops->pkts_acked(sk, pkts_acked, rtt_us);
			}
		}

	#if FASTRETRANS_DEBUG > 0  // 下面用于调试
		BUG_TRAP((int)tp->sacked_out >= 0);
		BUG_TRAP((int)tp->lost_out >= 0);
		BUG_TRAP((int)tp->retrans_out >= 0);
		if (!tp->packets_out && tcp_is_sack(tp)) {
			icsk = inet_csk(sk);
			if (tp->lost_out) {
				printk(KERN_DEBUG "Leak l=%u %d\n",
					tp->lost_out, icsk->icsk_ca_state);
				tp->lost_out = 0;
			}
			if (tp->sacked_out) {
				printk(KERN_DEBUG "Leak s=%u %d\n",
					tp->sacked_out, icsk->icsk_ca_state);
				tp->sacked_out = 0;
			}
			if (tp->retrans_out) {
				printk(KERN_DEBUG "Leak r=%u %d\n",
					tp->retrans_out, icsk->icsk_ca_state);
				 tp->retrans_out = 0;
			}
		}
	#endif
		return flag;
	}
```

下面看一下tcp_tso_acked函数：
```
	/* If we get here, the whole TSO packet has not been acked. */
	static u32 tcp_tso_acked(struct sock *sk, struct sk_buff *skb)       // TSO 包并没有全部被确认，现在需要统计已经被确认的数量
	{
		struct tcp_sock *tp = tcp_sk(sk);                                // 获得tcp_sock
		u32 packets_acked;

		BUG_ON(!after(TCP_SKB_CB(skb)->end_seq, tp->snd_una));           // seq---end_seq---snd_una  这种情况不可能进来

		packets_acked = tcp_skb_pcount(skb);                             // TSO段总共包括几个
		if (tcp_trim_head(sk, skb, tp->snd_una - TCP_SKB_CB(skb)->seq))  // 对于已经确认的部分，更新skb中的信息。例如len之类信息都变了
			return 0;                                                    // 然后重新计算出新的剩余的segs
		packets_acked -= tcp_skb_pcount(skb);                            // 之前总的segs - 现在剩余的segs == 被确认的segs

		if (packets_acked) {
			BUG_ON(tcp_skb_pcount(skb) == 0);
			BUG_ON(!before(TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq));
		}

		return packets_acked;                                            // 返回被确认的数量
	}
```

