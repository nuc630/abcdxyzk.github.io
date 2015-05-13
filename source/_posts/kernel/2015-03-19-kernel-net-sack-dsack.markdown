---
layout: post
title: "TCP的核心系列 — SACK和DSACK的实现"
date: 2015-03-19 16:27:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
[TCP的核心系列 — SACK和DSACK的实现（一）](http://blog.csdn.net/zhangskd/article/details/9613347)  
[TCP的核心系列 — SACK和DSACK的实现（二）](http://blog.csdn.net/zhangskd/article/details/8979718)  
[TCP的核心系列 — SACK和DSACK的实现（三）](http://blog.csdn.net/zhangskd/article/details/9706113)  
[TCP的核心系列 — SACK和DSACK的实现（四）](http://blog.csdn.net/zhangskd/article/details/9766895)  
[TCP的核心系列 — SACK和DSACK的实现（五）](http://blog.csdn.net/zhangskd/article/details/9768315)  
[TCP的核心系列 — SACK和DSACK的实现（六）](http://blog.csdn.net/zhangskd/article/details/9768519)  
[TCP的核心系列 — SACK和DSACK的实现（七）](http://blog.csdn.net/zhangskd/article/details/9698901)  

-------------

### TCP的核心系列 — SACK和DSACK的实现（一）

TCP的实现中，SACK和DSACK是比较重要的一部分。

SACK和DSACK的处理部分由Ilpo Järvinen (ilpo.jarvinen@helsinki.fi) 维护。

tcp_ack()处理接收到的带有ACK标志的数据段时，如果此ACK处于慢速路径，且此ACK的记分牌不为空，则调用  
tcp_sacktag_write_queue()来根据SACK选项标记发送队列中skb的记分牌状态。

笔者主要分析18和37这两个版本的实现。  
相对而言，18版本的逻辑清晰，但效率较低；37版本的逻辑复杂，但效率较高。

本文主要内容：18版tcp_sacktag_write_queue()的实现，也即18版SACK和DSACK的实现。

#### 18版数据结构
```
	/* 这就是一个SACK块 */
	struct tcp_sack_block {
		u32 start_seq;  /* 起始序号 */
		u32 end_seq;    /* 结束序号 */
	};
```
```
	struct tcp_sock {
		...
		/* Options received (usually on last packet, some only on SYN packets). */
		struct tcp_options_received rx_opt;
		...
		struct tcp_sack_block recv_sack_cache[4]; /* 保存收到的SACK块，用于提高效率*/
		...
		/* 快速路径中使用，上次第一个SACK块的结束处，现在直接从这里开始处理 */
		struct sk_buff *fastpath_skb_hint;
		int fastpath_cnt_hint;  /* 快速路径中使用，上次记录的fack_count，现在继续累加 */
		...

	};
```

```
	struct tcp_options_received {
		...
		u16 saw_tstamp : 1,    /* Saw TIMESTAMP on last packet */
			tstamp_ok : 1,     /* TIMESTAMP seen on SYN packet */
			dsack : 1,         /* D-SACK is scheduled, 下一个发送段是否存在D-SACK */
			sack_ok : 4,       /* SACK seen on SYN packet, 接收方是否支持SACK */
			...
		u8 num_sacks;          /* Number of SACK blocks, 下一个发送段中SACK块数 */
		...
	};
```

<!-- more -->

#### 18版本实现
18版本的逻辑较清晰，我们先来看看。
```
	static int tcp_sacktag_write_queue(struct sock *sk, struct sk_buff *ack_skb, u32 prior_snd_una)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);

		/* SACK选项的起始地址，sacked为SACK选项在TCP首部的偏移 */
		unsigned char *ptr = ack_skb->h.raw + TCP_SKB_CB(ack_skb)->sacked;

		struct tcp_sack_block *sp = (struct tcp_sack_block *) (ptr + 2); /* 指向第一个sack块 */
		int num_sacks = (ptr[1] - TCPOLEN_SACK_BASE) >> 3;               /* sack的块数 */

		int reord = tp->packets_out;     /* 乱序的起始包位置，一开始设为最大 */
		int prior_fackets;               /* 上次的fackets_out */
		u32 lost_retrans = 0;            /* 重传包可能丢失时SACK块结束序号，表示需要遍历到的最高序号 */
		int flag = 0;                    /* 有两种用途：先表示是否为快速路径，后用于返回标志 */
		int dup_sack = 0;                /* 有没有DSACK */
		int i;

		/* 如果之前没有SACKed的数据 */
		if (! tp->sacked_out)
			tp->fackets_out = 0;         /* FACK是根据最新的SACK来计算的，所以也要为0 */
		prior_fackets = tp->fackets_out; /* 处理前先保存上次的fackets_out */

		/* SACK fastpath:
		 * if the only SACK change is the increase of the end_seq of the first block then only
		 * apply that SACK block and use retrans queue hinting otherwise slowpath.
		 * 什么是快速路径：就是只有第一个SACK块的结束序号发生变化，其它的都不变。
		 */
		flag = 1; /* 为1的话为快速路径，0为慢速路径 */

		for (i = 0; i < num_sacks; i++) {
			__u32 start_seq = ntohl(sp[i].start_seq);  /* 块的起始序号 */
			__u32 end_seq = ntohl(sp[i].end_seq);      /* 块的结束序号 */

			/* 判断是否进入快速路径。
			 * 对第一个块：只要求起始序号相同
			 * 对于非第一个块：要求起始序号和结束序号都相同
			 * 也就是说，快速路径指的是只有第一个块的结束序号增加的情况
			 */
			if (i == 0) {
				if (tp->recv_sack_cache[i].start_seq != start_seq)
					flag = 0;

			} else {
				if ((tp->recv_sack_cache[i].start_seq != start_seq) ||
					(tp->recv_sack_cache[i].end_seq != end_seq))
					flag = 0;
			}

			/* 更新，保存这次收到的SACK块 */
			tp->recv_sack_cache[i].start_seq = start_seq;
			tp->recv_sack_cache[i].end_seq = end_seq;

			/* Check for D-SACK.
			 * 检测是否有DSACK ，DSACK块如果有，只能在第一个块
			 */
			if (i == 0) {
				u32 ack = TCP_SKB_CB(ack_skb)->ack_seq;

				/* 如果第一个SACK块的起始序号小于它的确认序号，说明此SACK块包含了确认过的数据 */
				if (before(start_seq, ack)) {
					dup_sack = 1;
					tp->rx_opt.sack_ok |= 4;
					NET_INC_STATS_BH(LINUX_MIB_TCPDSACKRECV);

				/* 如果第一个SACK块包含在第二个SACK块中，也说明第一个SACK块是重复的，即DSACK */
				} else if (num_sacks > 1 &&
					!after(end_seq, ntohl(sp[1].end_seq)) &&
					!before(start_seq, ntohl(sp[1].start_seq))) {
						dup_sack = 1;
						tp->rx_opt.sack_ok |= 4;
						NET_INC_STATS_BH(LINUX_MIB_TCPDSACKOFORECV);
				}
			}

			/* D-SACK for already forgotten data...
			 * Do dumb counting.
			 * undo_retrans记录重传数据包的个数，如果undo_retrans降到0，
			 * 就说明之前的重传都是不必要的，进行拥塞调整撤销。
			 * 条件：DSACK、undo_marker < end_seq <= prior_snd_una
			 */
			if (dup_sack && !after(end_seq, prior_snd_una) &&
				after(end_seq, tp->undo_marker))
				tp->undo_retrans--;

			/* Eliminate too old ACKs, but take into account more or less fresh ones,
			 * they can contain valid SACK info.
			 * tp->max_window为接收方通告过的最大接收窗口。
			 * 如果SACK信息是很早以前的，直接丢弃。
			 */
			if (before(ack, prior_snd_una - tp->max_window))
				return 0;
		}

		if (flag)
			num_sacks = 1; /* 快速路径时只有第一个块有变化，处理第一个块即可 */
		else {
			int j;
			/* 上次第一个SACK块的结束处，也是这次快速路径的开始点，慢速路径中重置了 */
			tp->fastpath_skb_hint = NULL;

			/* order SACK blocks to allow in order walk of the retrans queue.
			 * 对SACK块按起始序号，从小到大冒泡排序，以便与接下来的顺序遍历。
			 */
			for (i = num_sacks - 1; i > 0; i--) {
				for (j = 0; j < i; j++) {
					if (after(ntohl(sp[j].start_seq), ntohl(sp[j+1].start_seq))) {
						sp[j].start_seq = htonl(tp->recv_sack_cache[j+1].start_seq);
						sp[j].end_seq = htonl(tp->recv_sack_cache[j+1].end_seq);
						sp[j+1].start_seq = htonl(tp->recv_sack_cache[j].start_seq);
						sp[j+1].end_seq = htonl(tp->recv_sack_cache[j].end_seq);
					}
				}
			}
		}

		/* clear flag as used for different purpose in following code */
		flag = 0; /* 用于返回一些标志 */

		/* 逐个处理SACK块，可能只有一个，也可能多个 */
		for (i = 0; i < num_sacks; i++, sp++) {
			struct sk_buff *skb;
			__u32 start_seq = ntohl(sp->start_seq);  /* SACK块起始序号 */
			__u32 end_seq = ntohl(sp->end_seq);      /* SACK块结束序号 */
			int fack_count;                          /* 用于更新fackets_out */

			/* Use SACK fastpath hint if valid.
			 * 如果处于快速路径，那么可以不用从头遍历发送队列。
			  */
			if (tp->fastpath_skb_hint) {
				skb = tp->fastpath_skb_hint;         /* 从这个段开始处理 */
				fack_count = tp->fastpath_cnt_hint;  /* 已有的fackets_out */

			} else {                                 /* 否则慢速路径，从头开始处理 */
				skb = sk->sk_write_queue.next;       /* 发送队列头 */
				fack_count = 0;
			}

			/* Event B in the comment above.
			 * high_seq是进入Recovery或Loss时的snd_nxt，如果high_seq被SACK了，那么很可能有数据包
			  * 丢失了，不然就可以ACK掉high_seq返回Open态了。
			  */
			if (after(end_seq, tp->high_seq))
				flag |= FLAG_DATA_LOST;

			/* 从skb开始遍历发送队列 */
			sk_stream_for_retrans_queue_from(skb, sk) {
				int in_sack, pcount;
				u8 sacked;

				/* 记录最后一个正在处理的段，下次进入快速路径时，可以直接从这里
				 * 开始处理，而不用从头遍历发送队列。
				 */
				tp->fastpath_skb_hint = skb;
				tp->fastpath_cnt_hint = fack_count;

				/* The retransmission queue is always in order, so we can short-circuit
				 * the walk early.
				 * 当前skb段的序号超过SACK块的右端时，说明这个SACK块已经处理好了。
				 */
				if (! before(TCP_SKB_CB(skb)->seq, end_seq))
					break;

				/* 这个段是否完全包含在SACK块中 */
				in_sack = ! after(start_seq, TCP_SKB_CB(skb)->seq) &&
								   ! before(end_seq, TCP_SKB_CB(skb)->end_seq);
				pcount = tcp_skb_pcount(skb); /* 这个段分为多少个包 */

				/* 如果当前的段是TSO段，且它的一部份包含在SACK块中。
				 * 那么那些已经被SACK的部分就不用再重传了，所以需要重新分割TSO段。
				 */
				if (pcount > 1 && ! in_sack &&
					after(TCP_SKB_CB(skb)->end_seq, start_seq)) {
					unsigned int pkt_len;

					/* 表示TSO段的后半部在SACK块之外 */
					in_sack = ! after(start_seq, TCP_SKB_CB(skb)->seq);

					if (! in_sack)                                    /* 如果TSO段的前半部在SACK块之外 */
						pkt_len = (start_seq - TCP_SKB_CB(skb)->seq); /* SACK块之外段的长度 */
					else
						pkt_len = (end_seq - TCP_SKB_CB(skb)->seq);   /* SACK块之内段的长度 */

					/* 把TSO段分为两部分 */
					if (tcp_fragment(sk, skb, pkt_len, skb_shinfo(skb)->gso_size))
						break;

					pcount += tcp_skb_pcount(skb); /* skb缩减了，需要重新计算 */
				}

				fack_count += pcount;              /* 累加fackets_out */

				sacked = TCP_SKB_CB(skb)->sacked;  /* 这就是记分板scoreboard */

				/* Account D-SACK for retransmitted packet.
				 * 如果此skb属于DSACK块，且skb被重传过。
				 * 这里in_sack指的是：全部包含在SACK块中，还有前半部包含也算，因为分割了：）
				 */
				if ((dup_sack && in_sack) && (sacked & TCPCB_RETRANS) &&
					after(TCP_SKB_CB(skb)->end_seq, tp->undo_marker))
					tp->undo_retrans--; /* 如果减为0，那么说明之前重传都是不必要的，进行拥塞控制调整撤销 */

				/* The frame is ACKed. 当这个skb被确认了*/
				if (! after(TCP_SKB_CB(skb)->end_seq, tp->snd_una)) {
					/* 乱序情况1：R|S标志，收到DSACK */
					if (sacked & TCPCB_RETRANS) {
						if ((dup_sack && in_sack) && (sacked & TCPCB_SACKED_ACKED))
							reord = min(fack_count, reord); /* 更新乱序的起始位置 */

					} else {
						/* 乱序情况2：一个包落在highest_sack之前，它既没被SACK过，也不是重传的，
						 * 现在才到达了，那么它就是乱序了。就是前面的洞自动填满了：）
						 */
						if (fack_count < prior_fackets && ! (sacked & TCPCB_SACKED_ACKED))
							reord = min(fack_count, reord);
					}

					/* Nothing to do; acked frame is about to be dropped.
					 * 这个skb已经被正常确认了，不用再处理了，它即将被丢弃。
					 */
					continue;
				}

				/* 如果这个包是重传包，并且它的snd_nxt小于此块的结束序号，
				 * 那么这个重传包可能是丢失了，我们记录这个块的结束序号，
				 * 作为接下来遍历的最高序号。
				 */
				if ((sacked & TCPCB_SACKED_RETRANS) &&
					after(end_seq, TCP_SKB_CB(skb)->ack_seq) &&
					(! lost_retrans || after(end_seq, lost_retrans)))
					lost_retrans = end_seq;

				/* 如果这个包不包含在SACK块中，即在SACK块之外，则不用继续处理 */
				if (! in_sack)
					continue;

				/* 如果skb还没有被标志为SACK，那么进行处理 */
				if (! (sacked & TCPCB_SACKED_ACKED)) {
					/* 有R标志，表示被重传过 */
					if (sacked & TCPCB_SACKED_RETRANS) {
						/* If the segment is not tagged as lost, we do not clear RETRANS, believing
						 * that retransmission is still in flight.
						 * 如果之前的标志是：R | L，那么好，现在收到包了，可以清除R和L。
						 * 如果之前的标志是：R，那么认为现在收到的是orig，重传包还在路上，所以不用干活：）
						 */
						if (sacked & TCPCB_LOST) {
							TCP_SKB_CB(skb)->sacked &= ~(TCPCB_LOST | TCPCB_SACKED_RETRANS); /* 取消L和R标志 */
							tp->lost_out -= tcp_skb_pcount(skb);    /* 更新LOST包个数 */
							tp->retrans_out -= tcp_skb_pcount(skb); /* 更新RETRANS包个数 */
							/* clear lost hint */
							tp->retransmit_skb_hint = NULL;
						}

					} else {
						/* New sack for not retransmitted frame, which was in hole. It is reordering.
						 * 如果一个包落在highest_sack之前，它即没被SACK过，也不是重传的，那么
						 * 它肯定是乱序了，到现在才被SACK。
						 */
						if (! (sacked & TCPCB_RETRANS) && fack_count < prior_fackets)
							reord = min(fack_count, reord); /* 记录乱序的起始 */

						/* 如果有L标志 */
						if (sacked & TCPCB_LOST) {
							TCP_SKB_CB(skb)->sacked &= ~TCPCB_LOST; /* 清除L标志 */
							tp->lost_out -= tcp_skb_pcount(skb);    /* 更新lost_out */
							/* clear lost hint */
							tp->retransmit_skb_hint = NULL;
						}
					}

					TCP_SKB_CB(skb)->sacked |= TCPCB_SACKED_ACKED;  /* 打上S标志 */
					flag |= FLAG_DATA_SACKED;                       /* New SACK */
					tp->sacked_out += tcp_skb_pcount(skb);          /* 更新sacked_out */

					if (fack_count > tp->fackets_out)
						tp->fackets_out = fack_count;               /* 更新fackets_out */

				} else { /* 已经有S标志 */
					/* 如果之前是R|S标志，且这个包被DSACK了，说明是乱序 */
					if (dup_sack && (sacked & TCPCB_RETRANS))
						reord = min(fack_count, reord);
				}

				/* D-SACK. We can detect redundant retransmission in S|R and plain R frames
				 * and clear it.
				 * undo_retrans is decreased above, L|R frames are accounted above as well.
				 * 如果skb被D-SACK，并且它的重传标志还未被清除，那么现在清除。
				 */
				if (dup_sack && (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS)) {
					TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_RETRANS;
					tp->retrans_out -= tcp_skb_pcount(skb);
					tp->retransmit_skb_hint = NULL;
				}
			}
		}

		/* Check for lost retransmit. This superb idea is borrowed from "ratehalving." Event C.
		 * 如果lost_retrans不为0，且处于Recovery状态，说明有重传包丢失，进行处理。
		 */
		if (lost_retrans && icsk->icsk_ca_state == TCP_CA_Recovery) {
			struct sk_buff *skb;

			/* 从头开始遍历发送队列 */
			sk_stream_for_retrans_queue(skb, sk) {
				/* lost_retrans记录的是SACK块结束序号，并且只在小于lost_retrans内有发现重传包丢失 */
				if (after(TCP_SKB_CB(skb)->seq, lost_retrans))
					break;

				/* 不关心成功确认过的包 */
				if (! after(TCP_SKB_CB(skb)->end_seq, tp->snd_una)
					continue;

				/* 现在判断这个重传包是否丢失。
				 * 这个包要是重传包，并且它的snd_nxt小于lost_retrans
				 */
				if ((TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS) &&
					after(lost_retrans, TCP_SKB_CB(skb)->ack_seq) &&  (IsFack(tp) ||
					!before(lost_retrans, TCP_SKB_CB(skb)->ack_seq + tp->reordering * tp->mss_cache))) {
					TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_RETRANS;   /* 清除R标志 */
					tp->retrans_out -= tcp_skb_pcount(skb);             /* 更新retrans_out */
					/* clear lost hint */
					tp->retransmit_skb_hint = NULL;

					/* 给这个包重新打上L标志 */
					if (! (TCP_SKB_CB(skb)->sacked & (TCPCB_LOST | TCPCB_SACKED_ACKED))) {
						tp->lost_out += tcp_skb_pcount(skb);            /* 更新lost_out */
						TCP_SKB_CB(skb)->sacked |= TCPCB_LOST;          /* 打上L标志 */
						/* 这个弄错了吧？应该是FLAG_DATA_LOST才对 */
						flag |= FLAG_DATA_SACKED;
						NET_INC_STATS_BH(LINUX_MIB_TCPLOSTRETRANSMIT);
					}
				}
			}
		}

		tp->left_out = tp->sacked_out + tp->lost_out;
		/* 更新乱序队列长度。
		 * 乱序队列的长度 = fackets_out - reord + 1，reord记录从第几个包开始乱序
		 */
		if ((reord < tp->fackets_out) && icsk->icsk_ca_state != TCP_CA_Loss)
			tcp_update_reordering(sk, ((tp->fackets_out + 1) - reord), 0);

	#if FASTRETRANS_DEBUG > 0
		BUG_TRAP((int) tp->sacked_out >= 0);
		BUG_TRAP((int) tp->lost_out >= 0);
		BUG_TRAP((int) tp->retrans_out >= 0);
		BUG_TRAP((int) tcp_packets_in_flight(tp) >= 0);
	#endif

		return flag;
	}
```

Q: 为什么说18版的实现效率不高呢？  
A: 我们收到num_sacks个SACK块，如果符合快速路径，那么遍历一次发送队列就可以了;  
但是如果不符合快速路径，那么对于每个SACK块，都要遍历一次发送队列，而且都是从头开始遍历，  
这样就做了很多重复工作，复杂度为O(num_sacks * cwnd)。如果cwnd很大的话，CPU消耗会较高。  
37版本在这一方面做了一些优化。

对于18版本中的一些细节，接下来会对照37版本的实现进行详细分析，比如：  
SACK选项的地址在接收时是如何保存起来的，这是在tcp_rcv_established中处理的。  
DSACK的原理和实现，这部分在37中独立出来。  
检测重传包是否丢失的原理和实现，这部分在37中独立出来。  
乱序是如何检测的，它的原理和实现。
 
##### Reference
RFC 2018  
RFC 2883  

----------------

### TCP的核心系列 — SACK和DSACK的实现（二）


和18版本相比，37版本的SACK和DSACK的实现做了很多改进，最明显的就是需要遍历的次数少了，  
减少了CPU的消耗。37版的性能提升了，代码有大幅度的改动，逻辑也更加复杂了。

本文主要内容：37版tcp_sacktag_write_queue()的实现，也即37版SACK和DSACK的实现。
```
	/* This defines a selective acknowledgement block. */
	struct tcp_sack_block_wire {
		__be32 start_seq;
		__be32 end_seq;
	};

	/* 这就是一个SACK块 */
	struct tcp_sack_block {
		u32 start_seq;   /* 起始序号 */
		u32 end_seq;     /* 结束序号 */
	};

	/* 用于处理SACK块时保存一些信息 */
	struct tcp_sacktag_state {
		int reord;       /* 乱序的位置 */
		int fack_count;  /* 累加fackets_out */ // fack_count只是单纯的累加write_queue的packets_out
		int flag;        /* 返回标志 */
	};
```

```
	struct tcp_sock {
		...
		/* Options received (usually on last packet, some only on SYN packets). */
		struct tcp_options_received rx_opt;
		...
		/* SACKs data, these 2 need to be together (see tcp_build_and_update_options)
		 * 收到乱序包时填入信息，用于回复
		 */
		struct tcp_sack_block duplicate_sack[1]; /* D-SACK block */
		struct tcp_sack_block selective_acks[4]; /* The SACKS themselves */

		struct tcp_sack_block recv_sack_cache[4]; /* 保存收到的SACK块，用于提高效率*/
		struct sk_buff *highest_sack; /* highest skb with SACK received
									   * (validity guaranteed only if sacked_out > 0) */
		...
	};
```

```
	struct tcp_options_received {
		...
		u16 saw_tstamp : 1,    /* Saw TIMESTAMP on last packet */
				tstamp_ok : 1, /* TIMESTAMP seen on SYN packet */
				dsack : 1,     /* D-SACK is scheduled, 下一个发送段是否存在D-SACK */
				sack_ok : 4,   /* SACK seen on SYN packet, 接收方是否支持SACK */
				...
		u8 num_sacks;          /* Number of SACK blocks, 下一个发送段中SACK块数 */
		...
	};
```

#### 37版本实现
37版本做了一些改进，主要是为了提升效率，减少重复工作。
```
	static int tcp_sacktag_write_queue (struct sock *sk, const struct sk_buff *ack_skb, u32 prior_snd_una)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);

		/* SACK选项的起始地址，sacked为SACK选项在TCP首部的偏移 */
		const unsigned char *ptr = (skb_transport_header(ack_skb) + TCP_SKB_CB(ack_skb)->sacked);

		struct tcp_sack_block_wire *sp_wire = (struct tcp_sack_block_wire *) (ptr + 2); /* 指向第一个sack块 */
		struct tcp_sack_block sp[TCP_NUM_SACKS];
		struct tcp_sack_block *cache;
		struct tcp_sacktag_state state;
		struct sk_buff *skb;
		int num_sacks = min(TCP_NUM_SACKS, (ptr[1] - TCPOLEN_SACK_BASE) >> 3); /* sack的块数 */
		int used_sacks;
		int found_dup_sack = 0;
		int i, j;
		int first_sack_index;

		state.flag = 0;
		state.reord = tp->packets_out;   /* 乱序的起始位置一开始设为最大 */

		/* 如果之前没有SACKed的数据 */
		if (! tp->sacked_out) {
			if (WARN_ON(tp->fackets_out))
				tp->fackets_out = 0;     /* FACK是根据最新的SACK来计算的，也要为0 */
			tcp_highest_sack_reset(sk);  /* tp->highest_sack置为发送队列的第一个数据包，因为没有SACK块 */
		}

		/* 检查第一个SACK块是否为DSACK */
		found_dup_sack = tcp_check_dsack(sk, ack_skb, sp_wire, num_sacks, prior_snd_una);
		if (found_dup_sack)
			state.flag |= FLAG_DSACKING_ACK; /* SACK blocks contained D-SACK info */

		/* Eliminate too old ACKs, but take into account more or less fresh ones,
		 * they can contain valid SACK info.
		 * tp->max_window为接收方通告过的最大接收窗口。
		 * 如果SACK信息是很早以前的，直接丢弃。
		 */
		if (before(TCP_SKB_CB(ack_skb)->ack_seq, prior_snd_una - tp->max_window))
			return 0;

		if (! tp->packets_out) /* 如果我们并没有发送数据到网络中，错误 */
			goto out;

		used_sacks = 0;
		first_sack_index = 0;

		/* 进行SACK块的合法性检查，并确定要使用哪些SACK块 */
		for (i = 0; i < num_sacks; i++) {
			int dup_sack = ! i && found_dup_sack; /* 是否为DSACK块，DSACK块只能是第一个块 */

			sp[used_sacks].start_seq = get_unaligned_be32(&sp_wire[i].start_seq);
			sp[used_sacks].end_seq = get_unaligned_be32(&sp_wire[i].end_seq);

			/* 检查这个SACK块是否为合法的 */
			if (! tcp_is_sackblock_valid(tp, dup_sack, sp[used_sacks].start_seq,
					 sp[used_sacks].end_seq)) {

				/* 不合法的话进行处理 */
				int mib_idx;

				if (dup_sack) { /* 如果是DSACK块 */
					if (! tp->undo_marker) /* 之前没有进入Recovery或Loss状态 */
						mib_idx = LINUX_MIB_TCPDSACKINGOREDNOUNDO; /* TCPSACKIgnoredNoUndo */
					else
						mib_idx = LINUX_MIB_TCPDSACKINGNOREDOLD; /* TCPSACKIgnoredOld */

				} else { /* 不是DSACK块 */
					/* Don't count olds caused by ACK reordering，不处理ACK乱序 */
					if ((TCP_SKB_CB(ack_skb)->ack_seq != tp->snd_una) &&
						! after(sp[used_sacks].end_seq, tp->snd_una))
						continue;
					mib_idx = LINUX_MIB_TCPSACKDISCARD;
				}

				NET_INC_STATS_BH(sock_net(sk), mib_idx);

				if (i == 0)
					first_sack_index = -1; /* 表示第一个块无效 */

				continue;
			}

			/* Ignore very old stuff early，忽略已确认过的块 */
			if (! after(sp[used_sacks].end_seq, prior_snd_una))
				continue;

			used_sacks++; /* 实际要使用的SACK块数，忽略不合法和已确认过的 */
		}

		/* order SACK blocks to allow in order walk of the retrans queue.
		 * 对实际使用的SACK块，按起始序列号，从小到大进行冒泡排序。
		 */
		for (i = used_sacks - 1; i > 0; i--) {
			for (j = 0; j < i; j++) {
				if (after(sp[j].start_seq, sp[j+1].start_seq)) {
					swap(sp[j], sp[j+1]); /* 交换SACK块 */

					/* Track where the first SACK block goes to，跟踪第一个SACK块 */
					if (j == first_sack_index)
						first_sack_index = j + 1;
				}
			}
		}

		skb = tcp_write_queue_head(sk); /* 发送队列的第一个包 */
		state.fack_count = 0;
		i = 0;

		/* 接下来使cache指向之前的SACK块，即recv_sack_cache */
		if (! tp->sacked_out) {  /* 如果之前没有SACK块 */
			/* It's already past, so skip checking against it.
			 * cache指向recv_sack_cache数组的末尾
			 */
			cache = tp->recv_sack_cache + ARRAY_SIZE(tp->recv_sack_cache);

		} else {
			cache = tp->recv_sack_cache;
			/* Skip empty blocks in at head of the cache. 跳过空的块 */
			while(tcp_sack_cache_ok(tp, cache) && ! cache->start_seq && ! cache->end_seq)
				cache++;
		}

		/* 遍历实际用到的SACK块 */
		while (i < used_sacks) {
			u32 start_seq = sp[i].start_seq;
			u32 end_seq = sp[i].end_seq;
			int dup_sack = (found_dup_sack && (i == first_sack_index)); /* 这个SACK块是否为DSACK块 */
			struct tcp_sack_block *next_dup = NULL;

			/* 如果下一个SACK块是DSACK块，则next_dup指向DSACK块 */
			if (found_dup_sack && ((i + 1) == first_sack_index))
				next_dup = &sp[i + 1];

			/* Event B in the comment above.
			 * high_seq是进入Recovery或Loss时的snd_nxt，如果high_seq被SACK了，那么很可能有数据包
			 * 丢失了，不然就可以ACK掉high_seq返回Open态了。
			 */
			if (after(end_seq, tp->high_seq))
				state.flag |= FLAG_DATA_LOST;

			/* Skip too early cached blocks.
			 * 如果cache块的end_seq < SACK块的start_seq，那说明cache块在当前块之前，不用管它了。
			 */
			while (tcp_sack_cache_ok(tp, cache) && ! before(start_seq, cache->end_seq))
				cache++;

			/* Can skip some work by looking recv_sack_cache?
			 * 查看当前SACK块和cache块有无交集，避免重复工作。
			 * 前一个包的sack块(cache块)只是为了加快处理这个包的sack块
			 */
			if (tcp_sack_cache_ok(tp, cache) && ! dup_sack &&
				after(end_seq, cache->start_seq)) {

				/* Head todo? 处理start_seq到cache->start_seq之间的段 */
				if (before(start_seq, cache->start_seq)) {
					/* 找到start_seq对应的数据段 */
					skb = tcp_sacktag_skip(skb, sk, &state, start_seq);
					/* 遍历start_seq到cache->start_seq之间的段，为其间的skb更新记分牌 */
					skb = tcp_sacktag_walk(skb, sk, next_dup, &state, start_seq, cache->start_seq, dup_sack);
				}

				/* Rest of the block already fully processed?
				 * 如果此块剩下的部分都包含在cache块中，那么就不用再处理了。
				 */
				if (! after(end_seq, cache->end_seq))
					goto advance_sp;

				/* 如果cache->start_seq < next_dup->start_seq < cache->end_seq，那么处理next_dup。
				 * 注意，如果start_seq < next_dup->start_seq < cache->start_seq，那么next_dup落在
				 * (start_seq, cache->start_seq) 内的部分已经被上面的处理过了：）现在处理的next_dup的剩余部分。
				 */
				skb = tcp_maybe_skipping_dsack(skb, sk, next_dup, &state, cache->end_seq);

				/* 处理(cache->end_seq, end_seq) ...tail remains todo... */
				if (tcp_highest_sack_seq(tp) == cache->end_seq) {
					skb = tcp_highest_sack(sk);
					/* 如果已经到了snd_nxt了，那么直接退出SACK块的遍历 */
					if (skb == NULL)
						break;
					state.fack_count = tp->fackets_out; // fack_count只是单纯的累加write_queue的packets_out
					cache++; /* 此cache已经用完了 */
					goto walk; /* 继续SACK块还没处理完的部分 */
				}

				/* 找到end_seq > cache->end_seq的skb */
				 skb = tcp_sacktag_skip(skb, sk, &state, cache->end_seq);

				/* Check overlap against next cached too (past this one already) */
				cache++;

				continue;
			}

			/* 这个块没有和cache块重叠，是新的 */
			if (! before(start_seq, tcp_highest_sack_seq(tp))) {
				skb = tcp_highest_sack(sk);
				if (skb == NULL)
					break;
				state.fack_count = tp->fackets_out; // fack_count只是单纯的累加write_queue的packets_out
			}

			skb = tcp_sacktag_skip(skb, sk, &state, start_seq); /* skb跳到start_seq处，下面会walk遍历此块 */

	walk:
			/* 从skb开始遍历，标志块间的包 */
			skb = tcp_sacktag_walk(skb, sk, next_dup, &state, start_seq, end_seq, dup_sack);

	advance_sp:
			/* SACK enhanced FRTO (RFC4138, Appendix B): Clearing correct due to
			 * in-order walk.
			 */
			if (after(end_seq, tp->frto_highmark))
				state.flag &= ~FLAG_ONLY_ORIG_SACKED; /* 清除这个标志 */

			i++; /* 接下来处理下一个SACK块 */
		}

		/* Clear the head of the cache sack blocks so we can skip it next time.
		 * 两个循环用于清除旧的SACK块，保存新的SACK块。保存前一个包的sack块只是为了加快处理下一个包的sack块
		 */
		for (i = 0; i < ARRAY_SIZE(tp->recv_sack_cache) - used_sacks; i++) {
			tp->recv_sack_cache[i].start_seq = 0;
			tp->recv_sack_cache[i].end_seq = 0;
		}

		for (j = 0; j < used_sacks; j++)
			tp->recv_sack_cache[i++] = sp[j];

		/* 检查重传包是否丢失，这部分独立出来 */
		tcp_mark_lost_retrans(sk);

		tcp_verify_left_out(tp);

		if ((state.reord < tp->fackets_out) && ((icsk->icsk_ca_state != TCP_CA_Loss) || tp->undo_marker) &&
			(! tp->frto_highmark || after(tp->snd_una, tp->frto_highmark)))
			tcp_update_reordering(sk, tp->fackets_out - state.reord, 0); /* 更新乱序长度 */

	out:
	#if FASTRETRANS_DEBUG > 0
		WARN_ON((int) tp->sacked_out < 0);
		WARN_ON((int) tp->lost_out < 0);
		WARN_ON((int) tp->retrans_out < 0);
		WARN_ON((int) tcp_packets_in_flight(tp) < 0);
	#endif

		return state.flag;
	}
```

```
	/*
	 * swap - swap value of @a and @b
	 */
	#define swap(a, b) \
		do { typeof(a) __tmp = (a); (a) = (b); (b) = __tmp; } while (0)

	static int tcp_sack_cache_ok(struct tcp_sock *tp, struct tcp_sack_block *cache)
	{
		return cache < tp->recv_sack_cache + ARRAY_SIZE(tp->recv_sack_cache);
	}

	/* 被SACK过的包的最大初始序列号
	 * Start sequence of the highest skb with SACKed bit, valid only if sacked > 0
	 * or when the caller has ensured validity by itself.
	 */
	static inline u32 tcp_highest_sack_seq(struct tcp_sock *tp)
	{
		if (! tp->sacked_out)  /* 没有包被SACK过，则设置成snd_una */
			return tp->snd_una;

		if (tp->highest_sack == NULL) /* 已经是发送队列的最后一个包了 */
			return tp->snd_nxt;

		return TCP_SKB_CB(tp->highest_sack)->seq;
	}

	static inline void tcp_advance_highest_sack(struct sock *sk, struct sk_buff *skb)
	{
		tcp_sk(sk)->highest_sack = tcp_skb_is_last(sk, skb) ? NULL : tcp_write_queue_next(sk, skb);
	}
```

#### 使用cache
37版本利用上次缓存的tp->recv_sack_cache块来避免重复工作，提高处理效率。  
主要思想就是，处理sack块时，和cache块作比较，如果它们有交集，说明交集部分已经处理过了，  
不用再重复处理。

##### （1）忽略cache块
如果cache块完全在sack块的前面，即cache->end_seq < start_seq，那么忽略此cache块。

##### （2）没有交集
如果sack块完全在cache块前面，即end_seq < cache->start_seq，那么跳到walk处理，不考虑cache块。

##### （3）有交集
case 1： end_seq<=cache->end_seq，只需处理(start_seq, cache->start_seq)这部分，交集不必处理。处理完后直接跳到advance_sp。  
case 2： start_seq>=cache->start_seq，只需处理(cache->end_seq, end_seq)这部分，交集不必处理。先skip到cache->end_seq，cache++，再continue。  
case 3： sack块完全包含在cache块中，那么什么都不用做，直接跳到advance_sp，处理下一个sack块。  
case 4： cache块完全包含在sack块中，这时候需要处理两部分：(start_seq, cache->start_seq)，(cache->end_seq, end_seq)。  

-------------

### TCP的核心系列 — SACK和DSACK的实现（三）


不论是18版，还是37版，一开始都会从TCP的控制块中取出SACK选项的起始地址。  
SACK选项的起始地址是保存在tcp_skb_cb结构的sacked项中的，那么这是在什么时候做的呢？  
SACK块并不是总是合法的，非法的SACK块可能会引起处理错误，所以还需要进行SACK块的合法性检查。

本文主要内容：TCP首部中SACK选项的解析和地址的获取，SACK块的合法性检查。

#### SACK选项的地址
TCP_SKB_CB(skb)->sacked is initialized to offset corresponding to the start of the SACK option in the  
TCP header for the segment received.

处理时机为：
```
	tcp_rcv_established()，进入慢速路径时调用
		| --> tcp_validate_incoming()
				| --> tcp_fast_parse_options()
						| --> tcp_parse_options()
```

在慢速路径中，有可能只带有TIMESTAMP选项，因此先用tcp_fast_parse_options()快速解析。

```
	/* Fast parse options. This hopes to only see timestamps.
	 * If it is wrong it falls back on tcp_parse_options().
	 */
	static int tcp_fast_parse_options(struct sk_buff *skb, struct tcphdr *th, struct tcp_sock *tp, u8 **hvpp)
	{
		/* In the spirit of fast parsing, compare doff directly to constant values.
		 * Because equality is used, short doff can be ignored here.
		 */
		if (th->doff == (sizeof(*th) / 4)) { /* 没有带选项 */
			tp->rx_opt.saw_tstamp = 0;
			return 0;

		} else if (tp->rx_opt.tstamp_ok &&
			th->doff == ((sizeof(*th) + TCPOLEN_TSTAMP_ALIGNED) / 4)) { /* 只带有时间戳选项 */
			if (tcp_parse_aligned_timestamp(tp, th))
				return 1;
		}

		/* 如果以上的快速解析失败，则进行全面解析 */
		tcp_parse_options(skb, &tp->rx_opt, hvpp, 1);

		return 1;
	}
```

```
	static int tcp_parse_aligned_timestamp(struct tcp_sock *tp, struct tcphdr *th)
	{
		__be32 *ptr = (__be32 *) (th + 1); /* 指向选项部分 */

		/* 如果选项部分的前4个字节分别为：0x 01 01 08 0A */
		if (*ptr == htonl((TCPOPT_NOP << 24) | (TCPOPT_NOP << 16)
			 | (TCPOPT_TIMESTAMP << 8) | TCPOLEN_TIMESTAMP)) {

			tp->rx_opt.saw_tstamp = 1;
			++ptr;

			tp->rx_opt.rcv_tsval = ntohl(*ptr); /* 提取接收包的时间戳*/
			++ptr;

			tp->rx_opt.rcv_tsecr = ntohl(*ptr); /* 提取接收包的回显值*/
			return 1;
		}

		return 0;
	}
```

在慢速路径中，如果tcp_fast_parse_options()失败，则调用tcp_parse_options()全面解析TCP选项。
```
	/* Look for tcp options. Normally only called on SYN and SYNACK packets.
	 * But, this can also be called on packets in the established flow when the fast version
	 * below fails.
	 */
	void tcp_parse_options(struct sk_buff *skb, struct tcp_options_received *opt_rx, u8 **hvpp, int estab)
	{
		unsigned char *ptr;
		struct tcphdr *th = tcp_hdr(skb);
		int length = (th->doff * 4) - sizeof(struct tcphdr); /* 选项总长度 */

		ptr = (unsigned char *) (th + 1);                    /* 选项起始地址 */
		opt_rx->saw_tstamp = 0;                              /* 此ACK有没有带时间戳接下来才知道 */

		while (length > 0) {
			int opcode = *ptr++;     /* 选项kind */
			int opsize;

			switch (opcode) {
				case TCPOPT_EOL:     /* 结束选项，不常见到 */
					return;

				case TCPOPT_NOP:     /* 填充选项 */
					length--;        /* 此选项只占一个字节 */
					continue;

				default:
					opsize = *ptr++; /* 此选项长度 */

					if (opsize < 2)  /* "silly options" */
						return;      /* 选项长度过小 */

					if (opsize > length)
						return;      /* don't parse partial options */

					switch (opcode) {
						...
						case TCPOPT_SACK_PERM:
							if (opsize == TCPOLEN_SACK_PERM && th->syn &&
								 !estab && sysctl_tcp_sack) {

								opt_rx->sack_ok = 1;    /* SYN包中显示支持SACK */
								tcp_sack_reset(opt_rx); /* 清空dsack和num_sacks */
							}
							break;

							case TCPOPT_SACK:
								if ((opsize >= (TCPOLEN_SACK_BASE + TCPOLEN_SACK_PERBLOCK)) &&
								   !((opsize - TCPOLEN_SACK_BASE) % TCPOLEN_SACK_PERBLOCK) &&
								   opt_rx->sack_ok) {

									/*保存SACK选项的起始地址偏移*/
									TCP_SKB_CB(skb)->sacked = (ptr - 2) - (unsigned char *) th;
								}
								break;
							...
					}
			}
		}
	}
```

```
	/* TCP options */
	#define TCPOPT_NOP 1 /* Padding */
	#define TCPOPT_EOL 0 /* End of options */
	#define TCPOPT_MSS 2 /* Segment size negotiating */
	#define TCPOPT_WINDOW 3 /* Window Scaling */
	#define TCPOPT_SACK_PERM 4 /* SACK Permitted */
	#define TCPOPT_SACK 5 /* SACK Block */
	#define TCPOPT_TIMESTAMP 8 /* Better RTT estimations/PAWS */

	static inline void tcp_sack_reset(struct tcp_options_received *rx_opt)
	{
		rx_opt->dsack = 0;
		rx_opt->num_sacks = 0;
	}

	/* This is the max number of SACKS that we'll generate and process.
	 * It's safe to increase this, although since:
	 * size = TCPOLEN_SACK_BASE_ALIGNED(4) + n * TCPOLEN_SACK_PERBLOCK(8)
	 * only four options will fit in a standard TCP header
	 */
	#define TCP_NUM_SACKS 4 /* SACK块数最多为4 */
```

#### SACK块合法性检查
检查SACK块或者DSACK块是否合法。  
2.6.24之前的版本没有检查SACK块的合法性，而某些非法的SACK块可能会触发空指针的引用。  
在3.1版本之前有一个小bug，处理DSACK时会产生问题，修复非常简单：  
@if (! after(end_seq, tp->snd_una))，把非去掉。

符合以下任一条件的SACK块是合法的：  
1. sack块和dsack块：snd_una < start_seq < end_seq <= snd_nxt  
2. dsack块：undo_marker <= start_seq < end_seq <= snd_una  
3. dsack块：start_seq < undo_marker < end_seq <= snd_una 且 end_seq - start_seq <= max_window  

```
	/* SACK block range validation checks that the received SACK block fits to the
	 * expected sequence limits, i.e., it is between SND.UNA and SND.NXT.
	 */
	static int tcp_is_sackblock_valid(struct tcp_sock *tp, int is_dsack, u32 start_seq, u32 end_seq)
	{
		/* Too far in future, or reversed (interpretation is ambiguous)
		 * end_seq超过了snd_nxt，或者start_seq >= end_seq，那么不合法
		 */
		if (after(end_seq, tp->snd_nxt) || ! before(start_seq, end_seq))
			return 0;

		/* Nasty start_seq wrap-around check (see comments above) */
		 * start_seq超过了snd_nxt
		 */
		if (! before(start_seq, tp->snd_nxt))
			return 0;

		/* In outstanding window? This is valid exit for D-SACKs too.
		 * start_seq == snd_una is non-sensical (see comments above)
		 */
		if (after(start_seq, tp->snd_una))
			return 1; /* 合法 */

		if (! is_dsack || ! tp->undo_marker)
			return 0;

		/* Then it's D-SACK, and must reside below snd_una completely.
		 * 注意在3.1以前这里是：! after(end_seq, tp->snd_una)，是一个bug
		 */
		if (after(end_seq, tp->snd_una))
			return 0;

		if (! before(start_seq, tp->undo_marker))
			return 1; /* dsack块合法 */

		/* Too old，DSACK块太旧了*/
		if (! after(end_seq, tp->undo_marker))
			return 0;

		/* Undo_marker boundary crossing */
		return !before(start_seq, end_seq - tp->max_window);
	}
```

------------------

### TCP的核心系列 — SACK和DSACK的实现（四）


和18版本不同，37版本把DSACK的检测部分独立出来，可读性更好。  
37版本在DSACK的处理中也做了一些优化，对DSACK的两种情况分别进行处理。

本文主要内容：DSACK的检测、DSACK的处理。

#### dsack检测
根据RFC 2883，DSACK的处理流程如下：  
1）look at the first SACK block :  
—If the first SACK block is covered by the Cumulative Acknowledgement field, then it is a D-SACK block, and is reporting duplicate data.  
—Else, if the first SACK block is covered by the second SACK block, then the first SACK block is a D-SACK block, and is reporting duplicate data.
2）otherwise, interpret the SACK blocks using the normal SACK procedures.  

简单来说，符合以下任一情况的，就是DSACK：  
1）第一个SACK块的起始序号小于它的确认序号，说明此SACK块包含了确认过的数据。  
2）第一个SACK块包含在第二个SACK块中，说明第一个SACK块是重复的。  

```
	static int tcp_check_dsack(struct sock *sk, struct sk_buff *ack_skb,
			struct tcp_sack_block_wire *sp, int num_sacks, u32 prior_snd_una)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		u32 start_seq_0 = get_unaligned_be32(&sp[0].start_seq); /* 第一个SACK块的起始 */
		u32 end_seq_0 = get_unaligned_be32(&sp[0].end_seq);     /* 第一个SACK块的结束 */
		int dup_sack = 0;                                       /* 是否有DSACK */

		/* 如果第一个SACK块的起始序号小于它的确认序号，说明此SACK块包含了确认过的数据，
		 * 所以第一个SACK块是DSACK。
		 */
		if (before(start_seq_0, TCP_SKB_CB(ack_skb)->ack_seq)) {
			dup_sack = 1;
			tcp_dsack_seen(tp);
			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPDSACKRECV);

		} else if (num_sacks > 1) {
			u32 end_seq_1 = get_unaligned_be32(&sp[1].end_seq);     /* 第二个块的结束序号 */
			u32 start_seq_1 = get_unaligned_be32(&sp[1].start_seq); /* 第二个块的起始序号 */

			/* 如果第一个SACK块包含在第二个SACK块中，说明第一个SACK块是重复的，即为DSACK */
			if (! after(end_seq_0, end_seq_1) && ! before(start_seq_0, start_seq_1)) {
				dup_sack = 1;
				tcp_dsack_seen(tp);
				NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPDSACKOFORECV);
			}
		}

		/* D-SACK for already forgotten data... Do dumb counting.
		 * undo_retrans记录重传数据包的个数，如果undo_retrans降到0，
		 * 就说明之前的重传都是不必要的，进行拥塞调整撤销。
		 */
		if (dup_sack && ! after(end_seq_0, prior_snd_una) &&
			after(end_seq_0, tp->undo_marker))
			tp->undo_retrans--;

		return dup_sack;
	}
```

```
	/* Take a notice that peer is sending D-SACKs */
	static void tcp_dsack_seen(struct tcp_sock *tp)
	{
		tp->rx_opt.sack_ok |= 4;
	}
```

在以上函数中，undo_marker为进入Recovery或FRTO状态时记录的snd_una，prior_snd_una为根据该ACK更新窗口前的snd_una。如果回复的DSACK在这块中间，说明是超时重传或FRTO后进行的重传，因此需要减少undo_retrans。当undo_retrans减小到0，说明之前的重传都是不必要的，网络并没有拥塞，因此要进行拥塞调整撤销。

#### dsack处理
当处理一个块时，会检查下一个块是不是DSACK块，如果是则用next_dup指向该DSACK块。  
为什么在处理当前SACK块的时候，还要考虑到下个DSACK块呢？  
我们知道DSACK有两种情况，一种是DSACK块小于snd_una，另一种情况是DSACK块大于snd_una且包含在第一个块中，我们来分别分析下。

（1）DSACK块大于snd_una且包含在第一个SACK块中
两个块需要同时处理。不然等SACK块处理完后，再处理DSACK块，就需要做一些重复的工作。

当DSACK包含在第一个SACK块中，那么处理DSACK块在cache中的部分。
```
	static struct sk_buff *tcp_maybe_skipping_dsack(struct sk_buff *skb, struct sock *sk,
													struct tcp_sack_block *next_dup,
													struct tcp_sacktag_state *state,
													u32 skip_to_seq)
	{
		/* 如果下个SACK块不是DSACK块，那么不用进行dsack处理 */
		if (next_dup == NULL)
			return skb;

		/* 如果在(cache->start_seq, cache->end_seq)中包含dsack */
		if (before(next_dup->start_seq, skip_to_seq)) {

			/* 找到next_dup->start_seq之后的skb */
			skb = tcp_sacktag_skip(skb, sk, state, next_dup->start_seq);

			/* 处理next_dup->start_seq之后的skb */
			skb = tcp_sacktag_walk(skb, sk, NULL, state, next_dup->start_seq, next_dup->end_seq, 1);
		}
	}
```

（2）DSACK块小于snd_una
这时候DSACK排序后也是第一个块，会被直接处理，next_dup在这里就没有意义了。  
DSACK的两种情况都在tcp_sacktag_walk()中处理，第一种时next_dup不为空、dup_sack_in为0；第二种时next_dup为空，dup_sack_in为1。

##### Reference
RFC 2883

-------------

### TCP的核心系列 — SACK和DSACK的实现（五）


18版本对于每个SACK块，都是从重传队列头开始遍历。37版本则可以选择性的遍历重传队列的某一部分，忽略SACK块间的间隙、或者已经cache过的部分。这主要是通过tcp_sacktag_skip()和tcp_sacktag_walk()完成的。  
tcp_sacktag_skip()可以直接找到包含某个序号的skb，通常用于定位SACK块的开头。  
tcp_sacktag_walk()则遍历两个序号之间的skb，通常用于遍历一个SACK块。  

本文主要内容：SACK的遍历函数tcp_sacktag_skip()和tcp_sacktag_walk()。

#### tcp_sacktag_skip
从当前skb开始遍历，查找skip_to_seq序号对应的skb，同时统计fackets_out。  
这样可以从当前包，直接遍历到某个块的start_seq，而不用从头开始遍历，也可以跳过块间的间隙。  
```
	/* Avoid all extra work that is being done by sacktag while walking in a normal way */
	static struct sk_buff *tcp_sacktag_skip(struct sk_buff *skb, struct sock *sk,
								   struct tcp_sacktag_state *state, u32 skip_to_seq)
	{
		tcp_for_write_queue_from(skb, sk) {
			if (skb == tcp_send_head(sk))                     /* 到了发送队列头，即下一个将要发送的数据包 */
				break;

			if (after(TCP_SKB_CB(skb)->end_seq, skip_to_seq)) /* 找到包含skip_to_seq序号的数据包了 */
				break;

			state->fack_count += tcp_skb_pcount(skb);         /* 统计fackets_out个数 */ // fack_count只是单纯的累加write_queue的packets_out
		}

		return skb; /* 返回包含skip_to_seq的skb */
	}
```

#### tcp_sacktag_walk
遍历一个SACK块，如果SACK块包含了多个连续的skb，那么先尝试合并这些段。  
为什么要合并呢？因为下次遍历的时候，要遍历的包个数就减少了，能提高效率。  
如果skb完全包含在块中，则调用tcp_sacktag_one更新该段的记分牌。  

```
	static struct sk_buff *tcp_sacktag_walk(struct sk_buff *skb, struct sock *sk,
											struct tcp_sack_block *next_dup,
											struct tcp_sacktag_state *state,
											u32 start_seq, u32 end_seq,
											int dup_sack_in)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *tmp;

		tcp_for_write_queue_from(skb, sk) {
			int in_sack = 0;
			int dup_sack = dup_sack_in;

			if (skb == tcp_send_head(sk))                /* 遍历到发送队列头了 */
				break;

			if (! before(TCP_SKB_CB(skb)->seq, end_seq)) /* skb序号超过SACK块了 */
				break;

			/* 如果下一个块是DSACK，且此skb可能包含在其中 */
			if ((next_dup != NULL) &&
				before(TCP_SKB_CB(skb)->seq, next_dup->end_seq)) {

				/* 此skb是否完全包含在DSACK块中 */
				in_sack = tcp_match_skb_to_sack(sk, skb, next_dup->start_seq, next_dup->end_seq);

				if (in_sack > 0)
					dup_sack = 1;           /* 表示这个skb被DSACK */
			}

			if (in_sack <= 0) {
				/* 一个SACK块可能包括多个skb，尝试把这些连续的skb合并 */
				tmp = tcp_shift_skb_data(sk, skb, state, start_seq, end_seq, dup_sack);

				if (tmp != NULL) {          /* 合并成功 */
					if (tmp != skb) {       /* tmp和当前段地址不同，则跳到合并后的段处理 */
						skb = tmp;
						continue;
					}
					in_sack = 0;

				} else {                    /* 合并不成功，单独处理这个段 */
					in_sack = tcp_match_skb_to_sack(sk, skb, start_seq, end_seq); /* 段是否完全包含在块中 */
				}
			}

			if (unlikely(in_sack < 0))
				break;

			/* 如果这个段完全包含在块中，进行处理 */
			if (in_sack) {

				/* 就是在这里：标志这个段的记分牌！*/
				TCP_SKB_CB(skb)->sacked = tcp_sacktag_one(skb, sk, state, dup_sack, tcp_skb_pcount(skb));

				/* 如果当前skb的开始序列号大于被SACK的包的最高初始序列号 */
				if (! before(TCP_SKB_CB(skb)->seq, tcp_highest_sack_seq(tp)))
					tcp_advance_highest_sack(sk, skb); /*把highest_sack设为skb->next */
			}

			state->fack_count += tcp_skb_pcount(skb); /* 更新fackets_out */ // fack_count只是单纯的累加write_queue的packets_out
		}

		return skb; /* 遍历到此skb退出 */
	}
```

##### tcp_match_skb_to_sack()
用于检查一个数据段是否完全包含在一个SACK块中，主要考虑到GSO分段。
```
	/* Check if skb is fully within the SACK block.
	 * In presence of GSO skbs, the incoming SACK may not exactly match but we can find smaller MSS
	 * aligned portion of it that matches. Therefore we might need to fragment which may fail and creates
	 * some hassle (caller must handle error case returns).
	 * FIXME: this could be merged to shift decision code
	 */
	static int tcp_match_skb_to_sack(struct sock *sk, struct sk_buff *skb, u32 start_seq, u32 end_seq)
	{
		int in_sack, err;
		unsigned int pkt_len;
		unsigned int mss;

		/* 如果start_seq <= skb->seq < skb->end_seq <= end_seq，说明skb完全包含在SACK块中 */
		in_sack = ! after(start_seq, TCP_SKB_CB(skb)->seq) &&
						   ! before(end_seq, TCP_SKB_CB(skb)->end_seq);

		/* 如果有GSO分段，skb可能部分包含在块中 */
		if (tcp_skb_pcount(skb) > 1 && ! in_sack &&
			after(TCP_SKB_CB(skb)->end_seq, start_seq)) {

			mss = tcp_skb_mss(skb);
			in_sack = ! after(start_seq, TCP_SKB_CB(skb)->seq); /* 前半部在块中 */

			/* 这里根据skb->seq和start_seq的大小，分情况处理 */
			if (! in_sack) {         /* 后半部在块中 */
				pkt_len = start_seq - TCP_SKB_CB(skb)->seq; /* skb在块之前的部分 */
				if (pkt_len < mss)
					pkt_len = mss;

			} else {
				pkt_len = end_seq - TCP_SKB_CB(skb)->seq;   /* skb在块内的部分 */
				if (pkt_len < mss)
					return -EINVAL;
			}

			/* Round if necessary so that SACKs cover only full MSSes and/or the remaining
			 * small portion (if present)
			 */
			if (pkt_len > mss) {
				unsigned int new_len = (pkt_len / mss) * mss;
				if (! in_sack && new_len < pkt_len) {
					new_len += mss;
					if (new_len > skb->len)
						return 0;
				}
				pkt_len = new_len;
			}

			err = tcp_fragment(sk, skb, pkt_len, mss); /* 把skb分为两个包，SACK块内的和SACK块外的 */
		}

		return in_sack;
	}
```

##### tcp_shift_skb_data()
尝试把SACK块内的多个包合成一个，可以提升遍历效率。  
一个SACK块可能包括多个skb，尝试把这些连续的skb合成一个。  
```
	/* Try to collapsing SACK blocks spanning across multiple skbs to a single skb. */
	static struct sk_buff *tcp_shift_skb_data(struct sock *sk, struct sk_buff *skb,
											  struct tcp_sacktag_state *state,
											  u32 start_seq, u32 end_seq, int dup_sack)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *prev;
		int mss;
		int pcount = 0;
		int len;
		int in_sack;

		if (! sk_can_gso(sk))
			goto fallback;

		...

	fallback:
		NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_SACKSHIFTFALLBACK);
		return NULL;
	}
```

-----------------

### TCP的核心系列 — SACK和DSACK的实现（六）


上篇文章中我们主要说明如何skip到一个SACK块对应的开始段，如何walk这个SACK块包含的段，而没有涉及到
如何标志一个段的记分牌。37版本把给一个段打标志的内容独立出来，这就是tcp_sacktag_one()。  

本文主要内容：tcp_sacktag_one()，给一个段打上标志。

#### 标志一个包
tcp_sacktag_walk()用于遍历块中的数据包，最终会调用tcp_sacktag_one()来标志一个数据包的记分牌，

即TCP_SKB_CB(skb)->sacked。

记分牌有哪些标志呢？
```
	#define TCPCB_SACKED_ACKED 0x01     /* SKB ACK'd by a SACK block， 标志S */
	#define TCPCB_SACKED_RETRANS 0x02   /* SKB retransmitted，标志R */
	#define TCPCB_LOST 0x04             /* SKB is lot，标志L */
	#define TCPCB_TAGBITS 0x07          /* All tag bits，标志位掩码 */
	#define TCPCB_EVER_RETRANS 0x08     /* Ever retransmitted frame，曾经重传过 */
	#define TCPCB_RETRANS (TCPCB_SACKED_RETRANS | TCPCB_EVER_RETRANS)
```

以上标志的说明如下：  
We have three tag bits: SACKED(S)、RETRANS(R) and LOST(L).  
Packets in queue with these bits set are counted in variables sacked_out、retrans_out and lost_out.

tag标志可能的6种情况：  
```
Tag        InFlight             Description
0             1            orig segment is in flight，正常情况
S             0            nothing flies, orig reached receiver.
L             0            nothing flies, orig lost by net.
R             2            both orig and retransmit is in flight.
L|R           1            orig is lost, retransmit is in flight.
S|R           1            orig reached receiver, retrans is still in flight.
```
L|S|R is logically valid, it could occur when L|R is sacked, but it is equivalent to plain S and code short-curcuits it to S.  
L|S is logically invalid, it would mean -1 packet in flight.

以上6种情况是由以下事件触发的：  
These 6 states form finite state machine, controlled by the following events:
```
1. New ACK (+SACK) arrives. (tcp_sacktag_write_queue())
2. Retransmission. (tcp_retransmit_skb(), tcp_xmit_retransmit_queue())
3. Loss detection event of one of three flavors:
	A. Scoreboard estimator decided the packet is lost.
		A'. Reno "three dupacks" marks head of queue lost.
		A''. Its FACK modification, head until snd.fack is lost.
	B. SACK arrives sacking data retransmitted after never retransmitted hole was sent out.
	C. SACK arrives sacking SND.NXT at the moment, when the segment was retransmitted.
4. D-SACK added new rule: D-SACK changes any tag to S. 
```

```
	static u8 tcp_sacktag_one(struct sk_buff *skb, struct sock *sk,
							  struct tcp_sacktag_state *state, int dup_sack, int pcount)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		u8 sacked = TCP_SKB_CB(skb)->sacked;
		int fack_count = state->fack_count;

		/* Account D-SACK for retransmitted packet.
		 * 如果此skb属于DSACK块，且skb被重传过。即此前tag为R、或者R|S。
		 */
		if (dup_sack && (sacked & TCPCB_RETRANS)) {

			/* 位于上次进入Recovery或Loss之后 */
			if (after(TCP_SKB_CB(skb)->end_seq, tp->undo_marker))
				tp->undo_retrans--;          /* 如果减为0，那么说明之前重传都是不必要的，进行拥塞控制调整撤销 */

			if (sacked & TCPCB_SACKED_ACKED) /* 如果这个包已经被SACK过，那么说明是乱序 */
				state->reord = min(fack_count, state->reord); /* 更新乱序队列的起始点 */
		}

		/* Nothing to do; acked frame is about to be dropped (was ACKed).
		 * 这个skb已经被正常确认了，不用再处理了，它即将被丢弃。
		 */
		if (! after(TCP_SKB_CB(skb)->end_seq, tp->snd_una))
			return sacked;

		/* 如果skb还没有被SACK，那么进行处理 */
		if (! (sacked & TCPCB_SACKED_ACKED)) {

			/* 有R标志，表示被重传过 */
			if (sacked & TCPCB_SACKED_RETRANS) {
				/* If the segment is not tagged as lost, we do not clear RETRANS, believing
				 * that retransmission is still in flight.
				 * 如果之前的标志是：R | L，那么好，现在收到包了，可以清除R和L。
				 * 如果之前的标志是：R，那么认为现在收到的是orig，重传包还在路上，所以不用干活：）
				 */
				if (sacked & TCPCB_LOST) {
					sacked &= ~(TCPCB_LOST | TCPCB_SACKED_RETRANS); /* 取消L和R标志 */
					tp->lost_out -= pcount; /* 更新LOST包个数 */
					tp->retrans_out -= pcount; /* 更新RETRANS包个数 */
				}

			} else { /* 没有R标志 */
				if (! (sacked & TCPCB_RETRANS)) {
					/* New sack for not retransmitted frame, which was in hole. It is reordering.
					 * 如果一个包落在highest_sack之前，它即没被SACK过，也不是重传的，那么
					 * 它肯定是乱序了，到现在才被SACK。
					 */
					if (before(TCP_SKB_CB(skb)->seq, tcp_highest_sack_seq(tp)))
						state->reord = min(fack_count, state->reord); /* 记录乱序的起始位置 */

					/* SACK enhanced F-RTO (RFC4138; Appendix B) */
					if (! after(TCP_SKB_CB(skb)->end_seq, tp->frto_highmark))
						state->flag |= FLAG_ONLY_ORIG_SACKED; /* SACKs only non-rexmit sent before RTO */
				}

				/* 如果它有LOST标志，既然收到了，那么要撤销了 */
				if (sacked & TCPCB_LOST) {
					sacked &= ~TCPCB_LOST; /* 撤销LOST标志 */
					tp->lost_out -= pcount; /* 更新LOST包个数 */
				}
			}

			sacked |= TCPCB_SACKED_ACKED; /* 给skb打上SACK标志，就是这里：） */
			state->flag |= FLAG_DATA_SACKED;
			tp->sacked_out += pcount; /* 更新SACK包个数 */
			fack_count += pcount; /* fackets_out =sacked_out + lost_out，也跟着更新 */

			/* 没有使用FACK时 */
			if (! tcp_is_fack(tp) && (tp->lost_skb_hint != NULL) &&
				before(TCP_SKB_CB(skb)->seq, TCP_SKB_CB(tp->lost_skb_hint)->seq))
				tp->lost_cnt_hint += pcount;

			if (fack_count > tp->fackets_out)
				tp->fackets_out = fack_count; /* 更新tp->fackets_out */
		}

		/* D-SACK. We can detect redundant retransmission in S|R and plain R frames and clear it.
		 * undo_retrans is decreased above, L|R frames are accounted above as well.
		 * 如果skb被D-SACK，并且它的重传标志还未被清除，那么现在清除。
		 */
		if (dup_sack && (sacked & TCPCB_SACKED_RETRANS)) {
			sacked &= ~TCPCB_SACKED_RETRANS; /* 清除重传标志 */
			tp->retrans_out -= pcount; /* 更新重传包个数 */
		}

		return sacked; /* 返回此skb的记分牌 */
	}
```

--------------

### TCP的核心系列 — SACK和DSACK的实现（七）


我们发送重传包时，重传包也可能丢失，如果没有检查重传包是否丢失的机制，那么只能依靠超时来恢复了。  
37版本把检查重传包是否丢失的部分独立出来，这就是tcp_mark_lost_retrans()。  
在处理SACK块的同时，会检测是否有出现乱序，如果有乱序，那么会计算乱序的长度并更新。  

本文主要内容：检查重传包是否丢失，以及乱序的检测和更新。

#### 检查重传包是否丢失
tcp_mark_lost_retrans()用于检查重传的包是否丢失，2.6.22内核在检查重传包是否丢失时是有Bug的，  
具体可见：http://projects.itri.aist.go.jp/gnet/sack-bug.html

Q: 怎么检查重传包是否丢失呢？  
A: 我们知道，要发送数据时，是先发送重传包，之后才发送新包的。  
	如果重传包顺利到达接收端，当新包到达时，服务器端会收到一个对新包的正常确认。  
	如果重传包丢失了，当新包到达时，服务器端会收到一个对新包的选择性确认。

	基于这个事实：  
	当重传一个包时，我们记录当时要发送的下一新包的序列号(当时的tp->snd_nxt)。  
	当我们收到SACK时，就检查新包是被正常ACK，还是被SACK。如果新包被SACK，  
	但是重传包还没有，就说明当时重传的包已经丢失了。  

重传一个包时，会记录当时要发送的下一个新包的序号，即tp->snd_nxt。

```
	int tcp_retransmit_skb(struct sock *sk, struct sk_buff *skb)
	{
		...

		/* 如果之前网络中没有重传包 */
		if (! tp->retrans_out)
			tp->lost_retrans_low = tp->snd_nxt;

		TCP_SKB_CB(skb)->sacked |= TCPCB_RETRANS; /* 打上R标记 */
		tp->retrans_out += tcp_skb_pcount(skb);   /* 更新retrans_out */

		/* Save stamp of the first retransmit. */
		if (! tp->retrans_stamp)
			tp->retrans_stamp = TCP_SKB_CB(skb)->when;

		tp->undo_retrans++;

		/* snd_nxt is stored to detect loss of retransmitted segment,
		 * see tcp_input.c tcp_sacktag_write_queue().
		 * 就是在这里！把这时的snd_nxt保存到重传包的ack_seq。
		 */
		TCP_SKB_CB(skb)->ack_seq = tp->snd_nxt;

		...
	}
```

检查重传包是否丢失，如果丢失了，重新打L标志。
```
	/* Check for lost retransmit. */
	static void tcp_mark_lost_retrans(struct sock *sk)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb;
		int cnt = 0;
		u32 new_low_seq = tp->snd_nxt;                /* 下一个要发送的新包序列号 */
		u32 received_upto = tcp_highest_sack_seq(tp); /* 被SACK过的最大序列号 */

		/* 使用这个方法的条件：
		 * 使用FACK；有重传包；上次的最低snd_nxt被SACK；处于Recovery状态
		 */
		if (! tcp_is_fack(tp) || ! tp->retrans_out || ! after(received_upto, tp->lost_retrans_low)
			|| icsk->icsk_ca_state != TCP_CA_Recovery)
		return;

		tcp_for_write_queue(skb, sk) {
			/* 注意了：对于重传包来说，ack_seq其实是当时的snd_nxt */
			u32 ack_seq = TCP_SKB_CB(skb)->ack_seq;

			if (skb == tcp_send_head(sk)) /* 发送队列头了 */
				break;

			/* 我们关注的是重传的包，如果遍历完了，就退出 */
			if (cnt == tp->retrans_out)
				break;

			/* 不关心成功确认过的包 */
			if (! after(TCP_SKB_CB(skb)->end_seq, tp->snd_una))
				continue;

			/* 只关注重传包，必须有R标志才处理 */
			if (! (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS))
				continue;

			/*
			 * 如果重传包记录的snd_nxt被SACK了，那说明重传包丢了；否则应该在新包之前被确认才对。
			 */
			if (after(received_upto, ack_seq)) {
				TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_RETRANS; /* 取消R标志 */
				tp->retrans_out -= tcp_skb_pcount(skb); /* 更新网络中重传包数量 */
				tcp_skb_mark_lost_uncond_verify(tp, skb); /* 给重传包打上LOST标志，并更新相关变量 */
				NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPLOSTRETRANSMIT);

			} else { /* 如果重传包对应的snd_nxt在最高SACK序列号之后 */
				if (before(ack_seq, new_low_seq))
					new_low_seq = ack_seq;  /* 更新未检测的重传包对应的最小snd_nxt */
				cnt += tcp_skb_pcount(skb); /* 用于判断重传包是否检查完了 */
			}
		}

		/* 如果还有未检查完的重传包，那么更新未检测的重传包对应的最小snd_nxt */
		if (tp->retrans_out)
			tp->lost_retrans_low = new_low_seq;

	}
```

给数据包打上LOST标志，更新相关变量。
```
	static void tcp_skb_mark_lost_uncond_verify(struct tcp_sock *tp, struct sk_buff *skb)
	{
		/* 更新重传过的包的最低、最高序号 */
		tcp_verfiy_retransmit_hint(tp, skb);

		/* 如果这个包还未打上L标志，且没有S标志 */
		if (! (TCP_SKB_CB(skb)->sacked & (TCP_LOST | TCPCB_SACKED_ACKED))) {
			tp->lost_out += tcp_skb_pcount(skb);   /* 更新网络中丢失包数量 */
			TCP_SKB_CB(skb)->sacked |= TCPCB_LOST; /* 打上L标志 */
		}
	}

	/* This must be called before lost_out is incremented
	 * 记录重传过的包的最低序号、最高序号。
	 */
	static void tcp_verify_retransmit_hint(struct tcp_sock *tp, struct sk_buff *skb)
	{
		if ((tp->retransmit_skb_hint == NULL) || before(TCP_SKB_CB(skb)->seq,
			TCP_SKB_CB(tp->retransmit_skb_hint)->seq))
			tp->retransmit_skb_hint = skb;

		if (! tp->lost_out || after(TCP_SKB_CB(skb)->end_seq, tp->retransmit_high))
			tp->retransmit_high = TCP_SKB_CB(skb)->end_seq;
	}
```

#### 乱序处理
说明  
Reordering metric is maximal distance, which a packet can be displaced in packet stream.  
With SACKs we can estimate it:  
1. SACK fills old hole and the corresponding segment was not ever retransmitted -> reordering.  
	Alas, we cannot use it when segment was retransmitted.  
2. The last flaw it solved with D-SACK. D-SACK arrives for retransmitted and already SACKed segment  
	-> reordering..   
Both of these heuristics are not used in Loss state, when we cannot account for retransmits accurately.

对于乱序，我们主要关注如何检测乱序，以及计算乱序的长度。  
在tcp_sacktag_one()中有进行乱序的检测，那么在收到SACK或DSACK时怎么判断有乱序呢？  

（1）skb的记分牌为S|R，然后它被DSACK。  
我们想象一下，一个数据包乱序了，它滞留在网络的某个角落里。我们收到后续包的SACK，认为这个包丢失了，进行重传。之后原始包到达接收端了，这个数据包被SACK了。最后重传包也到达接收端了，这个包被DSACK了。  

（2）如果一个包落在highest_sack之前，它既没被SACK过，也不是重传的，那么它肯定是乱序了，到现在才被SACK。

如果检测到了乱序，那么乱序队列的长队为：tp->fackets_out - state.reord。

```
	static void tcp_update_reordering(struct sock *sk, const int metric,
										   const int ts)
	{
		struct tcp_sock *tp = tcp_sk(sk);

		if (metric > tp->reordering) {
			int mib_idx;
			/* 更新reordering的值，取其小者*/
			tp->reordering = min(TCP_MAX_REORDERING, metric);

			if (ts)
				mib_idx = LINUX_MIB_TCPTSREORDER;
			else if (tcp_is_reno(tp))
				mib_idx = LINUX_MIB_TCPRENOREORDER;
			else if (tcp_is_fack(tp))
				mib_idx = LINUX_MIB_TCPFACKREORDER;
			else
				mib_idx = LINUX_MIB_TCPSACKREORDER;

			NET_INC_STATS_BH(sock_net(sk), mib_idx);
	#if FASTRETRANS_DEBUG > 1
			printk(KERN_DEBUG "Disorder%d %d %u f%u s%u rr%d\n",
					   tp->rx_opt.sack_ok, inet_csk(sk)->icsk_ca_state,
					   tp->reordering, tp->fackets_out, tp->sacked_out,
					   tp->undo_marker ? tp->undo_retrans : 0);
	#endif
			tcp_disable_fack(tp); /* 出现了reorder，再用fack就太激进了*/
		}
	}
```

```
	/* Packet counting of FACK is based on in-order assumptions, therefore
	 * TCP disables it when reordering is detected.
	 */
	static void tcp_disable_fack(struct tcp_sock *tp)
	{
		/* RFC3517 uses different metric in lost marker => reset on change */
		if (tcp_is_fack(tp))
			tp->lost_skb_hint = NULL;
		tp->rx_opt.sack_ok &= ~2; /* 取消FACK选项*/
	}
```


