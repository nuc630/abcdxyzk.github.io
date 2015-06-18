---
layout: post
title: "IPV6 实现"
date: 2015-06-18 10:44:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://www.cnblogs.com/super-king/p/ipv6_implement.html

code extract from 2.6.24.
在文件 net/ipv6/af_inet6.c 中包含了ipv6协议初始化的主函数。
```
	static int __init inet6_init(void)
	{
		struct sk_buff *dummy_skb;
		struct list_head *r;
		int err;
		//inet6_skb_parm必须小于等于skb中的cb
		BUILD_BUG_ON(sizeof(struct inet6_skb_parm) > sizeof(dummy_skb->cb));

		//初始化tcpv6_prot结构中的一些与slab相关的字段，然后添加到 proto_list 全局连表
		err = proto_register(&tcpv6_prot, 1);
		if (err)
			goto out;
		//udp协议同上
		err = proto_register(&udpv6_prot, 1);
		if (err)
			goto out_unregister_tcp_proto;
		//udp-lite传输协议，主要用于多媒体传输，参考kernel中的 Documentation/networking/udplite.txt
		err = proto_register(&udplitev6_prot, 1);
		if (err)
			goto out_unregister_udp_proto;
		//原始套接字同上
		err = proto_register(&rawv6_prot, 1);
		if (err)
			goto out_unregister_udplite_proto;

		/* Register the socket-side information for inet6_create.  */
		for(r = &inetsw6[0]; r < &inetsw6[SOCK_MAX]; ++r) //初始化一个协议连表数组
			INIT_LIST_HEAD(r);
		/* We MUST register RAW sockets before we create the ICMP6, IGMP6, or NDISC control sockets. */
		//根据参数数据结构中标识的协议类型，把这数据结构添加到上面的协议连表数组中
		inet6_register_protosw(&rawv6_protosw);

		/* Register the family here so that the init calls below will be able to create sockets. (?? is this dangerous ??) */
		//注册ipv6协议族，主要是注册socket创建函数
		err = sock_register(&inet6_family_ops);
		if (err)
			goto out_unregister_raw_proto;

		/* Initialise ipv6 mibs */
		err = init_ipv6_mibs(); //所有ipv6相关的统计信息
		if (err)
			goto out_unregister_sock;
		/* ipngwg API draft makes clear that the correct semantics for TCP and UDP is to consider one TCP and UDP instance 
		 * in a host availiable by both INET and INET6 APIs and able to communicate via both network protocols.
		 */
	#ifdef CONFIG_SYSCTL
		ipv6_sysctl_register(); // ipv6协议proc条件项初始化
	#endif
		//icmp协议注册
		err = icmpv6_init(&inet6_family_ops);
		if (err)
			goto icmp_fail;
		//邻居协议（arp）初始化       
		err = ndisc_init(&inet6_family_ops);
		if (err)
			goto ndisc_fail;
		//igmp协议初始化       
		err = igmp6_init(&inet6_family_ops);
		if (err)
			goto igmp_fail;
		//ipv6协议相关的 netfilter 初始化     
		err = ipv6_netfilter_init();
		if (err)
			goto netfilter_fail;

		/* Create /proc/foo6 entries. */
	#ifdef CONFIG_PROC_FS //注册/proc/中协议统计输出项
		err = -ENOMEM;
		if (raw6_proc_init())
			goto proc_raw6_fail;
		if (tcp6_proc_init())
			goto proc_tcp6_fail;
		if (udp6_proc_init())
			goto proc_udp6_fail;
		if (udplite6_proc_init())
			goto proc_udplite6_fail;
		if (ipv6_misc_proc_init())
			goto proc_misc6_fail;
		if (ac6_proc_init())
			goto proc_anycast6_fail;
		if (if6_proc_init())
			goto proc_if6_fail;
	#endif
		ip6_route_init(); //ipv6 路由初始化
		ip6_flowlabel_init();//ipv6 中流标记，注册了输出流标记的 proc

		//rtnetlink相关部分和路由模板中一些字段和其他一些功能的初始化
		err = addrconf_init();
		if (err)
			goto addrconf_fail;
		/* Init v6 extension headers. */
		//ipv6 新添加的扩展头初始化，参考ipv6介绍
		ipv6_rthdr_init();
		ipv6_frag_init();
		ipv6_nodata_init();
		ipv6_destopt_init();

		/* Init v6 transport protocols. */
		//最主要的传输层协议初始化
		udpv6_init();
		udplitev6_init();
		tcpv6_init();

		//最后注册ipv6协议，注册协议处理函数
		ipv6_packet_init();
		err = 0;
	out:
		return err;
		...... //下面就是错误处理的过程
	}
```

下面我们主要看ipv6协议部分流程，其他部分在各自相关文章中介绍。

ipv6扩展头，路由包头注册

```
	void __init ipv6_rthdr_init(void)
	{
		if (inet6_add_protocol(&rthdr_protocol, IPPROTO_ROUTING) < 0)
			printk(KERN_ERR "ipv6_rthdr_init: Could not register protocol\n");
	};
```

ipv6扩展头，分片包头注册

```
	void __init ipv6_frag_init(void)
	{
		if (inet6_add_protocol(&frag_protocol, IPPROTO_FRAGMENT) < 0)
			printk(KERN_ERR "ipv6_frag_init: Could not register protocol\n");

		ip6_frags.ctl = &ip6_frags_ctl;
		ip6_frags.hashfn = ip6_hashfn;
		ip6_frags.constructor = ip6_frag_init;
		ip6_frags.destructor = NULL;
		ip6_frags.skb_free = NULL;
		ip6_frags.qsize = sizeof(struct frag_queue);
		ip6_frags.match = ip6_frag_match;
		ip6_frags.frag_expire = ip6_frag_expire;
		inet_frags_init(&ip6_frags);
	}
	void __init ipv6_nodata_init(void)
	{
		if (inet6_add_protocol(&nodata_protocol, IPPROTO_NONE) < 0)
			printk(KERN_ERR "ipv6_nodata_init: Could not register protocol\n");
	}
```

ipv6扩展头，目的选项包头注册

```
	void __init ipv6_destopt_init(void)
	{
		if (inet6_add_protocol(&destopt_protocol, IPPROTO_DSTOPTS) < 0)
			printk(KERN_ERR "ipv6_destopt_init: Could not register protocol\n");
	}
		注册ipv6协议处理函数
	void __init ipv6_packet_init(void)
	{
		dev_add_pack(&ipv6_packet_type);
	}
```

当netif_receive_skb函数向上层递交skb时会根据协议类型调用相关的协议处理函数，那么就会调用到 ipv6_rcv函数了。

```
	static struct packet_type ipv6_packet_type = {
		.type = __constant_htons(ETH_P_IPV6),
		.func = ipv6_rcv,
		.gso_send_check = ipv6_gso_send_check,
		.gso_segment = ipv6_gso_segment,
	};
```

ipv6协议处理函数

```
	int ipv6_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *orig_dev)
	{
		struct ipv6hdr *hdr;
		u32             pkt_len;
		struct inet6_dev *idev;

		if (dev->nd_net != &init_net) {
			kfree_skb(skb);
			return 0;
		}
		//mac地址是其他主机的包
		if (skb->pkt_type == PACKET_OTHERHOST) {
			kfree_skb(skb);
			return 0;
		}
		rcu_read_lock();
		//获取ipv6相关的配置结构
		idev = __in6_dev_get(skb->dev);

		IP6_INC_STATS_BH(idev, IPSTATS_MIB_INRECEIVES);
		//是否共享，如果是，新clone一个
		if ((skb = skb_share_check(skb, GFP_ATOMIC)) == NULL) {
			IP6_INC_STATS_BH(idev, IPSTATS_MIB_INDISCARDS);
			rcu_read_unlock();
			goto out;
		}
		//清空保存扩展头解析结果的数据结构
		memset(IP6CB(skb), 0, sizeof(struct inet6_skb_parm));

		//保存接收这个数据包的设备索引
		IP6CB(skb)->iif = skb->dst ? ip6_dst_idev(skb->dst)->dev->ifindex : dev->ifindex;

		//有足够的头长度，ipv6是40字节
		if (unlikely(!pskb_may_pull(skb, sizeof(*hdr))))
			goto err;

		hdr = ipv6_hdr(skb); //获取头

		if (hdr->version != 6) //验证版本
			goto err;

		//传输头（扩展头）在网络头后面
		skb->transport_header = skb->network_header + sizeof(*hdr);
		//保存下一个扩展头协议在ipv6头结构中的偏移
		IP6CB(skb)->nhoff = offsetof(struct ipv6hdr, nexthdr);
		pkt_len = ntohs(hdr->payload_len); //ipv6负载数据长度

		/* pkt_len may be zero if Jumbo payload option is present */
		if (pkt_len || hdr->nexthdr != NEXTHDR_HOP) { //没有使用扩展头逐个跳段选项
			if (pkt_len + sizeof(struct ipv6hdr) > skb->len) { //数据长度不对
				IP6_INC_STATS_BH(idev, IPSTATS_MIB_INTRUNCATEDPKTS);
				goto drop;
			}
			//如果skb->len > (pkt_len + sizeof(struct ipv6hdr))试着缩小skb->len的长度
			//相对ipv4来说简单多了，自己看吧
			if (pskb_trim_rcsum(skb, pkt_len + sizeof(struct ipv6hdr))) {
				IP6_INC_STATS_BH(idev, IPSTATS_MIB_INHDRERRORS);
				goto drop;
			}
			hdr = ipv6_hdr(skb); //重新获取ip头
		}
		if (hdr->nexthdr == NEXTHDR_HOP) { //使用了扩展头逐个跳段选项
			if (ipv6_parse_hopopts(skb) < 0) {//处理这个选项
				IP6_INC_STATS_BH(idev, IPSTATS_MIB_INHDRERRORS);
				rcu_read_unlock();
				return 0;
			}
		}
		rcu_read_unlock();
		//进入ipv6的netfilter然后调用ip6_rcv_finish
		return NF_HOOK(PF_INET6,NF_IP6_PRE_ROUTING, skb, dev, NULL, ip6_rcv_finish);
	err:
		IP6_INC_STATS_BH(idev, IPSTATS_MIB_INHDRERRORS);
	drop:
		rcu_read_unlock();
		kfree_skb(skb);
	out:
		return 0;
	}
```

解析扩展头逐个跳段中的巨量负载选项

```
	int ipv6_parse_hopopts(struct sk_buff *skb)
	{
		struct inet6_skb_parm *opt = IP6CB(skb); //获取扩展头结果结构
		/* skb_network_header(skb) is equal to skb->data, and skb_network_header_len(skb) is always equal to
		 * sizeof(struct ipv6hdr) by definition of hop-by-hop options.
		 */
		//验证数据有足够的长度
		if (!pskb_may_pull(skb, sizeof(struct ipv6hdr) + 8) || !pskb_may_pull(skb, (sizeof(struct ipv6hdr) +
						//下面的意思是取得扩展首部中的长度
						((skb_transport_header(skb)[1] + 1) << 3)))) {
			kfree_skb(skb);
			return -1;
		}
		opt->hop = sizeof(struct ipv6hdr); //40字节
		if (ip6_parse_tlv(tlvprochopopt_lst, skb)) { //实际的解析工作
			//把传输头移动到扩展首部之后
			skb->transport_header += (skb_transport_header(skb)[1] + 1) << 3;
			opt = IP6CB(skb);
			opt->nhoff = sizeof(struct ipv6hdr); //进行了ipv6扩展头解析，保存下一个扩展头协议字段的偏移
			return 1;
		}
		return -1;
	}
```

解析tlv编码的扩展选项头

```
	static int ip6_parse_tlv(struct tlvtype_proc *procs, struct sk_buff *skb)
	{
		struct tlvtype_proc *curr;
		const unsigned char *nh = skb_network_header(skb); //获取网络头
		int off = skb_network_header_len(skb); //获取网络头长度
		int len = (skb_transport_header(skb)[1] + 1) << 3; //首部扩展头长度

		if (skb_transport_offset(skb) + len > skb_headlen(skb)) //长度错误
			goto bad;
		off += 2; //跳过下一个首部和首部扩展长度这两个字节
		len -= 2;

		while (len > 0) {
			int optlen = nh[off + 1] + 2; //获取选项数据长度 + 2 (2是选项类型和选项数据长度两字节)
			switch (nh[off]) { //选项类型
				case IPV6_TLV_PAD0: //Pad1选项
					optlen = 1;
					break;
				case IPV6_TLV_PADN://PadN选项
					break;
				default: //其他选项
					if (optlen > len)
						goto bad;

					for (curr = procs; curr->type >= 0; curr++) {
						if (curr->type == nh[off]) { //类型匹配，调用参数函数处理，参考下面ipv6选项处理
							/* type specific length/alignment checks will be performed in the func(). */
							if (curr->func(skb, off) == 0)
								return 0;
							break;
						}
					}
					if (curr->type < 0) {
						if (ip6_tlvopt_unknown(skb, off) == 0) //处理未知选项
							return 0;
					}
					break;
			}
			off += optlen; //偏移增加，这样到下一个选项
			len -= optlen; //长度递减
		}
		if (len == 0)
			return 1; //正确解析完毕
	bad:
		kfree_skb(skb);
		return 0;
	}
```

处理未知的选项

```
	static int ip6_tlvopt_unknown(struct sk_buff *skb, int optoff)
	{
		//根据选项类型标识符的要求进行处理
		switch ((skb_network_header(skb)[optoff] & 0xC0) >> 6) {
			case 0: /* ignore */
				return 1;
			case 1: /* drop packet */
				break;
			case 3: /* Send ICMP if not a multicast address and drop packet */
				/* Actually, it is redundant check. icmp_send will recheck in any case. */
				if (ipv6_addr_is_multicast(&ipv6_hdr(skb)->daddr)) //目的是多播地址
					break;
			case 2: /* send ICMP PARM PROB regardless and drop packet */
				//给包的源地址发送一个 ICMP "参数存在问题", 编码 2 的报文, 指针指向无法识别的选项类型
				icmpv6_param_prob(skb, ICMPV6_UNK_OPTION, optoff);
				return 0;
		}
		kfree_skb(skb);
		return 0;
	}
```

到这需要解释一下，上面解析ipv6选项只是解析了第一层的扩展头，在后面可能还有其他扩展头会在后面解析。

```
	inline int ip6_rcv_finish( struct sk_buff *skb)
	{
		if (skb->dst == NULL) //没有路由，进行路由查找
			ip6_route_input(skb); //路由部分将在路由实现文章中介绍

		return dst_input(skb);
	}
	static inline int dst_input(struct sk_buff *skb)
	{
		int err;
		for (;;) {
			err = skb->dst->input(skb); //调用路由的输入函数
			if (likely(err == 0))
				return err;

			/* Oh, Jamal... Seems, I will not forgive you this mess. :-) */
			if (unlikely(err != NET_XMIT_BYPASS))
				return err;
		}
	}
```

现在我们假设包是到本地的，那么上面的input函数就是

```
	int ip6_input(struct sk_buff *skb)
	{
		//进入ipv6 netfilter NF_IP6_LOCAL_IN hook 然后调用 ip6_input_finish
		return NF_HOOK(PF_INET6, NF_IP6_LOCAL_IN, skb, skb->dev, NULL, ip6_input_finish);
	}
	static int ip6_input_finish(struct sk_buff *skb)
	{
		struct inet6_protocol *ipprot;
		struct sock *raw_sk;
		unsigned int nhoff;
		int nexthdr;
		u8 hash;
		struct inet6_dev *idev;

		/* Parse extension headers */
		rcu_read_lock();
	resubmit:
		idev = ip6_dst_idev(skb->dst);
		//将skb->data指针移动到传输层头
		if (!pskb_pull(skb, skb_transport_offset(skb)))
			goto discard;

		nhoff = IP6CB(skb)->nhoff;
		nexthdr = skb_network_header(skb)[nhoff];//下一个扩展头协议

		//处理原始sock
		raw_sk = sk_head(&raw_v6_htable[nexthdr & (MAX_INET_PROTOS - 1)]);
		if (raw_sk && !ipv6_raw_deliver(skb, nexthdr))
			raw_sk = NULL;

		//向上层协议栈递交数据，看初始化时注册的一些协议，主要是tcp，udp等，还包括一些ip扩展头的处理
		hash = nexthdr & (MAX_INET_PROTOS - 1);
		if ((ipprot = rcu_dereference(inet6_protos[hash])) != NULL) {
			int ret;
			if (ipprot->flags & INET6_PROTO_FINAL) {
				struct ipv6hdr *hdr;
				/* Free reference early: we don't need it any more,                        
				   and it may hold ip_conntrack module loaded indefinitely. */
				nf_reset(skb);

				skb_postpull_rcsum(skb, skb_network_header(skb), skb_network_header_len(skb));
				hdr = ipv6_hdr(skb);
				if (ipv6_addr_is_multicast(&hdr->daddr) && !ipv6_chk_mcast_addr(skb->dev, &hdr->daddr, &hdr->saddr)
						&& !ipv6_is_mld(skb, nexthdr))
					goto discard;
			}
			//处理 IPSEC v6 的相关部分
			if (!(ipprot->flags & INET6_PROTO_NOPOLICY) && !xfrm6_policy_check(NULL, XFRM_POLICY_IN, skb))
				goto discard;

			ret = ipprot->handler(skb); //上层协议处理，看下面ipv6扩展头处理
			if (ret > 0)
				goto resubmit; //重新处理
			else if (ret == 0)
				IP6_INC_STATS_BH(idev, IPSTATS_MIB_INDELIVERS);
		} else { //没有找到上层处理函数
			if (!raw_sk) {
				if (xfrm6_policy_check(NULL, XFRM_POLICY_IN, skb)) {
					IP6_INC_STATS_BH(idev, IPSTATS_MIB_INUNKNOWNPROTOS);
					icmpv6_send(skb, ICMPV6_PARAMPROB, ICMPV6_UNK_NEXTHDR, nhoff, skb->dev);
				}
			} else
				IP6_INC_STATS_BH(idev, IPSTATS_MIB_INDELIVERS);
			kfree_skb(skb);
		}
		rcu_read_unlock();
		return 0;
	discard:
		IP6_INC_STATS_BH(idev, IPSTATS_MIB_INDISCARDS);
		rcu_read_unlock();
		kfree_skb(skb);
		return 0;
	}
```

#### ipv6选项处理
```
	static struct tlvtype_proc tlvprochopopt_lst[] = {
		{
			.type   = IPV6_TLV_ROUTERALERT,
			.func   = ipv6_hop_ra,
		},
		{
			.type   = IPV6_TLV_JUMBO,
			.func   = ipv6_hop_jumbo,
		},
		{ -1, }
	};
```

解析路由警告选项

```
	static int ipv6_hop_ra(struct sk_buff *skb, int optoff)
	{
		const unsigned char *nh = skb_network_header(skb); //获取网络头

		if (nh[optoff + 1] == 2) { //路由警告选项长度必须是2 ? rfc 要求是 4
			IP6CB(skb)->ra = optoff; //记录警告类型
			return 1;
		}
		LIMIT_NETDEBUG(KERN_DEBUG "ipv6_hop_ra: wrong RA length %d\n", nh[optoff + 1]);
		kfree_skb(skb);
		return 0;
	}
```

解析jumbo frame选项

```
	static int ipv6_hop_jumbo(struct sk_buff *skb, int optoff)
	{
		const unsigned char *nh = skb_network_header(skb);
		u32 pkt_len;
		//选项数据长度必须是4，选项类型必须是 0xc2， ＆3 后必须是2
		if (nh[optoff + 1] != 4 || (optoff & 3) != 2) {
			LIMIT_NETDEBUG(KERN_DEBUG "ipv6_hop_jumbo: wrong jumbo opt length/alignment %d\n", nh[optoff+1]);
			IP6_INC_STATS_BH(ipv6_skb_idev(skb), IPSTATS_MIB_INHDRERRORS);
			goto drop;
		}
		pkt_len = ntohl(*(__be32 *)(nh + optoff + 2)); //获取整个负载长度
		if (pkt_len <= IPV6_MAXPLEN) { //小于65535 是不对地
			IP6_INC_STATS_BH(ipv6_skb_idev(skb), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, optoff+2);
			return 0;
		}
		if (ipv6_hdr(skb)->payload_len) { //原ipv6头中就不应该有负载长度了
			IP6_INC_STATS_BH(ipv6_skb_idev(skb), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, optoff);
			return 0;
		}
		if (pkt_len > skb->len - sizeof(struct ipv6hdr)) { //长度超出了 skb 的实际长度
			IP6_INC_STATS_BH(ipv6_skb_idev(skb), IPSTATS_MIB_INTRUNCATEDPKTS);
			goto drop;
		}
		//如果必要试图缩减 skb 的长度
		if (pskb_trim_rcsum(skb, pkt_len + sizeof(struct ipv6hdr)))
			goto drop;

		return 1;
	drop:
		kfree_skb(skb);
		return 0;
	}
```

目的选项处理

```
	static struct tlvtype_proc tlvprocdestopt_lst[] = {
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
		{
			.type   = IPV6_TLV_HAO,
			.func   = ipv6_dest_hao,
		},
	#endif
		{-1,    NULL}
	};
```

解析目的选项

```
	static int ipv6_dest_hao(struct sk_buff *skb, int optoff)
	{
		struct ipv6_destopt_hao *hao;
		struct inet6_skb_parm *opt = IP6CB(skb);
		struct ipv6hdr *ipv6h = ipv6_hdr(skb);
		struct in6_addr tmp_addr;
		int ret;

		if (opt->dsthao) { //已经处理
			LIMIT_NETDEBUG(KERN_DEBUG "hao duplicated\n");
			goto discard;
		}
		opt->dsthao = opt->dst1;
		opt->dst1 = 0;

		//获取网络头后面的选项部分
		hao = (struct ipv6_destopt_hao *)(skb_network_header(skb) + optoff);

		if (hao->length != 16) { //长度要求
			LIMIT_NETDEBUG(KERN_DEBUG "hao invalid option length = %d\n", hao->length);
			goto discard;
		}
		if (!(ipv6_addr_type(&hao->addr) & IPV6_ADDR_UNICAST)) { //地址不是单播
			LIMIT_NETDEBUG(KERN_DEBUG "hao is not an unicast addr: " NIP6_FMT "\n", NIP6(hao->addr));
			goto discard;
		}
		//IPSEC相关
		ret = xfrm6_input_addr(skb, (xfrm_address_t *)&ipv6h->daddr, (xfrm_address_t *)&hao->addr, IPPROTO_DSTOPTS);
		if (unlikely(ret < 0))
			goto discard;

		if (skb_cloned(skb)) { //如果包是cloned
			//分配新的内存数据
			if (pskb_expand_head(skb, 0, 0, GFP_ATOMIC))
				goto discard;

			//重新指向各头
			hao = (struct ipv6_destopt_hao *)(skb_network_header(skb) + optoff);
			ipv6h = ipv6_hdr(skb);
		}
		if (skb->ip_summed == CHECKSUM_COMPLETE)
			skb->ip_summed = CHECKSUM_NONE;

		//把ip头中的源地址与选项中的地址交换
		ipv6_addr_copy(&tmp_addr, &ipv6h->saddr);
		ipv6_addr_copy(&ipv6h->saddr, &hao->addr);
		ipv6_addr_copy(&hao->addr, &tmp_addr);

		if (skb->tstamp.tv64 == 0)
			__net_timestamp(skb); //记录时间截

		return 1;
	discard:
		kfree_skb(skb);
		return 0;
	}
```

#### ipv6扩展头处理

我们只介绍根ipv6扩展头相关的实现，像其他的扩展头(tcp, udp)等虽然也是叫扩展头但实际是传输层的内容，将在其他文章中介绍。

路由扩展首部
```
	struct ipv6_rt_hdr {
		__u8            nexthdr;
		__u8            hdrlen;
		__u8            type;
		__u8            segments_left;

		/* type specific data variable length field */
	};
```

路由扩展首部处理结构

```
	static struct inet6_protocol rthdr_protocol = {
		.handler        =       ipv6_rthdr_rcv,
		.flags          =       INET6_PROTO_NOPOLICY | INET6_PROTO_GSO_EXTHDR,
	};
	static int ipv6_rthdr_rcv(struct sk_buff *skb)
	{
		struct inet6_skb_parm *opt = IP6CB(skb);
		struct in6_addr *addr = NULL;
		struct in6_addr daddr;
		struct inet6_dev *idev;
		int n, i;
		struct ipv6_rt_hdr *hdr;
		struct rt0_hdr *rthdr;
		int accept_source_route = ipv6_devconf.accept_source_route;

		idev = in6_dev_get(skb->dev); //包进入设备
		if (idev) {
			if (accept_source_route > idev->cnf.accept_source_route) //默认数量大于了手动调节(proc中）的数量
				accept_source_route = idev->cnf.accept_source_route;
			in6_dev_put(idev);
		}
		//skb长度和内存空间正确
		if (!pskb_may_pull(skb, skb_transport_offset(skb) + 8) || !pskb_may_pull(skb, (skb_transport_offset(skb) +
						((skb_transport_header(skb)[1] + 1) << 3)))) {
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			kfree_skb(skb);
			return -1;
		}
		hdr = (struct ipv6_rt_hdr *)skb_transport_header(skb); //路由扩展头
		//是到多播地址或硬件地址不是到本机的地址
		if (ipv6_addr_is_multicast(&ipv6_hdr(skb)->daddr) || skb->pkt_type != PACKET_HOST) {
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INADDRERRORS);
			kfree_skb(skb);
			return -1;
		}
	looped_back:
		if (hdr->segments_left == 0) { //根据rfc要求 分段剩余为0
			switch (hdr->type) {
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
				case IPV6_SRCRT_TYPE_2:
					/* Silently discard type 2 header unless it was processed by own */
					if (!addr) {
						IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INADDRERRORS);
						kfree_skb(skb);
						return -1;
					}
					break;
	#endif
				default:
					break;

			}
			opt->lastopt = opt->srcrt = skb_network_header_len(skb);
			skb->transport_header += (hdr->hdrlen + 1) << 3; //下一个传输头的位置
			opt->dst0 = opt->dst1;
			opt->dst1 = 0;
			opt->nhoff = (&hdr->nexthdr) - skb_network_header(skb); //记录下一个头数据相对网络头的偏移量
			return 1;
		}
		switch (hdr->type) {
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
			case IPV6_SRCRT_TYPE_2:
				if (accept_source_route < 0)
					goto unknown_rh;
				/* Silently discard invalid RTH type 2 */
				if (hdr->hdrlen != 2 || hdr->segments_left != 1) {
					IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
					kfree_skb(skb);
					return -1;
				}
				break;
	#endif
			default:
				goto unknown_rh;
		}
		/* This is the routing header forwarding algorithm from RFC 2460, page 16. */

		n = hdr->hdrlen >> 1; //计算路由首部中的地址数量
		if (hdr->segments_left > n) {
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, ((&hdr->segments_left) - skb_network_header(skb)));
			return -1;
		}
		/* We are about to mangle packet header. Be careful!                                       
		   Do not damage packets queued somewhere.  */
		if (skb_cloned(skb)) {
			/* the copy is a forwarded packet */
			if (pskb_expand_head(skb, 0, 0, GFP_ATOMIC)) {
				IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_OUTDISCARDS);
				kfree_skb(skb);
				return -1;
			}
			hdr = (struct ipv6_rt_hdr *)skb_transport_header(skb);
		}
		if (skb->ip_summed == CHECKSUM_COMPLETE)
			skb->ip_summed = CHECKSUM_NONE;

		i = n - --hdr->segments_left; //计算地址向量(地址列表)中要"访问"的下一个地址

		rthdr = (struct rt0_hdr *) hdr;
		addr = rthdr->addr; //指向地址列表首部
		addr += i - 1; //移动到下一个地址

		switch (hdr->type) {
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
			case IPV6_SRCRT_TYPE_2:
				if (xfrm6_input_addr(skb, (xfrm_address_t *)addr, (xfrm_address_t *)&ipv6_hdr(skb)->saddr, IPPROTO_ROUTING) < 0) {
					IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INADDRERRORS);
					kfree_skb(skb);
					return -1;
				}
				if (!ipv6_chk_home_addr(addr)) {
					IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INADDRERRORS);
					kfree_skb(skb);
					return -1;
				}
				break;
	#endif
			default:
				break;
		}
		if (ipv6_addr_is_multicast(addr)) { //这个地址是多播地址
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INADDRERRORS);
			kfree_skb(skb);
			return -1;
		}
		//交换 IPv6 目的地址和这个地址
		ipv6_addr_copy(&daddr, addr);
		ipv6_addr_copy(addr, &ipv6_hdr(skb)->daddr);
		ipv6_addr_copy(&ipv6_hdr(skb)->daddr, &daddr);
		dst_release(xchg(&skb->dst, NULL));

		ip6_route_input(skb); //路由查找处理，将在其他文章中介绍

		if (skb->dst->error) {
			skb_push(skb, skb->data - skb_network_header(skb));
			dst_input(skb);
			return -1;
		}

		if (skb->dst->dev->flags & IFF_LOOPBACK) { //路由查找后要发送到的目的设备是回环
			if (ipv6_hdr(skb)->hop_limit <= 1) { //跳数限制小于1
				IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
				//给源地址发送一个 ICMP "超时 – 传输超过跳数限制" 的报文, 并且抛弃此包
				icmpv6_send(skb, ICMPV6_TIME_EXCEED, ICMPV6_EXC_HOPLIMIT, 0, skb->dev);
				kfree_skb(skb);
				return -1;
			}
			ipv6_hdr(skb)->hop_limit--;
			goto looped_back;
		}
		//将data之中移动到网络头
		skb_push(skb, skb->data - skb_network_header(skb));
		dst_input(skb); //这时包应该被转发了
		return -1;
	unknown_rh:
		IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
		icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, (&hdr->type) - skb_network_header(skb));
		return -1;
	}
```

ipv6分配包扩展首部处理

```
	static struct inet6_protocol frag_protocol =
	{
		.handler        =       ipv6_frag_rcv,
		.flags          =       INET6_PROTO_NOPOLICY,
	};
	static int ipv6_frag_rcv(struct sk_buff *skb)
	{
		struct frag_hdr *fhdr;
		struct frag_queue *fq;
		struct ipv6hdr *hdr = ipv6_hdr(skb);

		IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_REASMREQDS);

		/* Jumbo payload inhibits frag. header */
		if (hdr->payload_len == 0) { //是Jumbo payload，不是分片包
			IP6_INC_STATS(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, skb_network_header_len(skb));
			return -1;
		}
		//有碎片头空间
		if (!pskb_may_pull(skb, (skb_transport_offset(skb) + sizeof(struct frag_hdr)))) {
			IP6_INC_STATS(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, skb_network_header_len(skb));
			return -1;
		}
		hdr = ipv6_hdr(skb);
		fhdr = (struct frag_hdr *)skb_transport_header(skb); //分片头

		if (!(fhdr->frag_off & htons(0xFFF9))) { //没有分片偏移，不是分片包
			/* It is not a fragmented frame */
			skb->transport_header += sizeof(struct frag_hdr); //传输头向后移动到下一个头
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_REASMOKS);
			IP6CB(skb)->nhoff = (u8 *)fhdr - skb_network_header(skb);
			return 1;
		}
		if (atomic_read(&ip6_frags.mem) > ip6_frags_ctl.high_thresh) //内存使用超过限制
			ip6_evictor(ip6_dst_idev(skb->dst));

		//查找或创建分片队列头
		if ((fq = fq_find(fhdr->identification, &hdr->saddr, &hdr->daddr, ip6_dst_idev(skb->dst))) != NULL) {
			int ret;
			spin_lock(&fq->q.lock);
			ret = ip6_frag_queue(fq, skb, fhdr, IP6CB(skb)->nhoff); //入队重组
			spin_unlock(&fq->q.lock);
			fq_put(fq);
			return ret;
		}
		IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_REASMFAILS);
		kfree_skb(skb);
		return -1;
	}
	static __inline__ struct frag_queue * fq_find(__be32 id, struct in6_addr *src, struct in6_addr *dst, struct inet6_dev *idev)
	{
		struct inet_frag_queue *q;
		struct ip6_create_arg arg;
		unsigned int hash;

		arg.id = id;
		arg.src = src;
		arg.dst = dst;
		hash = ip6qhashfn(id, src, dst); //id，源，目的进行 hash

		q = inet_frag_find(&ip6_frags, &arg, hash); //查找或创建
		if (q == NULL)
			goto oom;

		return container_of(q, struct frag_queue, q); //成功返回
	oom: //没内存了
		IP6_INC_STATS_BH(idev, IPSTATS_MIB_REASMFAILS);
		return NULL;
	}
	struct inet_frag_queue *inet_frag_find(struct inet_frags *f, void *key, unsigned int hash)
	{
		struct inet_frag_queue *q;
		struct hlist_node *n;

		read_lock(&f->lock);
		hlist_for_each_entry(q, n, &f->hash[hash], list) { //在hash桶中查找

			if (f->match(q, key)) { //调用匹配函数进行匹配，具体函数很简单参考初始化时的ipv6_frag_init函数
				atomic_inc(&q->refcnt);
				read_unlock(&f->lock);
				return q;
			}
		}
		//没有找到就创建一个
		return inet_frag_create(f, key, hash);
	}
```

创建分片队列

```
	static struct inet_frag_queue *inet_frag_create(struct inet_frags *f, void *arg, unsigned int hash)
	{
		struct inet_frag_queue *q;

		q = inet_frag_alloc(f, arg); //分配一个
		if (q == NULL)
			return NULL;
		//添加到 hash 表
		return inet_frag_intern(q, f, hash, arg);
	}
	static struct inet_frag_queue *inet_frag_alloc(struct inet_frags *f, void *arg)
	{
		struct inet_frag_queue *q;

		q = kzalloc(f->qsize, GFP_ATOMIC); //分配一个队列头，大小是 sizeof(struct frag_queue)
		if (q == NULL)
			return NULL;

		f->constructor(q, arg); //拷贝地址和 id 到队列头结构中
		atomic_add(f->qsize, &f->mem);
		setup_timer(&q->timer, f->frag_expire, (unsigned long)q);
		spin_lock_init(&q->lock);
		atomic_set(&q->refcnt, 1);
		return q;
	}
	static struct inet_frag_queue *inet_frag_intern(struct inet_frag_queue *qp_in, struct inet_frags *f, unsigned int hash, void *arg)
	{
		struct inet_frag_queue *qp;
	#ifdef CONFIG_SMP
		struct hlist_node *n;
	#endif

		write_lock(&f->lock);
	#ifdef CONFIG_SMP
		//其他cpu可能已经创建了一个，所以要再次检查
		hlist_for_each_entry(qp, n, &f->hash[hash], list) {
			if (f->match(qp, arg)) { //已经创建
				atomic_inc(&qp->refcnt);
				write_unlock(&f->lock);
				qp_in->last_in |= COMPLETE;
				inet_frag_put(qp_in, f); //释放新分配的
				return qp;

			}
		}
	#endif
		qp = qp_in;
		if (!mod_timer(&qp->timer, jiffies + f->ctl->timeout)) //启动定时器
			atomic_inc(&qp->refcnt);

		//增加引用计数，然后添加到hash表
		atomic_inc(&qp->refcnt);
		hlist_add_head(&qp->list, &f->hash[hash]);
		list_add_tail(&qp->lru_list, &f->lru_list);
		f->nqueues++;
		write_unlock(&f->lock);
		return qp;
	}
```

入队重组

```
	static int ip6_frag_queue(struct frag_queue *fq, struct sk_buff *skb, struct frag_hdr *fhdr, int nhoff)
	{
		struct sk_buff *prev, *next;
		struct net_device *dev;
		int offset, end;

		if (fq->q.last_in & COMPLETE) //重组已经完成
			goto err;

		//分片开始位置
		offset = ntohs(fhdr->frag_off) & ~0x7;//偏移必须8字节对齐
		//分片在整个包中的结束位置 包负载长度 - 分片头长度
		end = offset + (ntohs(ipv6_hdr(skb)->payload_len) -  ((u8 *)(fhdr + 1) - (u8 *)(ipv6_hdr(skb) + 1)));

		//结束位置 > 65535
		if ((unsigned int)end > IPV6_MAXPLEN) {
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, ((u8 *)&fhdr->frag_off - skb_network_header(skb)));
			return -1;
		}
		//校验和已经完成
		if (skb->ip_summed == CHECKSUM_COMPLETE) {
			const unsigned char *nh = skb_network_header(skb);
			//减去分片包头的校验和
			skb->csum = csum_sub(skb->csum, csum_partial(nh, (u8 *)(fhdr + 1) - nh, 0));
		}
		//最后一个碎片包
		if (!(fhdr->frag_off & htons(IP6_MF))) {
			/* If we already have some bits beyond end or have different end, the segment is corrupted. */
			if (end < fq->q.len || ((fq->q.last_in & LAST_IN) && end != fq->q.len)) //分片出现错误
				goto err;

			fq->q.last_in |= LAST_IN; //标识最后一个分片
			fq->q.len = end; //记录包总长度
		} else {
			/* Check if the fragment is rounded to 8 bytes. Required by the RFC. */
			if (end & 0x7) { //碎片结尾也需要8字节对齐
				/* RFC2460 says always send parameter problem in this case. -DaveM */
				IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), PSTATS_MIB_INHDRERRORS);
				icmpv6_param_prob(skb, ICMPV6_HDR_FIELD, offsetof(struct ipv6hdr, payload_len));
				return -1;
			}
			if (end > fq->q.len) {
				/* Some bits beyond end -> corruption. */
				if (fq->q.last_in & LAST_IN)
					goto err;
				fq->q.len = end; //记录已经得到的碎片的最大长度
			}
		}
		if (end == offset) //开始 = 结束
			goto err;

		//skb->data 指向碎片首部头后数据部分
		if (!pskb_pull(skb, (u8 *) (fhdr + 1) - skb->data))
			goto err;
		//如果需要缩短skb的内存长度
		if (pskb_trim_rcsum(skb, end - offset))
			goto err;

		//找出碎片所在位置
		prev = NULL;
		for(next = fq->q.fragments; next != NULL; next = next->next) {
			if (FRAG6_CB(next)->offset >= offset)
				break;  /* bingo! */
			prev = next;
		}
		if (prev) { //有前一个碎片
			//前一个碎片 (开始 + 长度) - 这个碎片的开始. 计算出重叠部分
			int i = (FRAG6_CB(prev)->offset + prev->len) - offset;
			if (i > 0) { //有重叠
				offset += i; //调整这个碎片的开始位置
				if (end <= offset) //调整后出错
					goto err;
				if (!pskb_pull(skb, i))//skb->data += i;
					goto err;
				if (skb->ip_summed != CHECKSUM_UNNECESSARY)
					skb->ip_summed = CHECKSUM_NONE;
			}
		}
		//有下一个碎片，且开始位置 < 这个碎片的结束位置
		while (next && FRAG6_CB(next)->offset < end) {
			//这个碎片的结束位置  - 下一个碎片的开始位置，计算重叠
			int i = end - FRAG6_CB(next)->offset; /* overlap is 'i' bytes */
			if (i < next->len) { //重叠长度 < 下一个碎片的长度
				if (!pskb_pull(next, i)) //next->data += i;
					goto err;

				FRAG6_CB(next)->offset += i;    //下一个碎片开始位置调整
				fq->q.meat -= i; //总长度减少
				if (next->ip_summed != CHECKSUM_UNNECESSARY)
					next->ip_summed = CHECKSUM_NONE;
				break;

			} else { //这个碎片完全复盖了下一个碎片
				struct sk_buff *free_it = next; //释放这个碎片
				next = next->next;//调整下一个碎片指针
				//调整队列指针
				if (prev)
					prev->next = next;
				else
					fq->q.fragments = next;

				fq->q.meat -= free_it->len;
				frag_kfree_skb(free_it, NULL); //释放被复盖的包
			}
		}
		FRAG6_CB(skb)->offset = offset; //这个碎片包记录自己的开始位置

		//插入这个碎片到队列
		skb->next = next;
		if (prev)
			prev->next = skb;
		else
			fq->q.fragments = skb;

		dev = skb->dev;
		if (dev) {
			fq->iif = dev->ifindex;
			skb->dev = NULL;
		}
		fq->q.stamp = skb->tstamp;
		fq->q.meat += skb->len; //累加总长度
		atomic_add(skb->truesize, &ip6_frags.mem);

		if (offset == 0) { //偏移为0
			fq->nhoffset = nhoff;
			fq->q.last_in |= FIRST_IN; //标识开始碎片
		}
		//碎片已经聚齐，记录长度 = 包中标识的长度
		if (fq->q.last_in == (FIRST_IN | LAST_IN) && fq->q.meat == fq->q.len)
			return ip6_frag_reasm(fq, prev, dev); //重组
		//没有聚齐，移动队列连表到lru连表尾部
		write_lock(&ip6_frags.lock);
		list_move_tail(&fq->q.lru_list, &ip6_frags.lru_list);
		write_unlock(&ip6_frags.lock);
		return -1;
	err:
		IP6_INC_STATS(ip6_dst_idev(skb->dst), IPSTATS_MIB_REASMFAILS);
		kfree_skb(skb);
		return -1;
	}
```

重组ip头

```
	static int ip6_frag_reasm(struct frag_queue *fq, struct sk_buff *prev, struct net_device *dev)
	{
		struct sk_buff *fp, *head = fq->q.fragments;
		int    payload_len;
		unsigned int nhoff;

		fq_kill(fq); //把这个重组队列出队

		/* Make the one we just received the head. */
		if (prev) {
			//下面是把head指向的skb复制到fp，然后把fp插入到head指向的位置
			head = prev->next;
			fp = skb_clone(head, GFP_ATOMIC);

			if (!fp)
				goto out_oom;


			fp->next = head->next;
			prev->next = fp;
			//把真正的头skb复制到head指针的skb
			skb_morph(head, fq->q.fragments);
			head->next = fq->q.fragments->next;

			kfree_skb(fq->q.fragments);//释放原来的头
			fq->q.fragments = head;
		}
		/* Unfragmented part is taken from the first segment. */
		//计算负载总长度
		payload_len = ((head->data - skb_network_header(head)) - sizeof(struct ipv6hdr) + fq->q.len -  sizeof(struct frag_hdr));
		if (payload_len > IPV6_MAXPLEN) //超过65535
			goto out_oversize;

		/* Head of list must not be cloned. */
		//如果skb被克隆，从新分配他的data
		if (skb_cloned(head) && pskb_expand_head(head, 0, 0, GFP_ATOMIC))
			goto out_oom;

		/* If the first fragment is fragmented itself, we split it to two chunks: the first with data and paged part
		 * and the second, holding only fragments.
		 */
		if (skb_shinfo(head)->frag_list) {//如果头自己已经被分片
			struct sk_buff *clone;
			int i, plen = 0;

			if ((clone = alloc_skb(0, GFP_ATOMIC)) == NULL)
				goto out_oom;

			//把这个clone插入到头后               
			clone->next = head->next;
			head->next = clone;
			//把头的分片给这个clone
			skb_shinfo(clone)->frag_list = skb_shinfo(head)->frag_list;
			skb_shinfo(head)->frag_list = NULL;
			//头使用了页面，计算总长度
			for (i = 0; i < skb_shinfo(head)->nr_frags; i++)
				plen += skb_shinfo(head)->frags[i].size;

			clone->len = clone->data_len = head->data_len - plen;
			head->data_len -= clone->len;
			head->len -= clone->len;
			clone->csum = 0;
			clone->ip_summed = head->ip_summed;
			atomic_add(clone->truesize, &ip6_frags.mem);
		}
		/* We have to remove fragment header from datagram and to relocate                         
		 * header in order to calculate ICV correctly. */
		nhoff = fq->nhoffset;
		//把传输头（分片头）中的下一个头字段值赋给网络头中的下一个头字段
		skb_network_header(head)[nhoff] = skb_transport_header(head)[0];
		//把分片首部复盖掉
		memmove(head->head + sizeof(struct frag_hdr), head->head, (head->data - head->head) - sizeof(struct frag_hdr));
		//调整相应的各个层的头位置
		head->mac_header += sizeof(struct frag_hdr);
		head->network_header += sizeof(struct frag_hdr);

		skb_shinfo(head)->frag_list = head->next; //保存碎片连表
		skb_reset_transport_header(head);//重新调整网络头，现在指向分片头后的头
		skb_push(head, head->data - skb_network_header(head));//使head->data指向网络头
		atomic_sub(head->truesize, &ip6_frags.mem);

		for (fp = head->next; fp; fp = fp->next) { //统计分片总长度
			head->data_len += fp->len;
			head->len += fp->len;
			if (head->ip_summed != fp->ip_summed)
				head->ip_summed = CHECKSUM_NONE;
			else if (head->ip_summed == CHECKSUM_COMPLETE)
				head->csum = csum_add(head->csum, fp->csum); //添加各分片的累加和

			head->truesize += fp->truesize;
			atomic_sub(fp->truesize, &ip6_frags.mem);
		}
		head->next = NULL;
		head->dev = dev;
		head->tstamp = fq->q.stamp;
		ipv6_hdr(head)->payload_len = htons(payload_len); //总长度
		IP6CB(head)->nhoff = nhoff;

		/* Yes, and fold redundant checksum back. 8) */
		if (head->ip_summed == CHECKSUM_COMPLETE) //添加网络头累加和
			head->csum = csum_partial(skb_network_header(head), skb_network_header_len(head), head->csum);

		rcu_read_lock();
		IP6_INC_STATS_BH(__in6_dev_get(dev), IPSTATS_MIB_REASMOKS);
		rcu_read_unlock();
		fq->q.fragments = NULL;
		return 1;
		...... //下面是错误处理
	}
```

#### 无数据扩展头
```
	static struct inet6_protocol nodata_protocol = {
		.handler        =       ipv6_nodata_rcv,
		.flags          =       INET6_PROTO_NOPOLICY,
	};
	static int ipv6_nodata_rcv(struct sk_buff *skb)
	{
		kfree_skb(skb);
		return 0;
	}
```

#### 目的选项首部处理
```
	static struct inet6_protocol destopt_protocol = {
		.handler        =       ipv6_destopt_rcv,
		.flags          =       INET6_PROTO_NOPOLICY | INET6_PROTO_GSO_EXTHDR,
	};
	static int ipv6_destopt_rcv(struct sk_buff *skb)
	{
		struct inet6_skb_parm *opt = IP6CB(skb);
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
		__u16 dstbuf;
	#endif
		struct dst_entry *dst;
		//长度验证
		if (!pskb_may_pull(skb, skb_transport_offset(skb) + 8) || !pskb_may_pull(skb, (skb_transport_offset(skb) +
						((skb_transport_header(skb)[1] + 1) << 3)))) {
			IP6_INC_STATS_BH(ip6_dst_idev(skb->dst), IPSTATS_MIB_INHDRERRORS);
			kfree_skb(skb);
			return -1;
		}
		opt->lastopt = opt->dst1 = skb_network_header_len(skb); //网络头长度
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
		dstbuf = opt->dst1;
	#endif
		dst = dst_clone(skb->dst); //增加dst的引用计数
		//解析tlv，上面已经看到过了
		if (ip6_parse_tlv(tlvprocdestopt_lst, skb)) {
			dst_release(dst);
			skb->transport_header += (skb_transport_header(skb)[1] + 1) << 3; //调整网络头位置
			opt = IP6CB(skb);
	#if defined(CONFIG_IPV6_MIP6) || defined(CONFIG_IPV6_MIP6_MODULE)
			opt->nhoff = dstbuf;
	#else
			opt->nhoff = opt->dst1;
	#endif
			return 1;
		}
		IP6_INC_STATS_BH(ip6_dst_idev(dst), IPSTATS_MIB_INHDRERRORS);
		dst_release(dst);
		return -1;
	}
```

