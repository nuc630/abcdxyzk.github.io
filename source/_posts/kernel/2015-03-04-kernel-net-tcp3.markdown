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

```
	/* This retransmits one SKB.  Policy decisions and retransmit queue
	 * state updates are done by the caller.  Returns non-zero if an
	 * error occurred which prevented the send.
	 */
	int tcp_retransmit_skb(struct sock *sk, struct sk_buff *skb)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk);
		unsigned int cur_mss = tcp_current_mss(sk, 0);
		int err;
	 
		/* Inconslusive MTU probe */
		if (icsk->icsk_mtup.probe_size) {
			icsk->icsk_mtup.probe_size = 0;
		}
	 
		/* Do not sent more than we queued. 1/4 is reserved for possible  
		 * copying overhead: fragmentation, tunneling, mangling etc.
		 */ // 如果消耗很多的内存做其他事，那么就没有多余的来做队列的处理了~
		if (atomic_read(&sk->sk_wmem_alloc) >	                 // sk_wmem_alloc：传输队列大小
			min(sk->sk_wmem_queued + (sk->sk_wmem_queued >> 2), sk->sk_sndbuf))  // sk_wmem_queud：固定的队列大小
			return -EAGAIN;
	 
		if (before(TCP_SKB_CB(skb)->seq, tp->snd_una)) {         // 若这样，说明是有一部分数据才需要重传，形如：seq---snd_una---end_seq，前面一半已收到ACK
			if (before(TCP_SKB_CB(skb)->end_seq, tp->snd_una))   // 若这样，说明全部ACK，无需重传，BUG
				BUG();
			if (tcp_trim_head(sk, skb, tp->snd_una - TCP_SKB_CB(skb)->seq))      // 一些控制信息检查
				return -ENOMEM;
		}
	 
		/* If receiver has shrunk his window, and skb is out of
		 * new window, do not retransmit it. The exception is the
		 * case, when window is shrunk to zero. In this case
		 * our retransmit serves as a zero window probe.
		 */
		if (!before(TCP_SKB_CB(skb)->seq, tcp_wnd_end(tp))    // 如果数据在窗口后面，不会发送
			&& TCP_SKB_CB(skb)->seq != tp->snd_una)   
			   return -EAGAIN;
	 
		if (skb->len > cur_mss) {    // 如果skb长度 > MSS
			if (tcp_fragment(sk, skb, cur_mss, cur_mss))      // 先分片。再传送
				return -ENOMEM; /* We'll try again later. */
		}
	 
		/* Collapse two adjacent packets if worthwhile and we can. */   // 我*，这么多条件
		if (!(TCP_SKB_CB(skb)->flags & TCPCB_FLAG_SYN) &&               // SYN包
			(skb->len < (cur_mss >> 1)) &&                              // 长度<半个MSS
			(tcp_write_queue_next(sk, skb) != tcp_send_head(sk)) &&     // 不是结尾
			(!tcp_skb_is_last(sk, skb)) &&                              // 不是最后一个
			(skb_shinfo(skb)->nr_frags == 0 &&                          // 没有分页数据
			 skb_shinfo(tcp_write_queue_next(sk, skb))->nr_frags == 0) &&
			(tcp_skb_pcount(skb) == 1 &&                                // gso_segs=1
			 tcp_skb_pcount(tcp_write_queue_next(sk, skb)) == 1) &&
			(sysctl_tcp_retrans_collapse != 0))
			tcp_retrans_try_collapse(sk, skb, cur_mss);                 // 这个函数不是很明白，待看~~~~~~~~~~~~~~~~~~~~~~~~~
	 
		if (inet_csk(sk)->icsk_af_ops->rebuild_header(sk))              // 根据目的地址等条件获取路由，如果获取路由失败就不能发送
			return -EHOSTUNREACH; /* Routing failure or similar. */
	 
		/* Some Solaris stacks overoptimize and ignore the FIN on a
		 * retransmit when old data is attached.  So strip it off
		 * since it is cheap to do so and saves bytes on the network.
		 *///Solaris系统的协议栈有时候会忽略重传SKB上带有的FIN标志的payload，将payload全部剥离掉，节省网络流量
		if (skb->len > 0 &&
			(TCP_SKB_CB(skb)->flags & TCPCB_FLAG_FIN) &&
			tp->snd_una == (TCP_SKB_CB(skb)->end_seq - 1)) {
			if (!pskb_trim(skb, 0)) {
				/* Reuse, even though it does some unnecessary work */
				tcp_init_nondata_skb(skb, TCP_SKB_CB(skb)->end_seq - 1,
							 TCP_SKB_CB(skb)->flags);
				skb->ip_summed = CHECKSUM_NONE;
			}
		}
	 
		/* Make a copy, if the first transmission SKB clone we made
		 * is still in somebody's hands, else make a clone.
		 */
		TCP_SKB_CB(skb)->when = tcp_time_stamp;
	 
		err = tcp_transmit_skb(sk, skb, 1, GFP_ATOMIC);     // 这个才是正在的传输函数~~~~~~~~~~~~~~~~~~~~后面再说~~~~~~~~~~~~~~~
                                                            // 这个函数就是将数据包发送到下面一层，再慢慢传输出去~~~~~~~~~~~~~~
		if (err == 0) {    // 发送成功，那么就需要更新TCP统计信息
			/* Update global TCP statistics. */  
			TCP_INC_STATS(TCP_MIB_RETRANSSEGS);
	 
			tp->total_retrans++;   // 整体重传数量++
	 
	#if FASTRETRANS_DEBUG > 0
			if (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS) {
				if (net_ratelimit())
					printk(KERN_DEBUG "retrans_out leaked.\n");
			}
	#endif
			if (!tp->retrans_out)
				tp->lost_retrans_low = tp->snd_nxt;
			TCP_SKB_CB(skb)->sacked |= TCPCB_RETRANS;
			tp->retrans_out += tcp_skb_pcount(skb);         // 重传出去的数量+=。。。
	 
			/* Save stamp of the first retransmit. */
			if (!tp->retrans_stamp)
				tp->retrans_stamp = TCP_SKB_CB(skb)->when;  // 第一次重传时间戳
	 
			tp->undo_retrans++;
	 
			/* snd_nxt is stored to detect loss of retransmitted segment,
			 * see tcp_input.c tcp_sacktag_write_queue().
			 */
			TCP_SKB_CB(skb)->ack_seq = tp->snd_nxt;
		}
		return err;
	}
```

