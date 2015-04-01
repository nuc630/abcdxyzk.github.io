---
layout: post
title: "Linux TCP数据包接收处理tcp_data_queue"
date: 2015-04-01 18:20:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://www.cppblog.com/fwxjj/archive/2013/02/18/197906.aspx

#### tcp_data_queue函数
这里就是对数据包的处理了。

```
    static void tcp_data_queue(struct sock *sk, struct sk_buff *skb)  
    {  
        struct tcphdr *th = tcp_hdr(skb);  
        struct tcp_sock *tp = tcp_sk(sk);  
        int eaten = -1;  
        /* 没有数据处理*/  
        if (TCP_SKB_CB(skb)->seq == TCP_SKB_CB(skb)->end_seq)  
            goto drop;  
        /* 跳过tcp头部*/  
        __skb_pull(skb, th->doff * 4);  
        /* 如果收到对方发来的CWR，则本地TCP发送时不在设置ECE*/  
        TCP_ECN_accept_cwr(tp, skb);  
        /* 初始化Duplicate SACK*/  
        if (tp->rx_opt.dsack) {  
            tp->rx_opt.dsack = 0;  
            tp->rx_opt.eff_sacks = tp->rx_opt.num_sacks;  
        }  
```

如果该数据包刚好是下一个要接收的数据，则可以直接copy到用户空间（如果存在且可用），否则排队到receive queue

```
    /*  Queue data for delivery to the user. 
     *  Packets in sequence go to the receive queue. 
     *  Out of sequence packets to the out_of_order_queue. 
     */  
    if (TCP_SKB_CB(skb)->seq == tp->rcv_nxt) {  
        if (tcp_receive_window(tp) == 0)  
            goto out_of_window;  
      
        /* Ok. In sequence. In window. */  
        if (tp->ucopy.task == current &&  
            tp->copied_seq == tp->rcv_nxt && tp->ucopy.len &&  
            sock_owned_by_user(sk) && !tp->urg_data) {  
            int chunk = min_t(unsigned int, skb->len,  
                      tp->ucopy.len);  
      
            __set_current_state(TASK_RUNNING);  
            /* 这里的下半部开关的作用不解*/  
            local_bh_enable();  
            if (!skb_copy_datagram_iovec(skb, 0, tp->ucopy.iov, chunk)) {  
                tp->ucopy.len -= chunk;  
                tp->copied_seq += chunk;  
                eaten = (chunk == skb->len && !th->fin);  
                tcp_rcv_space_adjust(sk);  
            }  
            local_bh_disable();  
        }  
      
        if (eaten <= 0) {  
    ueue_and_out:  
            if (eaten < 0 &&  
                /* 该函数用于判断是否有接收缓存，在tcp内存管理中将分析*/  
                tcp_try_rmem_schedule(sk, skb->truesize))  
                goto drop;  
      
            skb_set_owner_r(skb, sk);  
            __skb_queue_tail(&sk->sk_receive_queue, skb);  
        }  
        tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;  
        if (skb->len)  
            tcp_event_data_recv(sk, skb);  
        if (th->fin)  
            tcp_fin(skb, sk, th);  
        /* 到达的数据包哟可能填充了乱序队列中的hole */  
        if (!skb_queue_empty(&tp->out_of_order_queue)) {  
            tcp_ofo_queue(sk);  
      
            /* RFC2581. 4.2. SHOULD send immediate ACK, when 
             * gap in queue is filled. 
             */  
            /*关闭乒乓模式，在quick计数没消耗完时则可立即发送ACK，见tcp_in_quickack_mode*/  
            if (skb_queue_empty(&tp->out_of_order_queue))  
                inet_csk(sk)->icsk_ack.pingpong = 0;  
        }  
        /* 新数据到达导致返回给对方的SACK Block 调整*/  
        if (tp->rx_opt.num_sacks)  
            tcp_sack_remove(tp);  
        /* 在当前slow path，检测是否可以进入fast path*/  
        tcp_fast_path_check(sk);  
      
        if (eaten > 0)  
            __kfree_skb(skb);  
        else if (!sock_flag(sk, SOCK_DEAD))  
            sk->sk_data_ready(sk, 0);  
        return;  
    }  
```

下面看看函数tcp_ofo_queue，也即out-of-order queue的处理

```
	/* This one checks to see if we can put data from the 
	 * out_of_order queue into the receive_queue. 
	 */  
	static void tcp_ofo_queue(struct sock *sk)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		__u32 dsack_high = tp->rcv_nxt;  
		struct sk_buff *skb;  
	  
		while ((skb = skb_peek(&tp->out_of_order_queue)) != NULL) {  
		    /* 当前hole未覆盖，则处理结束*/  
		    if (after(TCP_SKB_CB(skb)->seq, tp->rcv_nxt))  
		        break;  
		    /* DSACK处理*/  
		    if (before(TCP_SKB_CB(skb)->seq, dsack_high)) {  
		        __u32 dsack = dsack_high;  
		        if (before(TCP_SKB_CB(skb)->end_seq, dsack_high))  
		            dsack_high = TCP_SKB_CB(skb)->end_seq;  
		        tcp_dsack_extend(sk, TCP_SKB_CB(skb)->seq, dsack);  
		    }  
		    /* 该乱序数据包完全被到达的数据包覆盖，则从乱序队列中删除之，并释放该数据包*/  
		    if (!after(TCP_SKB_CB(skb)->end_seq, tp->rcv_nxt)) {  
		        SOCK_DEBUG(sk, "ofo packet was already received /n");  
		        __skb_unlink(skb, &tp->out_of_order_queue);  
		        __kfree_skb(skb);  
		        continue;  
		    }  
		    SOCK_DEBUG(sk, "ofo requeuing : rcv_next %X seq %X - %X/n",  
		           tp->rcv_nxt, TCP_SKB_CB(skb)->seq,  
		           TCP_SKB_CB(skb)->end_seq);  
		    /* hole被填充，取出该乱序数据包到receive queue中排队，并更新rcv_nxt */  
		    __skb_unlink(skb, &tp->out_of_order_queue);  
		    __skb_queue_tail(&sk->sk_receive_queue, skb);  
		    tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;  
		    if (tcp_hdr(skb)->fin)  
		        tcp_fin(skb, sk, tcp_hdr(skb));  
		}  
	}
```

```
    /* 该数据包的数据已经完全存在，则发送DSACK，并进入快速ACK模式，调度ACK发送*/    
    if (!after(TCP_SKB_CB(skb)->end_seq, tp->rcv_nxt)) {  
            /* A retransmit, 2nd most common case.  Force an immediate ack. */  
            NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_DELAYEDACKLOST);  
            tcp_dsack_set(sk, TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq);  
      
    out_of_window:  
            tcp_enter_quickack_mode(sk);  
            inet_csk_schedule_ack(sk);  
    drop:  
            __kfree_skb(skb);  
            return;  
        }  
      
        /* Out of window. F.e. zero window probe. */  
        if (!before(TCP_SKB_CB(skb)->seq, tp->rcv_nxt + tcp_receive_window(tp)))  
            goto out_of_window;  
              
        tcp_enter_quickack_mode(sk);  
        /* 部分数据已存在，则设置正确的DSACK，然后排队到receive queue*/  
        if (before(TCP_SKB_CB(skb)->seq, tp->rcv_nxt)) {  
            /* Partial packet, seq < rcv_next < end_seq */  
            SOCK_DEBUG(sk, "partial packet: rcv_next %X seq %X - %X/n",  
                   tp->rcv_nxt, TCP_SKB_CB(skb)->seq,  
                   TCP_SKB_CB(skb)->end_seq);  
      
            tcp_dsack_set(sk, TCP_SKB_CB(skb)->seq, tp->rcv_nxt);  
      
            /* If window is closed, drop tail of packet. But after 
             * remembering D-SACK for its head made in previous line. 
             */  
            if (!tcp_receive_window(tp))  
                goto out_of_window;  
            goto queue_and_out;  
        }  
```

```
	    TCP_ECN_check_ce(tp, skb); /* 检查ECE是否设置 */  
		/* 以下则把数据包排队到失序队列 */  
		/* 同样先判断内存是否满足 */  
		if (tcp_try_rmem_schedule(sk, skb->truesize))  
		    goto drop;  
	  
		/* Disable header prediction. */  
		tp->pred_flags = 0;  
		inet_csk_schedule_ack(sk);  
	  
		SOCK_DEBUG(sk, "out of order segment: rcv_next %X seq %X - %X/n",  
		       tp->rcv_nxt, TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq);  
	  
		skb_set_owner_r(skb, sk);  
		/* 该数据包是失序队列的第一个数据包*/  
		if (!skb_peek(&tp->out_of_order_queue)) {  
		    /* Initial out of order segment, build 1 SACK. */  
		    if (tcp_is_sack(tp)) {  
		        tp->rx_opt.num_sacks = 1;  
		        tp->rx_opt.dsack     = 0;  
		        tp->rx_opt.eff_sacks = 1;  
		        tp->selective_acks[0].start_seq = TCP_SKB_CB(skb)->seq;  
		        tp->selective_acks[0].end_seq =  
		                    TCP_SKB_CB(skb)->end_seq;  
		    }  
		    __skb_queue_head(&tp->out_of_order_queue, skb);  
		} else {  
		    struct sk_buff *skb1 = tp->out_of_order_queue.prev;  
		    u32 seq = TCP_SKB_CB(skb)->seq;  
		    u32 end_seq = TCP_SKB_CB(skb)->end_seq;  
		    /*刚好与失序队列最后一个数据包数据衔接*/  
		    if (seq == TCP_SKB_CB(skb1)->end_seq) {  
		        __skb_queue_after(&tp->out_of_order_queue, skb1, skb);  
		        /*如果没有sack block或者当前数据包开始序号不等于第一个block右边界*/  
		        if (!tp->rx_opt.num_sacks ||  
		            tp->selective_acks[0].end_seq != seq)  
		            goto add_sack;  
		        /*该数据包在某个hole后是按序到达的，所以可以直接扩展第一个sack*/    
		        /* Common case: data arrive in order after hole. */  
		        tp->selective_acks[0].end_seq = end_seq;  
		        return;  
		    }  
	  
		    /* Find place to insert this segment. */  
		    /* 该循环找到一个开始序号不大于该数据包开始序号的失序队列中的数据包*/  
		    do {  
		        if (!after(TCP_SKB_CB(skb1)->seq, seq))  
		            break;  
		    } while ((skb1 = skb1->prev) !=  
		         (struct sk_buff *)&tp->out_of_order_queue);  
	  
		    /* Do skb overlap to previous one? 检查与前个数据包是否有重叠*/  
		    if (skb1 != (struct sk_buff *)&tp->out_of_order_queue &&  
		        before(seq, TCP_SKB_CB(skb1)->end_seq)) {  
		        if (!after(end_seq, TCP_SKB_CB(skb1)->end_seq)) {  
		            /* All the bits are present. Drop. */  
		            __kfree_skb(skb);  
		            tcp_dsack_set(sk, seq, end_seq);  
		            goto add_sack;  
		        }  
		        if (after(seq, TCP_SKB_CB(skb1)->seq)) {  
		            /* Partial overlap. */  
		            tcp_dsack_set(sk, seq,  
		                      TCP_SKB_CB(skb1)->end_seq);  
		        } else {  
		            skb1 = skb1->prev;  
		        }  
		    }  
		    /* 排队到失序队列*/  
		    __skb_queue_after(&tp->out_of_order_queue, skb1, skb);  
	  
		    /* And clean segments covered by new one as whole. 检测与后面的数据包重叠*/  
		    while ((skb1 = skb->next) !=  
		           (struct sk_buff *)&tp->out_of_order_queue &&  
		           after(end_seq, TCP_SKB_CB(skb1)->seq)) {  
		        if (before(end_seq, TCP_SKB_CB(skb1)->end_seq)) {  
		            tcp_dsack_extend(sk, TCP_SKB_CB(skb1)->seq,  
		                     end_seq);  
		            break;  
		        }  
		        __skb_unlink(skb1, &tp->out_of_order_queue);  
		        tcp_dsack_extend(sk, TCP_SKB_CB(skb1)->seq,  
		                 TCP_SKB_CB(skb1)->end_seq);  
		        __kfree_skb(skb1);  
		    }  
	  
	add_sack:  
		    if (tcp_is_sack(tp))  
		        /* 根据失序队列的现状更新SACK的blocks */  
		        tcp_sack_new_ofo_skb(sk, seq, end_seq);  
		}  
	}
```

