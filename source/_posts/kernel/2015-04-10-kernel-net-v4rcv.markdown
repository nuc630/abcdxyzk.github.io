---
layout: post
title: "Linux TCP数据包接收处理 tcp_v4_rcv"
date: 2015-04-10 15:23:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.sina.com.cn/s/blog_52355d840100b6sd.html

#### tcp_v4_rcv函数

``` 
	int tcp_v4_rcv(struct sk_buff *skb)
	{
		const struct iphdr *iph;
		struct tcphdr *th;
		struct sock *sk;
		int ret;
		  
		//如果不是发往本地的数据包，则直接丢弃
		if (skb->pkt_type != PACKET_HOST)
			goto discard_it;

		TCP_INC_STATS_BH(TCP_MIB_INSEGS);

		//包长是否大于TCP头的长度
		if (!pskb_may_pull(skb, sizeof(struct tcphdr)))
			goto discard_it;

		//取得TCP首部
		th = tcp_hdr(skb);

		//检查TCP首部的长度和TCP首部中的doff字段是否匹配
		if (th->doff < sizeof(struct tcphdr) / 4)
			goto bad_packet;

		//检查TCP首部到TCP数据之间的偏移是否越界
		if (!pskb_may_pull(skb, th->doff * 4))
			goto discard_it;

		if (!skb_csum_unnecessary(skb) && tcp_v4_checksum_init(skb))
			goto bad_packet;

		 th = tcp_hdr(skb);
		iph = ip_hdr(skb);
		TCP_SKB_CB(skb)->seq = ntohl(th->seq);

		//计算end_seq,实际上，end_seq是数据包的结束序列号，实际上是期待TCP确认
		//包中ACK的数值，在数据传输过程中，确认包ACK的数值等于本次数据包SEQ
		//号加上本数据包的有效载荷，即skb->len - th->doff * 4,但是在处理SYN报文或者
		//FIN报文的时候，确认包的ACK等于本次处理数据包的SEQ+1,考虑到这种情况，
		//期待下一个数据包的ACK就变成了TCP_SKB_CB(skb)->seq + th->syn + th->fin +
		//skb->len - th->doff * 4

		// TCP_SKB_CB宏会返回skb->cb[0],一个类型为tcp_skb_cb的结构指针，这个结
		//构保存了TCP首部选项和其他的一些状态信息

		TCP_SKB_CB(skb)->end_seq = (TCP_SKB_CB(skb)->seq + th->syn + th->fin +
						skb->len - th->doff * 4);
		TCP_SKB_CB(skb)->ack_seq = ntohl(th->ack_seq);
		TCP_SKB_CB(skb)->when   = 0;
		TCP_SKB_CB(skb)->flags    = iph->tos;
		TCP_SKB_CB(skb)->sacked = 0;

		//根据四元组查找相应连接的sock结构，大体有两个步骤，
		//首先用__inet_lookup_established函数查找已经处于establish状态的连接，
		//如果查找不到的话，就调用__inet_lookup_listener函数查找是否存在四元组相
		//匹配的处于listen状态的sock,这个时候实际上是被动的接收来自其他主机的连接
		//请求

		//如果查找不到匹配的sock,则直接丢弃数据包
		sk = __inet_lookup(&tcp_hashinfo, iph->saddr, th->source,
				   iph->daddr, th->dest, inet_iif(skb));
		if (!sk)
			goto no_tcp_socket;

		//检查sock是否处于半关闭状态
		process:
		if (sk->sk_state == TCP_TIME_WAIT)
			goto do_time_wait;
	 
		//检查IPSEC规则
		if (!xfrm4_policy_check(sk, XFRM_POLICY_IN, skb))
			goto discard_and_relse;
		nf_reset(skb);

		//检查BPF规则
		if (sk_filter(sk, skb))
			goto discard_and_relse;

		skb->dev = NULL;

		//这里主要是和release_sock函数实现互斥，release_sock中调用了
		// spin_lock_bh(&sk->sk_lock.slock);
		bh_lock_sock_nested(sk);
		ret = 0;

		//查看是否有用户态进程对该sock进行了锁定
		//如果sock_owned_by_user为真，则sock的状态不能进行更改
		if (!sock_owned_by_user(sk)) {

	#ifdef CONFIG_NET_DMA
			struct tcp_sock *tp = tcp_sk(sk);
			if (!tp->ucopy.dma_chan && tp->ucopy.pinned_list)
				tp->ucopy.dma_chan = get_softnet_dma();
			if (tp->ucopy.dma_chan)
				ret = tcp_v4_do_rcv(sk, skb);
			else
	#endif
			{
				//进入预备处理队列
				if (!tcp_prequeue(sk, skb))
					ret = tcp_v4_do_rcv(sk, skb);
			}
		} else
			//如果数据包被用户进程锁定，则数据包进入后备处理队列，并且该进程进入
			//套接字的后备处理等待队列sk->lock.wq
			sk_add_backlog(sk, skb);
		bh_unlock_sock(sk);

		sock_put(sk);
		return ret;

	no_tcp_socket:
		if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb))
			goto discard_it;

		if (skb->len < (th->doff << 2) || tcp_checksum_complete(skb)) {
	bad_packet:
			TCP_INC_STATS_BH(TCP_MIB_INERRS);
		} else {
			tcp_v4_send_reset(NULL, skb);
		}

	discard_it:
		kfree_skb(skb);
		return 0;

	discard_and_relse:
		sock_put(sk);
		goto discard_it;

	do_time_wait:
		if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb)) {
			inet_twsk_put(inet_twsk(sk));
			goto discard_it;
		}

		if (skb->len < (th->doff << 2) || tcp_checksum_complete(skb)) {
			TCP_INC_STATS_BH(TCP_MIB_INERRS);
			inet_twsk_put(inet_twsk(sk));
			goto discard_it;
		}
		switch (tcp_timewait_state_process(inet_twsk(sk), skb, th)) {
		case TCP_TW_SYN: {
			struct sock *sk2 = inet_lookup_listener(&tcp_hashinfo,
								iph->daddr, th->dest,
								inet_iif(skb));
			if (sk2) {
				inet_twsk_deschedule(inet_twsk(sk), &tcp_death_row);
				inet_twsk_put(inet_twsk(sk));
				sk = sk2;
				goto process;
			}
		}
		case TCP_TW_ACK:
			tcp_v4_timewait_ack(sk, skb);
			break;
		case TCP_TW_RST:
			goto no_tcp_socket;
		case TCP_TW_SUCCESS:;
		}
		goto discard_it;
	}
```

