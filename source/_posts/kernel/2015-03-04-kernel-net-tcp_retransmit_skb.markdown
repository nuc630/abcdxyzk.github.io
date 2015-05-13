---
layout: post
title: "tcp重传数据包 tcp_retransmit_skb 函数"
date: 2015-03-04 17:39:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/shanshanpt/article/details/22202999

基于CentOS6.5  2.6.32-504.16.2.el6.x86_64

#### tcp_retransmit_skb 重传数据
```
	/* This retransmits one SKB.  Policy decisions and retransmit queue
	 * state updates are done by the caller.  Returns non-zero if an
	 * error occurred which prevented the send.
	 */ // 如果消耗很多的内存做其他事，那么就没有多余的来做队列的处理了
	int tcp_retransmit_skb(struct sock *sk, struct sk_buff *skb)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);
		unsigned int cur_mss;
		int err;

		/* Inconslusive MTU probe */
		if (icsk->icsk_mtup.probe_size) {
			icsk->icsk_mtup.probe_size = 0;
		}

		/* Do not sent more than we queued. 1/4 is reserved for possible
		 * copying overhead: fragmentation, tunneling, mangling etc.
		 */
		if (atomic_read(&sk->sk_wmem_alloc) >                                    // sk_wmem_alloc：传输队列大小
			min(sk->sk_wmem_queued + (sk->sk_wmem_queued >> 2), sk->sk_sndbuf))  // sk_wmem_queud：固定的队列大小
			return -EAGAIN;

		if (before(TCP_SKB_CB(skb)->seq, tp->snd_una)) {         // 若这样，说明是有一部分数据才需要重传，形如：seq---snd_una---end_seq，前面一半已收到ACK
			if (before(TCP_SKB_CB(skb)->end_seq, tp->snd_una))   // 若这样，说明全部ACK，无需重传，BUG
				BUG();
			if (tcp_trim_head(sk, skb, tp->snd_una - TCP_SKB_CB(skb)->seq))      // 将无须重传的部分去掉
				return -ENOMEM;
		}

		if (inet_csk(sk)->icsk_af_ops->rebuild_header(sk))
			return -EHOSTUNREACH; /* Routing failure or similar. */

		cur_mss = tcp_current_mss(sk);

		/* If receiver has shrunk his window, and skb is out of
		 * new window, do not retransmit it. The exception is the
		 * case, when window is shrunk to zero. In this case
		 * our retransmit serves as a zero window probe.
		 */
		if (!before(TCP_SKB_CB(skb)->seq, tcp_wnd_end(tp))       // 如果数据在窗口后面，不会发送
			&& TCP_SKB_CB(skb)->seq != tp->snd_una)
			return -EAGAIN;
		if (skb->len > cur_mss) {                                // 如果skb长度 > MSS
			if (tcp_fragment(sk, skb, cur_mss, cur_mss))         // 先分片，并调整packet_out等统计值。再传送
				return -ENOMEM; /* We'll try again later. */
		} else {
			int oldpcount = tcp_skb_pcount(skb);

			if (unlikely(oldpcount > 1)) {
				tcp_init_tso_segs(sk, skb, cur_mss);             // 按当前mss重置skb->gso_XXX
				tcp_adjust_pcount(sk, skb, oldpcount - tcp_skb_pcount(skb)); // 调整packet_out等统计值
			}
		}

		tcp_retrans_try_collapse(sk, skb, cur_mss);              // 尝试和后几个包合并后一起重传出去，加快速度

		/* Some Solaris stacks overoptimize and ignore the FIN on a
		 * retransmit when old data is attached.  So strip it off
		 * since it is cheap to do so and saves bytes on the network.
		 */ //Solaris系统的协议栈有时候会忽略重传SKB上带有的FIN标志的payload，将payload全部剥离掉，节省网络流量
		if (skb->len > 0 &&
			(TCP_SKB_CB(skb)->tcp_flags & TCPHDR_FIN) &&
			tp->snd_una == (TCP_SKB_CB(skb)->end_seq - 1)) {
			if (!pskb_trim(skb, 0)) {
				/* Reuse, even though it does some unnecessary work */
				tcp_init_nondata_skb(skb, TCP_SKB_CB(skb)->end_seq - 1,
							 TCP_SKB_CB(skb)->tcp_flags);
				skb->ip_summed = CHECKSUM_NONE;
			}
		}

		/* Make a copy, if the first transmission SKB clone we made
		 * is still in somebody's hands, else make a clone.
		 */
		TCP_SKB_CB(skb)->when = tcp_time_stamp;

		/* make sure skb->data is aligned on arches that require it
		 * and check if ack-trimming & collapsing extended the headroom
		 * beyond what csum_start can cover.
		 */
		if (unlikely((NET_IP_ALIGN && ((unsigned long)skb->data & 3)) ||
				 skb_headroom(skb) >= 0xFFFF)) {
			struct sk_buff *nskb = __pskb_copy(skb, MAX_TCP_HEADER,
							   GFP_ATOMIC);
			err = nskb ? tcp_transmit_skb(sk, nskb, 0, GFP_ATOMIC) :
					 -ENOBUFS;
		} else {
			err = tcp_transmit_skb(sk, skb, 1, GFP_ATOMIC);     // 这个才是正在的传输函数
		}

		if (err == 0) {                                         // 发送成功，那么就需要更新TCP统计信息
			/* Update global TCP statistics. */
			TCP_INC_STATS(sock_net(sk), TCP_MIB_RETRANSSEGS);

			tp->total_retrans++;                                // 整体重传数量++

	#if FASTRETRANS_DEBUG > 0
			if (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS) {
				if (net_ratelimit())
					printk(KERN_DEBUG "retrans_out leaked.\n");
			}
	#endif
			if (!tp->retrans_out)
				tp->lost_retrans_low = tp->snd_nxt;
			TCP_SKB_CB(skb)->sacked |= TCPCB_RETRANS;
			tp->retrans_out += tcp_skb_pcount(skb);             // 重传出去的数量+=。。。

			/* Save stamp of the first retransmit. */
			if (!tp->retrans_stamp)
				tp->retrans_stamp = TCP_SKB_CB(skb)->when;      // 第一次重传时间戳

			tp->undo_retrans += tcp_skb_pcount(skb);

			/* snd_nxt is stored to detect loss of retransmitted segment,
			 * see tcp_input.c tcp_sacktag_write_queue().
			 */
			TCP_SKB_CB(skb)->ack_seq = tp->snd_nxt;
		}
		return err;
	}
```

#### tcp_retrans_try_collapse 重传时尝试和后几个包合并后传出去
```
	// 只做简单合并，所以条件设置严格
	/* Check if coalescing SKBs is legal. */
	static int tcp_can_collapse(struct sock *sk, struct sk_buff *skb)
	{
		if (tcp_skb_pcount(skb) > 1)         // skb只包含一个数据包，没有TSO分包
			return 0;
		/* TODO: SACK collapsing could be used to remove this condition */
		if (skb_shinfo(skb)->nr_frags != 0)  // 数据都在线性空间，非线性空间中没有数据
			return 0;
		if (skb_cloned(skb))                 // 不是clone
			return 0;
		if (skb == tcp_send_head(sk))
			return 0;
		/* Some heurestics for collapsing over SACK'd could be invented */
		if (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED)  // 已经被sack的当然不用重传
			return 0;

		return 1;
	}

	/* Collapse packets in the retransmit queue to make to create
	 * less packets on the wire. This is only done on retransmission.
	 */
	static void tcp_retrans_try_collapse(struct sock *sk, struct sk_buff *to,
						 int space)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb = to, *tmp;
		int first = 1;

		if (!sysctl_tcp_retrans_collapse)
			return;
		if (TCP_SKB_CB(skb)->tcp_flags & TCPHDR_SYN)  // SYN包不合并
			return;

		tcp_for_write_queue_from_safe(skb, tmp, sk) {
			if (!tcp_can_collapse(sk, skb))           // 要和并的包判断是否符合条件
				break;

			space -= skb->len;

			if (first) {
				first = 0;
				continue;
			}

			if (space < 0)
				break;
			/* Punt if not enough space exists in the first SKB for
			 * the data in the second
			 */
			if (skb->len > skb_tailroom(to))          // 第一个包的tailroom空间足够容下该包
				break;

			if (after(TCP_SKB_CB(skb)->end_seq, tcp_wnd_end(tp))) // 大于窗口不合并
				break;

			tcp_collapse_retrans(sk, to);             // 进行两个包的合并
		}
	}
```

#### tcp_collapse_retrans 重传合并
```
	/* Collapses two adjacent SKB's during retransmission. */
	static void tcp_collapse_retrans(struct sock *sk, struct sk_buff *skb)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *next_skb = tcp_write_queue_next(sk, skb);
		int skb_size, next_skb_size;

		skb_size = skb->len;
		next_skb_size = next_skb->len;

		BUG_ON(tcp_skb_pcount(skb) != 1 || tcp_skb_pcount(next_skb) != 1);

		tcp_highest_sack_combine(sk, next_skb, skb);

		tcp_unlink_write_queue(next_skb, sk);    // 将要合并的包从队列中删掉

		skb_copy_from_linear_data(next_skb, skb_put(skb, next_skb_size),
					  next_skb_size);            // 将数据copy到前一个包上，调整前一个的len，tail

		if (next_skb->ip_summed == CHECKSUM_PARTIAL)
			skb->ip_summed = CHECKSUM_PARTIAL;

		if (skb->ip_summed != CHECKSUM_PARTIAL)
			skb->csum = csum_block_add(skb->csum, next_skb->csum, skb_size);

		/* Update sequence range on original skb. */
		TCP_SKB_CB(skb)->end_seq = TCP_SKB_CB(next_skb)->end_seq;  // end_seq 等于后一个包的end_seq，所以如果skb->end_seq > next_skb->seq，就会合并出一个len>end_seq-seq的异常数据(内核保证了sk_write_queue不会出现这情况)

		/* Merge over control information. This moves PSH/FIN etc. over */
		TCP_SKB_CB(skb)->tcp_flags |= TCP_SKB_CB(next_skb)->tcp_flags;

		/* All done, get rid of second SKB and account for it so
		 * packet counting does not break.
		 */
		TCP_SKB_CB(skb)->sacked |= TCP_SKB_CB(next_skb)->sacked & TCPCB_EVER_RETRANS;

		/* changed transmit queue under us so clear hints */
		tcp_clear_retrans_hints_partial(tp);
		if (next_skb == tp->retransmit_skb_hint)
			tp->retransmit_skb_hint = skb;

		tcp_adjust_pcount(sk, next_skb, tcp_skb_pcount(next_skb)); // 调整pcount

		sk_wmem_free_skb(sk, next_skb);        // 合并到了前一个包上，所以释放这个包
	}
```


