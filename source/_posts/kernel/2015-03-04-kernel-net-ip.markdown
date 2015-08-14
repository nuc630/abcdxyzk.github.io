---
layout: post
title: "linux TCP/IP协议栈-IP层"
date: 2015-03-04 17:03:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
[linux TCP/IP协议栈 ---ip_rcv()](http://blog.chinaunix.net/uid-22577711-id-3216938.html)  
[linux TCP/IP协议栈 ---ip_rcv_finish()](http://blog.chinaunix.net/uid-22577711-id-3216949.html)  
[linux TCP/IP协议栈 ---ip_local_deliver()](http://blog.chinaunix.net/uid-22577711-id-3218535.html)  
[linux TCP/IP协议栈 ---ip_local_deliver_finish()](http://blog.chinaunix.net/uid-22577711-id-3218536.html)  
[linux TCP/IP协议栈 ---ip_defrag()](http://blog.chinaunix.net/uid-22577711-id-3218543.html)  
[linux TCP/IP协议栈 ---ip_find()](http://blog.chinaunix.net/uid-22577711-id-3218545.html)  
[linux TCP/IP协议栈 ---inet_frag_find()](http://blog.chinaunix.net/uid-22577711-id-3218548.html)  

#### ip_rcv()
```
	/* 主要功能：对IP头部合法性进行严格检查，然后把具体功能交给ip_rcv_finish。*/
	int ip_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *orig_dev)
	{
		struct iphdr *iph;
		u32 len;
		/* 网络名字空间，忽略 */
		if (dev->nd_net != &init_net)
			goto drop;
		/*
		 *当网卡处于混杂模式时，收到不是发往该主机的数据包，由net_rx_action()设置。
		 *在调用ip_rcv之前，内核会将该数据包交给嗅探器，所以该函数仅丢弃该包。
		 */
		if (skb->pkt_type == PACKET_OTHERHOST)
			goto drop;
		/* SNMP所需要的统计数据，忽略 */
		IP_INC_STATS_BH(IPSTATS_MIB_INRECEIVES);

		/*
		 *ip_rcv是由netif_receive_skb函数调用，如果嗅探器或者其他的用户对数据包需要进
		 *进行处理，则在调用ip_rcv之前，netif_receive_skb会增加skb的引用计数，既该引
		 *用计数会大于1。若如此次，则skb_share_check会创建sk_buff的一份拷贝。
		 */
		if ((skb = skb_share_check(skb, GFP_ATOMIC)) == NULL) {
			IP_INC_STATS_BH(IPSTATS_MIB_INDISCARDS);
			goto out;
		}
		/*
		 *pskb_may_pull确保skb->data指向的内存包含的数据至少为IP头部大小，由于每个
		 *IP数据包包括IP分片必须包含一个完整的IP头部。如果小于IP头部大小，则缺失
		 *的部分将从数据分片中拷贝。这些分片保存在skb_shinfo(skb)->frags[]中。
		 */
		if (!pskb_may_pull(skb, sizeof(struct iphdr)))
			goto inhdr_error;
		/* pskb_may_pull可能会调整skb中的指针，所以需要重新定义IP头部*/
		iph = ip_hdr(skb);

		/*
		 *    RFC1122: 3.1.2.2 MUST silently discard any IP frame that fails the checksum.
		 *
		 *    Is the datagram acceptable?
		 *
		 *    1.    Length at least the size of an ip header
		 *    2.    Version of 4
		 *    3.    Checksums correctly. [Speed optimisation for later, skip loopback checksums]
		 *    4.    Doesn't have a bogus length
		 */
		/* 上面说的很清楚了 */
		if (iph->ihl < 5 || iph->version != 4)
			goto inhdr_error;
		/* 确保IP完整的头部包括选项在内存中 */
		if (!pskb_may_pull(skb, iph->ihl*4))
			goto inhdr_error;
		
		iph = ip_hdr(skb);
		/* 验证IP头部的校验和 */
		if (unlikely(ip_fast_csum((u8 *)iph, iph->ihl)))
			goto inhdr_error;
		/* IP头部中指示的IP数据包总长度 */
		len = ntohs(iph->tot_len);
		/*
		 *确保skb的数据长度大于等于IP头部中指示的IP数据包总长度及数据包总长度必须
		 *大于等于IP头部长度。
		 */
		if (skb->len < len) {
			IP_INC_STATS_BH(IPSTATS_MIB_INTRUNCATEDPKTS);
			goto drop;
		} else if (len < (iph->ihl*4))
			goto inhdr_error;

		/* Our transport medium may have padded the buffer out. Now we know it
		 * is IP we can trim to the true length of the frame.
		 * Note this now means skb->len holds ntohs(iph->tot_len).
		 */
		/* 注释说明的很清楚，该函数成功执行完之后，skb->len = ntohs(iph->tot_len). */
		if (pskb_trim_rcsum(skb, len)) {
			IP_INC_STATS_BH(IPSTATS_MIB_INDISCARDS);
			goto drop;
		}

		/* Remove any debris in the socket control block */
		memset(IPCB(skb), 0, sizeof(struct inet_skb_parm));
		/* 忽略与netfilter子系统的交互，调用为ip_rcv_finish(skb) */
		return NF_HOOK(PF_INET, NF_IP_PRE_ROUTING, skb, dev, NULL,
			 ip_rcv_finish);

	inhdr_error:
		IP_INC_STATS_BH(IPSTATS_MIB_INHDRERRORS);
	drop:
		kfree_skb(skb);
	out:
		return NET_RX_DROP;
	}
```

#### ip_rcv_finish()
```
	static int ip_rcv_finish(struct sk_buff *skb)
	{
		const struct iphdr *iph = ip_hdr(skb);
		struct rtable *rt;

		/*
		 *    Initialise the virtual path cache for the packet. It describes
		 *    how the packet travels inside Linux networking.
		 */
		/*
		 * 通常从外界接收的数据包,skb->dst不会包含路由信息，暂时还不知道在何处会设置
		 * 这个字段。ip_route_input函数会根据路由表设置路由信息，暂时不考虑路由系统。
		 */
		if (skb->dst == NULL) {
			int err = ip_route_input(skb, iph->daddr, iph->saddr, iph->tos,
						 skb->dev);
			if (unlikely(err)) {
				if (err == -EHOSTUNREACH)
					IP_INC_STATS_BH(IPSTATS_MIB_INADDRERRORS);
				else if (err == -ENETUNREACH)
					IP_INC_STATS_BH(IPSTATS_MIB_INNOROUTES);
				goto drop;
			}
		}
	/* 更新流量控制所需要的统计数据，忽略 */
	#ifdef CONFIG_NET_CLS_ROUTE
		if (unlikely(skb->dst->tclassid)) {
			struct ip_rt_acct *st = ip_rt_acct + 256*smp_processor_id();
			u32 idx = skb->dst->tclassid;
			st[idx&0xFF].o_packets++;
			st[idx&0xFF].o_bytes+=skb->len;
			st[(idx>>16)&0xFF].i_packets++;
			st[(idx>>16)&0xFF].i_bytes+=skb->len;
		}
	#endif
		/* 如果IP头部大于20字节，则表示IP头部包含IP选项，需要进行选项处理.暂时忽略，毕竟很少用 */
		if (iph->ihl > 5 && ip_rcv_options(skb))
			goto drop;

		/* skb->dst包含路由信息。根据路由类型更新SNMP统计数据 */
		rt = (struct rtable*)skb->dst;
		if (rt->rt_type == RTN_MULTICAST)
			IP_INC_STATS_BH(IPSTATS_MIB_INMCASTPKTS);
		else if (rt->rt_type == RTN_BROADCAST)
			IP_INC_STATS_BH(IPSTATS_MIB_INBCASTPKTS);
		/*
		 * dst_input实际上会调用skb->dst->input(skb).input函数会根据路由信息设置为合适的
		 * 函数指针，如果是递交到本地的则为ip_local_deliver，若是转发则为ip_forward.
		 * 暂时仅先考虑ip_local_deliver。
		 */
		return dst_input(skb);

	drop:
		kfree_skb(skb);
		return NET_RX_DROP;
	}
```

#### ip_local_deliver()
```
	/*
	 *     Deliver IP Packets to the higher protocol layers.
	 */
	主要功能：收集IP分片，然后调用ip_local_deliver_finish将一个完整的数据包传送给上层协议。
	int ip_local_deliver(struct sk_buff *skb)
	{
		/*
		 *    Reassemble IP fragments.
		 */
		/*
		 * 判断该IP数据包是否是一个分片，如果IP_MF置位，则表示该包是分片之一，其
		 * 后还有更多分片，最后一个IP分片未置位IP_MF但是其offset是非0。
		 * 如果是一个IP分片，则调用ip_defrag重新组织IP数据包。
		 */
		if (ip_hdr(skb)->frag_off & htons(IP_MF | IP_OFFSET)) {
			if (ip_defrag(skb, IP_DEFRAG_LOCAL_DELIVER))
				return 0;
		}
		/* 调用ip_local_deliver_finish(skb) */
		return NF_HOOK(PF_INET, NF_IP_LOCAL_IN, skb, skb->dev, NULL,
			 ip_local_deliver_finish);
	}
```

#### ip_local_deliver_finish()
```
	/* 如果忽略掉原始套接字和IPSec，则该函数仅仅是根据IP头部中的协议字段选择上层L4协议，并交给它来处理 */
	static int ip_local_deliver_finish(struct sk_buff *skb)
	{
		/* 跳过IP头部 */
		__skb_pull(skb, ip_hdrlen(skb));

		/* Point into the IP datagram, just past the header. */
		/* 设置传输层头部位置 */
		skb_reset_transport_header(skb);

		rcu_read_lock();
		{
			/* Note: See raw.c and net/raw.h, RAWV4_HTABLE_SIZE==MAX_INET_PROTOS */
			int protocol = ip_hdr(skb)->protocol;
			int hash;
			struct sock *raw_sk;
			struct net_protocol *ipprot;

		resubmit:
		/* 这个hash根本不是哈希值，仅仅只是inet_protos数组中的下表而已 */
			hash = protocol & (MAX_INET_PROTOS - 1);
			raw_sk = sk_head(&raw_v4_htable[hash]);

			/* If there maybe a raw socket we must check - if not we
			 * don't care less
			 */
		/* 原始套接字？？ 忽略... */
			if (raw_sk && !raw_v4_input(skb, ip_hdr(skb), hash))
				raw_sk = NULL;
		/* 查找注册的L4层协议处理结构。 */
			if ((ipprot = rcu_dereference(inet_protos[hash])) != NULL) {
				int ret;
		/* 启用了安全策略，则交给IPSec */
				if (!ipprot->no_policy) {
					if (!xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb)) {
						kfree_skb(skb);
						goto out;
					}
					nf_reset(skb);
				}
		/* 调用L4层协议处理函数 */
		/* 通常会是tcp_v4_rcv, udp_rcv, icmp_rcv和igmp_rcv */
		/* 如果注册了其他的L4层协议处理，则会进行相应的调用。 */
				ret = ipprot->handler(skb);
				if (ret < 0) {
					protocol = -ret;
					goto resubmit;
				}
				IP_INC_STATS_BH(IPSTATS_MIB_INDELIVERS);
			} else {
				if (!raw_sk) {    /* 无原始套接字，提交给IPSec */
					if (xfrm4_policy_check(NULL, XFRM_POLICY_IN, skb)) {
						IP_INC_STATS_BH(IPSTATS_MIB_INUNKNOWNPROTOS);
						icmp_send(skb, ICMP_DEST_UNREACH,
							 ICMP_PROT_UNREACH, 0);
					}
				} else
					IP_INC_STATS_BH(IPSTATS_MIB_INDELIVERS);
				kfree_skb(skb);
			}
		}
	 out:
		rcu_read_unlock();

		return 0;
	}
```

#### ip_defrag()
```
	/* Process an incoming IP datagram fragment. */
	int ip_defrag(struct sk_buff *skb, u32 user)
	{
		struct ipq *qp;

		IP_INC_STATS_BH(IPSTATS_MIB_REASMREQDS);

		/* Start by cleaning up the memory. */
		/*
		 * 首先检查所有IP分片所消耗的内存是否大于系统允许的最高阀值，如果是，则调用
		 * ip_evictor()丢弃未完全到达的IP分片，从最旧的分片开始释放。此举一来是为了节
		 * 约内存，二来是未了防止黑客的恶意攻击。使分片在系统中累计，降低系统性能。
		 */
		if (atomic_read(&ip4_frags.mem) > ip4_frags_ctl.high_thresh)
			ip_evictor();

		/* Lookup (or create) queue header */
		/* 如果该分片是数据报的第一个分片，则ip_find返回一个新的队列来搜集分片，否则
		 * 返回其所属于的分片队列。 */
		if ((qp = ip_find(ip_hdr(skb), user)) != NULL) {
			int ret;

			spin_lock(&qp->q.lock);
		/* 将该分片加入到队列中，重组分片队列，如果所有的包都收到了，则该函数
		 * 负责重组IP包 */
			ret = ip_frag_queue(qp, skb);

			spin_unlock(&qp->q.lock);
			ipq_put(qp);    /* 引用计数减1 */
			return ret;
		}

		IP_INC_STATS_BH(IPSTATS_MIB_REASMFAILS);
		kfree_skb(skb);
		return -ENOMEM;
	}
```

#### ip_find()
```
	/* Find the correct entry in the "incomplete datagrams" queue for
	 * this IP datagram, and create new one, if nothing is found.
	 */
	/* u32 user这个参数有点迷惑，其表示以何种理由需要对数据包进行重组，在ip_local_deliver的调用序列当中，这个值是IP_DEFRAG_LOCAL_DELIVER。*/
	static inline struct ipq *ip_find(struct iphdr *iph, u32 user)
	{
		struct inet_frag_queue *q;
		struct ip4_create_arg arg;
		unsigned int hash;

		arg.iph = iph;
		arg.user = user;
		/*
		 * hash算法，该算法除了使用所给的这四个参数之外，还使用了一个随机值
		 * ip4_frags.rnd,，其初始化为
		 * (u32) ((num_physpages ^ (num_physpages>>7)) ^ (jiffies ^ (jiffies >> 6)));
		 * 这是为了防止黑客根据固定的hash算法，通过设置ip头部的这些字段，生成同样
		 * HASH值，从而使某一HASH队列长度急剧增大而影响性能。
		 */
		hash = ipqhashfn(iph->id, iph->saddr, iph->daddr, iph->protocol);
		/* 若存在该分片所属的分片队列则返回这个队列，否则创建一个新的队列 */
		q = inet_frag_find(&ip4_frags, &arg, hash);
		if (q == NULL)
			goto out_nomem;

		return container_of(q, struct ipq, q);

	out_nomem:
		LIMIT_NETDEBUG(KERN_ERR "ip_frag_create: no memory left !\n");
		return NULL;
	}
```

#### inet_frag_find()
```
	struct inet_frag_queue *inet_frag_find(struct inet_frags *f, void *key,
			unsigned int hash)
	{
		struct inet_frag_queue *q;
		struct hlist_node *n;

		/* f->lock是读写锁，先搜索是否存在该IP分段所属的队列 */
		read_lock(&f->lock);
		hlist_for_each_entry(q, n, &f->hash[hash], list) { /* 扫描该HASH槽中所有节点 */
		/* f->match中match字段在ipfrag_init中初始化为ip4_frag_match函数。*/
		/* 对比分片队列中的散列字段和user是否和key相等，key指向的是struct ip4_create_arg
		 * 结构，包含IP头部和user字段。 */
			if (f->match(q, key)) {
				atomic_inc(&q->refcnt);     /* 若找到，则增加该队列引用计数。 */
				read_unlock(&f->lock);
				return q;                /* 返回该队列 */
			}
		}
		read_unlock(&f->lock);
		/* 该分片是第一个IP分片，创建一个新的分片队列并添加到合适的HASH队列 */
		return inet_frag_create(f, key, hash);
	}
```

