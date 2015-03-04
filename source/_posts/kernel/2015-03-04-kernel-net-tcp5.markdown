---
layout: post
title: "TCP拥塞状态机 tcp_fastretrans_alert"
date: 2015-03-04 17:45:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
这里主要说的是TCP拥塞情况下的状态状态处理
```
	/* Process an event, which can update packets-in-flight not trivially.
	 * Main goal of this function is to calculate new estimate for left_out,
	 * taking into account both packets sitting in receiver's buffer and
	 * packets lost by network.
	 *
	 * Besides that it does CWND reduction, when packet loss is detected
	 * and changes state of machine.
	 *
	 * It does _not_ decide what to send, it is made in function
	 * tcp_xmit_retransmit_queue().
	 */
	static void tcp_fastretrans_alert(struct sock *sk, int pkts_acked, int flag)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);     
		struct tcp_sock *tp = tcp_sk(sk);
		int is_dupack = !(flag & (FLAG_SND_UNA_ADVANCED | FLAG_NOT_DUP));   // 判断是不是重复的ACK
		int do_lost = is_dupack || ((flag & FLAG_DATA_SACKED) &&            // 判断是不是丢包：若是重复ACK 或者 SACK而且提前确认中没有到的包数量>重拍指标
						(tcp_fackets_out(tp) > tp->reordering));            // 后面会单独说说SACK和FACK内容，觉得总是理解不好
		int fast_rexmit = 0;
	 
		if (WARN_ON(!tp->packets_out && tp->sacked_out))   // 如果packet_out为0，那么不可能有sacked_out
			tp->sacked_out = 0;
		if (WARN_ON(!tp->sacked_out && tp->fackets_out))
			tp->fackets_out = 0;
	 
		/* Now state machine starts.   // 下面开始状态处理
		 * A. ECE, hence prohibit cwnd undoing, the reduction is required. */
		if (flag & FLAG_ECE)	       // 如果是ECE
			tp->prior_ssthresh = 0;    // 禁止拥塞窗口撤销，并开始减小拥塞窗口
	 
		/* B. In all the states check for reneging SACKs. */
		if (tcp_check_sack_reneging(sk, flag))   // 检查ACK是不是确认了已经被SACK选择确认的包了
			return;
	 
		/* C. Process data loss notification, provided it is valid. */
		if (tcp_is_fack(tp) && (flag & FLAG_DATA_LOST) &&   // 提前确认、数据丢失
			before(tp->snd_una, tp->high_seq) &&            // 我们需要注意high_seq&nbsp;可以标志为LOST的段序号的最大值
			icsk->icsk_ca_state != TCP_CA_Open &&           // 状态不是OPEN
			tp->fackets_out > tp->reordering) {             // 同上面说的
			tcp_mark_head_lost(sk, tp->fackets_out - tp->reordering);   // 发现丢包，需要标志出丢失的包。&nbsp;(1) 这个函数后面看
			NET_INC_STATS_BH(LINUX_MIB_TCPLOSS);
		}
	 
		/* D. Check consistency of the current state. */
		tcp_verify_left_out(tp); // #define tcp_verify_left_out(tp) WARN_ON(tcp_left_out(tp) > tp->packets_out)
					 // 检查丢失的包应该比发送出去的包小，即确定确定left_out < packets_out
		/* E. Check state exit conditions. State can be terminated
		 *    when high_seq is ACKed. */                    // 下面检测状态退出条件！当high_seq&nbsp;被确认的时候，这个状态就可以终止了
		if (icsk->icsk_ca_state == TCP_CA_Open) {           // 如果是open状态
			BUG_TRAP(tp->retrans_out == 0);                 // 重传数量应该=0才是合理的
			tp->retrans_stamp = 0;                          // 将重传发送时间置0
		} else if (!before(tp->snd_una, tp->high_seq)) {    // 如果high_seq已经被确认
			switch (icsk->icsk_ca_state) {
			case TCP_CA_Loss:
				icsk->icsk_retransmits = 0;                 // 超时重传次数归零
				if (tcp_try_undo_recovery(sk))              // 尝试将前面的拥塞窗口的调整撤销，在这种情况下弄不清楚包的情况（2）
					return;                                 // 如果使用了SACK，那么不管undo成功与否，都会返回Open态
				break;
	 
			case TCP_CA_CWR:   // 发生某些道路拥塞，需要减慢发送速度
				/* CWR is to be held something *above* high_seq
				 * is ACKed for CWR bit to reach receiver. */
				if (tp->snd_una != tp->high_seq) {
					tcp_complete_cwr(sk);                   // 完成道路拥塞情况处理，就是减小cwnd（3）
					tcp_set_ca_state(sk, TCP_CA_Open);      // 将状态设置成OPEN
				}
				break;
	 
			case TCP_CA_Disorder:
				tcp_try_undo_dsack(sk);                     // 尝试撤销cwnd的减少，因为DSACK确认了所有的重传数据（4）
				if (!tp->undo_marker ||                     // 跟踪了重传数据包？
					/* For SACK case do not Open to allow to undo
					 * catching for all duplicate ACKs. */
					tcp_is_reno(tp) || tp->snd_una != tp->high_seq) {   // 没有SACK || 两者不同步
					tp->undo_marker = 0;
					tcp_set_ca_state(sk, TCP_CA_Open);      // 将状态转换成OPEN
				}
				break;
	 
			case TCP_CA_Recovery:
				if (tcp_is_reno(tp))                // 没有SACK
					tcp_reset_reno_sack(tp);        // sacked_out=0
				if (tcp_try_undo_recovery(sk))      // 尝试撤销
					return;
				tcp_complete_cwr(sk);               // 完成处理
				break;
			}
		}
	 
		/* F. Process state. */
		switch (icsk->icsk_ca_state) {
		case TCP_CA_Recovery:
			if (!(flag & FLAG_SND_UNA_ADVANCED)) {  // snd_una没有改变
				if (tcp_is_reno(tp) && is_dupack)   // 不是SACK，而且是重复的ACK
					tcp_add_reno_sack(sk);          // 接收到重复的ACK，tp->sacked_out++; 并且检查新的reorder问题（5）
			} else
				do_lost = tcp_try_undo_partial(sk, pkts_acked);   // 部分ACK接收并撤销窗口操作（6）注意返回的是是否需要重传表示
			break;                                  // 1代表重传，0代表不需要重传
		case TCP_CA_Loss:
			if (flag & FLAG_DATA_ACKED)             // 如果是数据确认
				icsk->icsk_retransmits = 0;         // 超时重传置次数0
			if (tcp_is_reno(tp) && flag & FLAG_SND_UNA_ADVANCED) // 没有ACK，&& snd_una改变了
				tcp_reset_reno_sack(tp);            // 重置sacked=0
			if (!tcp_try_undo_loss(sk)) {           // 尝试撤销拥塞调整，然后进入OPEN状态（7）
				tcp_moderate_cwnd(tp);              // 调整窗口（8）
				tcp_xmit_retransmit_queue(sk);      // 重传丢失的包（9）
				return;
			}
			if (icsk->icsk_ca_state != TCP_CA_Open)
				return;
			/* Loss is undone; fall through to processing in Open state. */
		default:
			if (tcp_is_reno(tp)) {                  // 么有SACK，那么就是RENO算法处理：收到三个dup-ACK(即sacked_out==3)，就开始重传
				if (flag & FLAG_SND_UNA_ADVANCED)   // 如果收到少于 3 个 dupack 后又收到累计确认，则会重置之前的 sacked_out 计数
					tcp_reset_reno_sack(tp);        // 重新置0
				if (is_dupack)                      // 如果收到一个dup-ack，将sacked_out++
					tcp_add_reno_sack(sk);
			}
	 
			if (icsk->icsk_ca_state == TCP_CA_Disorder)
				tcp_try_undo_dsack(sk);             // DSACK确认了所有重传数据
	 
			if (!tcp_time_to_recover(sk)) {         // 判断是否进入恢复状态
				tcp_try_to_open(sk, flag);          // 如果不可以，那么会判断是否进入Open、Disorder、CWR等状态
				return;                             // 只有收到三个dup-ack时候，才进入快速回复，否则都返回
			}
	 
			/* MTU probe failure: don't reduce cwnd */
			if (icsk->icsk_ca_state < TCP_CA_CWR &&
				icsk->icsk_mtup.probe_size &&
				tp->snd_una == tp->mtu_probe.probe_seq_start) {
				tcp_mtup_probe_failed(sk);          // MTU探测失败
				/* Restores the reduction we did in tcp_mtup_probe() */
				tp->snd_cwnd++;
				tcp_simple_retransmit(sk);          // 做一个简单的转发，而不使用回退机制。用于路径MTU发现。&nbsp;
				return;
			}
			// 说明已经收到第 3 个连续 dupack，此时 sacked_out = 3，进入恢复态
			/* Otherwise enter Recovery state */
			// 进入恢复状态
			if (tcp_is_reno(tp))
				NET_INC_STATS_BH(LINUX_MIB_TCPRENORECOVERY);
			else
				NET_INC_STATS_BH(LINUX_MIB_TCPSACKRECOVERY);
	 
			tp->high_seq = tp->snd_nxt;
			tp->prior_ssthresh = 0;
			tp->undo_marker = tp->snd_una;
			tp->undo_retrans = tp->retrans_out;

			if (icsk->icsk_ca_state < TCP_CA_CWR) {
				if (!(flag & FLAG_ECE))
					tp->prior_ssthresh = tcp_current_ssthresh(sk);   // 根据状态获取当前门限值
				tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk);  // 更新
				TCP_ECN_queue_cwr(tp);
			}
	 
			tp->bytes_acked = 0;
			tp->snd_cwnd_cnt = 0;
			tcp_set_ca_state(sk, TCP_CA_Recovery);      // 键入恢复状态
			fast_rexmit = 1;    // 快速重传
		}
	 
		if (do_lost || (tcp_is_fack(tp) && tcp_head_timedout(sk))) // 如果丢失需要重传 || 超时重传
			tcp_update_scoreboard(sk, fast_rexmit);     // 标志丢失和超时的数据包，增加lost_out(10)
		tcp_cwnd_down(sk, flag);                        // 减小cwnd窗口（11）
		tcp_xmit_retransmit_queue(sk);                  // 重传丢失包
	}
```

下面看一下里面的函数：

先看：tcp_mark_head_lost：通过给丢失的数据包标志TCPCB_LOST，就可以表明哪些数据包需要重传。

注意参数：packets = fackets_out - reordering，其实就是sacked_out + lost_out。被标志为LOST的段数不能超过packets。

那么packets 就是标记丢失的包们数量
```
	/* Mark head of queue up as lost. With RFC3517 SACK, the packets is
	 * is against sacked "cnt", otherwise it's against facked "cnt"
	 */
	static void tcp_mark_head_lost(struct sock *sk, int packets)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;
		int cnt, oldcnt;
		int err;
		unsigned int mss;
	 
		BUG_TRAP(packets <= tp->packets_out);   // 丢失的包不可能比所有发出去的包的数量
		if (tp->lost_skb_hint) {                // 如果已经有标识为丢失的段了 
			skb = tp->lost_skb_hint;            // 下一个需要标记的数据段
			cnt = tp->lost_cnt_hint;            // 已经标记了多少段
		} else {
			skb = tcp_write_queue_head(sk);     // 获得链表的第一个结构元素
			cnt = 0;                            // 初始化标记了0个数据
		}
		// 下面开始遍历
		tcp_for_write_queue_from(skb, sk) {
			if (skb == tcp_send_head(sk))       // return sk->sk_send_head; 即snd_nxt，那么还没有发送不需要处理，break；
				break;
			/* TODO: do this better */
			/* this is not the most efficient way to do this... */
			tp->lost_skb_hint = skb;            // 更新丢失队列信息
			tp->lost_cnt_hint = cnt;
	 
			if (after(TCP_SKB_CB(skb)->end_seq, tp->high_seq))   // high_seq是最大的标记为LOST的号，不可以超过这个
				break;                          // 若这个skb超过，退出
	 
			oldcnt = cnt;                       // 保存cnt
			if (tcp_is_fack(tp) || tcp_is_reno(tp) ||
				(TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED))
				cnt += tcp_skb_pcount(skb);     // 表示这个段已经被标记
	 
			if (cnt > packets) {
				if (tcp_is_sack(tp) || (oldcnt >= packets))   // 已经超过了丢失包数量，break
					break;
	 
				mss = skb_shinfo(skb)->gso_size;// 得到MSS
				err = tcp_fragment(sk, skb, (packets - oldcnt) * mss, mss);   // 下面分配，前面说过了
				if (err < 0)
					break;
				cnt = packets;
			}
			// 下面这一段就是做标记动作
			if (!(TCP_SKB_CB(skb)->sacked & (TCPCB_SACKED_ACKED|TCPCB_LOST))) {
				TCP_SKB_CB(skb)->sacked |= TCPCB_LOST;   // 标识
				tp->lost_out += tcp_skb_pcount(skb);     // 丢失包+=
				tcp_verify_retransmit_hint(tp, skb);     // 其实就是标记这个丢失，加入重传标记队列
			   }
		}
		tcp_verify_left_out(tp);
	}
```

看一下tcp_verify_retransmit_hint函数：
```
	static void tcp_verify_retransmit_hint(struct tcp_sock *tp, struct sk_buff *skb)
	{
		if ((tp->retransmit_skb_hint == NULL) ||
			before(TCP_SKB_CB(skb)->seq,
			   TCP_SKB_CB(tp->retransmit_skb_hint)->seq))
			tp->retransmit_skb_hint = skb;    // 加入这个队列
	 
		if (!tp->lost_out ||
			after(TCP_SKB_CB(skb)->end_seq, tp->retransmit_high))   // 如果最后一个数据标号比high大，明显更新high
			tp->retransmit_high = TCP_SKB_CB(skb)->end_seq;
	}
```

OK，再看一下这个函数tcp_try_undo_recovery：
```
	static int tcp_try_undo_recovery(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
	 
		if (tcp_may_undo(tp)) {  // 如果可以undo
			/* Happy end! We did not retransmit anything
			 * or our original transmission succeeded.
			 */
			DBGUNDO(sk, inet_csk(sk)->icsk_ca_state == TCP_CA_Loss ? "loss" : "retrans");
			tcp_undo_cwr(sk, 1);   // 具体处理
			if (inet_csk(sk)->icsk_ca_state == TCP_CA_Loss)
				NET_INC_STATS_BH(LINUX_MIB_TCPLOSSUNDO);
			else
				NET_INC_STATS_BH(LINUX_MIB_TCPFULLUNDO);
			tp->undo_marker = 0;
		}
		if (tp->snd_una == tp->high_seq && tcp_is_reno(tp)) {
			/* Hold old state until something *above* high_seq
			 * is ACKed. For Reno it is MUST to prevent false
			 * fast retransmits (RFC2582). SACK TCP is safe. */
			tcp_moderate_cwnd(tp);   // 更新窗口大小
			return 1;
		}
		tcp_set_ca_state(sk, TCP_CA_Open);
		return 0;
	}
```

OK看一下tcp_may_undo函数：检测能否撤销
```
	static inline bool tcp_may_undo(const struct tcp_sock *tp)
	{
		return tp->undo_marker && (!tp->undo_retrans || tcp_packet_delayed(tp));
	}
```

首先得有undo_marker标识才OK！然后undo_retrans的意思是最近的Recovery时间内重传的数据包个数，如果收到一个DSACK那么undo_retrans减一，如果最后等于0，那么说明都被确认了，没有必要重传，所以没有必要调整窗口。或tcp_packet_delayed(tp)条件。如下：
```
	static inline int tcp_packet_delayed(struct tcp_sock *tp)
	{
		return !tp->retrans_stamp ||
			(tp->rx_opt.saw_tstamp && tp->rx_opt.rcv_tsecr &&
			 (__s32)(tp->rx_opt.rcv_tsecr - tp->retrans_stamp) < 0); // 接收ACK时间在重传数据之前
	}
```
下面 看一下这个函数tcp_complete_cwr：
```
	static inline void tcp_complete_cwr(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		tp->snd_cwnd = min(tp->snd_cwnd, tp->snd_ssthresh);   // 调整窗口
		tp->snd_cwnd_stamp = tcp_time_stamp;
		tcp_ca_event(sk, CA_EVENT_COMPLETE_CWR); // 出发事件
	}
```

```
	/* CWND moderation, preventing bursts due to too big ACKs
	 * in dubious situations.
	 */
	static inline void tcp_moderate_cwnd(struct tcp_sock *tp)  // 修改窗口值
	{
		tp->snd_cwnd = min(tp->snd_cwnd,
				   tcp_packets_in_flight(tp) + tcp_max_burst(tp));  // 防止怀疑的ACK情况，所以取min值
		tp->snd_cwnd_stamp = tcp_time_stamp;
	}
```
--------

再看看这个函数tcp_try_undo_dsack：当DSACK确认所有的重传数据，那么undo_retrans=0，那么需要回复窗口原来的情况
```
	/* Try to undo cwnd reduction, because D-SACKs acked all retransmitted data */
	static void tcp_try_undo_dsack(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
	 
		if (tp->undo_marker && !tp->undo_retrans) {  // 所有的段都被确认了
			DBGUNDO(sk, "D-SACK");
			tcp_undo_cwr(sk, 1);		             // 撤销（1）
			tp->undo_marker = 0;
			NET_INC_STATS_BH(LINUX_MIB_TCPDSACKUNDO);
		}
	}
```

撤销函数
```
	static void tcp_undo_cwr(struct sock *sk, const int undo)
	{
		struct tcp_sock *tp = tcp_sk(sk);
	 
		if (tp->prior_ssthresh) {  // 如果保存了旧的门限值
			const struct inet_connection_sock *icsk = inet_csk(sk);
	 
			if (icsk->icsk_ca_ops->undo_cwnd)
				tp->snd_cwnd = icsk->icsk_ca_ops->undo_cwnd(sk);           // 这个函数可以自己添加
			else
				tp->snd_cwnd = max(tp->snd_cwnd, tp->snd_ssthresh << 1);   // 如果没有定义那个函数，那么做简单的处理
	 
			if (undo && tp->prior_ssthresh > tp->snd_ssthresh) {
				tp->snd_ssthresh = tp->prior_ssthresh;
				TCP_ECN_withdraw_cwr(tp);
			}
		} else {                 // 没有保存旧的阈值
			tp->snd_cwnd = max(tp->snd_cwnd, tp->snd_ssthresh);   // 
		}
		tcp_moderate_cwnd(tp);   // 上面已经说了
		tp->snd_cwnd_stamp = tcp_time_stamp;
	 
		/* There is something screwy going on with the retrans hints after
		   an undo */
		tcp_clear_all_retrans_hints(tp);      // 清空所有的重传信息
	}
```

-------
接收到重复的ACK，那么需要对sacked_out处理，看函数tcp_add_reno_sack：
```
	/* Emulate SACKs for SACKless connection: account for a new dupack. */
	 
	static void tcp_add_reno_sack(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		tp->sacked_out++;                    // 收到重复的ACK，那么这个值++
		tcp_check_reno_reordering(sk, 0);    // 检查是否有reordering（1）
		tcp_verify_left_out(tp);   // 
	}
```

看看这个检查reordering函数：
```
	/* If we receive more dupacks than we expected counting segments
	 * in assumption of absent reordering, interpret this as reordering.
	 * The only another reason could be bug in receiver TCP.
	 */
	static void tcp_check_reno_reordering(struct sock *sk, const int addend)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		if (tcp_limit_reno_sacked(tp))   	// 检查sack的数量是否超过限度
			tcp_update_reordering(sk, tp->packets_out + addend, 0); // 如果是reordering则更新reordering
	}
```

```
	/* Limits sacked_out so that sum with lost_out isn't ever larger than
	 * packets_out. Returns zero if sacked_out adjustement wasn't necessary.
	 */
	int tcp_limit_reno_sacked(struct tcp_sock *tp)  // 限制sacked_out目的是使得sacked_out + lost_out <= packeted_out
	{					       
		u32 holes;
	 
		holes = max(tp->lost_out, 1U);              // 获得hole
		holes = min(holes, tp->packets_out);
	 
		if ((tp->sacked_out + holes) > tp->packets_out) {   // 如果大于发出的包，那么reordering就需要了
			tp->sacked_out = tp->packets_out - holes;       // 因为此处的dup-ack是reorder造成的
			return 1;
		}
		return 0;
	}
```

下面看看更新reordering函数tcp_update_reordering：
```
	static void tcp_update_reordering(struct sock *sk, const int metric,
					  const int ts)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		if (metric > tp->reordering) {                          // 如果现在的数量 > 之前的reorder
			tp->reordering = min(TCP_MAX_REORDERING, metric);   // 获得ordering值(注意不能超过最大设置值)
	 
			/* This exciting event is worth to be remembered. 8) */
			if (ts)
				NET_INC_STATS_BH(LINUX_MIB_TCPTSREORDER);	 // 统计信息
			else if (tcp_is_reno(tp))
				NET_INC_STATS_BH(LINUX_MIB_TCPRENOREORDER);
			else if (tcp_is_fack(tp))
				NET_INC_STATS_BH(LINUX_MIB_TCPFACKREORDER);
			else
				NET_INC_STATS_BH(LINUX_MIB_TCPSACKREORDER);
	#if FASTRETRANS_DEBUG > 1
			printk(KERN_DEBUG "Disorder%d %d %u f%u s%u rr%d\n",
				   tp->rx_opt.sack_ok, inet_csk(sk)->icsk_ca_state,
				   tp->reordering,
				   tp->fackets_out,
				   tp->sacked_out,
				   tp->undo_marker ? tp->undo_retrans : 0);
	#endif
			tcp_disable_fack(tp);       // 禁用fack(fack是基于有序的，因为已经使用order了，所以禁用fack)
		}
	}
```

------
下面再看一下这个tcp_try_undo_partial函数：在恢复状态，收到部分ACK确认，使用这个函数撤销拥塞调整。
```
	/* Undo during fast recovery after partial ACK. */
	 
	static int tcp_try_undo_partial(struct sock *sk, int acked)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		/* Partial ACK arrived. Force Hoe's retransmit. */ // 收到部分ACK，对于SACK来说不需要重传，对于RENO需要
		int failed = tcp_is_reno(tp) || (tcp_fackets_out(tp) > tp->reordering);  // 或者facked_out数量比reordering要大
	 
		if (tcp_may_undo(tp)) {    // 是否可以调整（上面已说）
			/* Plain luck! Hole if filled with delayed
			 * packet, rather than with a retransmit.
			 */
			if (tp->retrans_out == 0)       // 重传包=0
				tp->retrans_stamp = 0;      // 重置重传时间
	 
			tcp_update_reordering(sk, tcp_fackets_out(tp) + acked, 1);   // 需要更新reordering( 上面 )
	 
			DBGUNDO(sk, "Hoe");
			tcp_undo_cwr(sk, 0);   // 撤销操作( 上面 )
			NET_INC_STATS_BH(LINUX_MIB_TCPPARTIALUNDO);
	 
			/* So... Do not make Hoe's retransmit yet.
			 * If the first packet was delayed, the rest
			 * ones are most probably delayed as well.
			 */
			failed = 0;            // 表示不用重传了，可以发送新的数据
		}
		return failed;             // 返回是否需要重传
	}
```

-----
下面继续看tcp_try_undo_loss函数：收到部分确认之后，从loss状态撤销窗口调整
```
	/* Undo during loss recovery after partial ACK. */
	static int tcp_try_undo_loss(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
	 
		if (tcp_may_undo(tp)) {                    // 如果可以undo
			struct sk_buff *skb;
			tcp_for_write_queue(skb, sk) {         // 遍历整个发送queue
				if (skb == tcp_send_head(sk))      // 直到还没有发送的数据头之前(前面的都已经发送)
					break;
				TCP_SKB_CB(skb)->sacked &= ~TCPCB_LOST;  // 清除LOST标记
			}
	 
			tcp_clear_all_retrans_hints(tp);       // 清除所有的重传信息
	 
			DBGUNDO(sk, "partial loss");
			tp->lost_out = 0;                      // 重置
			tcp_undo_cwr(sk, 1);                   // 撤销窗口调整
			NET_INC_STATS_BH(LINUX_MIB_TCPLOSSUNDO);
			inet_csk(sk)->icsk_retransmits = 0;
			tp->undo_marker = 0;
			if (tcp_is_sack(tp))
				tcp_set_ca_state(sk, TCP_CA_Open);  // 设置状态OPEN
			return 1;
		}
		return 0;
	}
```

----
下面看一下tcp_update_scoreboard函数：其实就是更新lost包数量，这个涉及到不同的算法不一样的结果，没有SACK(reno)，有SACK，有FACK情况

1) 没有SACK：每次收到重复的ACK或部分ack时，标志一个包为丢失。

2)    有SACK：sacked_out - reordering > 0 时候，标记为这么多丢失，若小于0，标记为1个丢失(前提是有重传标识)

3)    有FACK：fackets_out - reordering  >0 时候，标记为这么多丢失，若小于0，标记为1个丢失

( 注意：小于0的情况是因为考虑到reordering情况 )
```
	/* Account newly detected lost packet(s) */
	 
	static void tcp_update_scoreboard(struct sock *sk, int fast_rexmit)
	{
		struct tcp_sock *tp = tcp_sk(sk);
	 
		if (tcp_is_reno(tp)) {              // 最普通的，没有SACK情况
			tcp_mark_head_lost(sk, 1);      // 标记为一个丢失
		} else if (tcp_is_fack(tp)) {       // 如果是fack
			int lost = tp->fackets_out - tp->reordering;  // 判断这个值大小
			if (lost <= 0)
				lost = 1;  // 小于0指标记一个
			tcp_mark_head_lost(sk, lost);   // 否则标记所有的
		} else {   // 仅仅有SACK情况
			int sacked_upto = tp->sacked_out - tp->reordering;
			if (sacked_upto < fast_rexmit)
				sacked_upto = fast_rexmit;
			tcp_mark_head_lost(sk, sacked_upto);   // 同上
		}
	 
		/* New heuristics: it is possible only after we switched
		 * to restart timer each time when something is ACKed.
		 * Hence, we can detect timed out packets during fast
		 * retransmit without falling to slow start.
		 */
		if (tcp_is_fack(tp) && tcp_head_timedout(sk)) {   // 下面检查超时包( 先检查第一个数据包是否超时 )
			struct sk_buff *skb;
	 
			skb = tp->scoreboard_skb_hint ? tp->scoreboard_skb_hint
				: tcp_write_queue_head(sk);
	 
			tcp_for_write_queue_from(skb, sk) {
				if (skb == tcp_send_head(sk))
					break;
				if (!tcp_skb_timedout(sk, skb))  // 检查所有的超时包，没有超时的就break
					break;
	 
				if (!(TCP_SKB_CB(skb)->sacked & (TCPCB_SACKED_ACKED|TCPCB_LOST))) {
					TCP_SKB_CB(skb)->sacked |= TCPCB_LOST;   // 标记为lost
					tp->lost_out += tcp_skb_pcount(skb);     // 增加lost数量
					tcp_verify_retransmit_hint(tp, skb);     
				}
			}
	 
			tp->scoreboard_skb_hint = skb;
	 
			   tcp_verify_left_out(tp);
		}
	}
```

------
下面继续看这个减小窗口函数：tcp_cwnd_down，
```
	/* Decrease cwnd each second ack. */ // 每收到2个确认将拥塞窗口减1，直到拥塞窗口等于慢启动阈值。
	static void tcp_cwnd_down(struct sock *sk, int flag)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		int decr = tp->snd_cwnd_cnt + 1; // 计数器
	 
		if ((flag & (FLAG_ANY_PROGRESS | FLAG_DSACKING_ACK)) ||
			(tcp_is_reno(tp) && !(flag & FLAG_NOT_DUP))) {
			tp->snd_cwnd_cnt = decr & 1;// 因为此处只可能是0,1三个值，这样的操作其实就是切换值，
										// 例如现在是第一个ACK，即之前的snd_cwnd_cnt=0，decr=1，那么1&1=1，
										// 将snd_cwnd_cnt赋值为1；第二个ACK到来，decr=2，则2&1=0，
										// 相当于又将snd_cwnd_cnt初始化为0，因为两个ACK就需要处理一次。
			decr >>= 1;   // 除以2，是判断是第一个ACK，还是第二个；第一个的话值=0，下面不会执行，是2的话=1，下面一句会执行
	 
			if (decr && tp->snd_cwnd > tcp_cwnd_min(sk)) // 如果是第二个ACK && 比最小的门限值还大一点，那么还需要减小cwnd
				tp->snd_cwnd -= decr;   // 减小一个，^_^
	 
			tp->snd_cwnd = min(tp->snd_cwnd, tcp_packets_in_flight(tp) + 1);  // 用于微调，和外面的数据包数量比较
			tp->snd_cwnd_stamp = tcp_time_stamp;    // 改变时间戳
		} 
	}
```


