---
layout: post
title: "TCP的TSO/GSO处理（二）"
date: 2015-03-27 17:45:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://book.51cto.com/art/201206/345021.htm

有些网络设备硬件可以完成一些传统上由CPU完成的任务，最常见的例子就是计算三层和四层校验和。有些网络设备甚至可以维护四层协议的状态机，由硬件完成分段或分片，因此传输层通过网络层提交给网络设备时可能是个GSO段，参见1.3.1节。本节论述SKB的成员都是用来支持GSO的。
```
	unsigned short gso_size 
```
生成GSO段时的MSS，因为GSO段的长度是与发送该段的套接口中合适MSS的整数倍。
```
	unsigned short gso_segs 
```
GSO段的长度是gso_size的倍数，即用gso_size来分割大段时产生的段数。
```
	unsigned short gso_type 
```
该SKB中的数据支持的GSO类型，见表3-5。

表3-5  gso_type的取值

gso_type            描述  
SKB_GSO_TCPV4   IPv4的TCP段卸载  
SKB_GSO_UDP     IPv4的UDP分片卸载  
SKB_GSO_DODGY   表明数据报是从一个不可信赖的来源发出的  
SKB_GSO_TCP_ECN IPv4的TCP段卸载，当设置TCP首部的CWR时，使用此gos_type。CWR参见29.4节  
SKB_GSO_TCPV6   IPv6的TCP段卸载  

-----------------

http://blog.csdn.net/majieyue/article/details/11881325

GSO用来扩展之前的TSO，目前已经并入upstream内核。TSO只能支持tcp协议，而GSO可以支持tcpv4, tcpv6, udp等协议。在GSO之前，skb_shinfo(skb)有两个成员ufo_size, tso_size，分别表示udp fragmentation offloading支持的分片长度，以及tcp segmentation offloading支持的分段长度，现在都用skb_shinfo(skb)->gso_size代替。skb_shinfo(skb)->ufo_segs, skb_shinfo(skb)->tso_segs也被替换成了skb_shinfo(skb)->gso_segs，表示分片的个数。

skb_shinfo(skb)->gso_type包括SKB_GSO_TCPv4, SKB_GSO_UDPv4，同时NETIF_F_XXX的标志也增加了相应的bit，标识设备是否支持TSO, GSO, e.g. 
```
	NETIF_F_TSO = SKB_GSO_TCPV4 << NETIF_F_GSO_SHIFT
	NETIF_F_UFO = SKB_GSO_UDPV4 << NETIF_F_GSO_SHIFT
	#define NETIF_F_GSO_SHIFT 16
```
dev_hard_start_xmit在调用设备驱动的发送函数之前，会通过netif_needs_gso判断是否需要软件做GSO，如果需要，那么会调用到dev_gso_segment

```
	/**
	 *  dev_gso_segment - Perform emulated hardware segmentation on skb.
	 *  @skb: buffer to segment
	 *
	 *  This function segments the given skb and stores the list of segments
	 *  in skb->next.
	 */
	static int dev_gso_segment(struct sk_buff *skb)
	{
		struct net_device *dev = skb->dev;
		struct sk_buff *segs;
		int features = dev->features & ~(illegal_highdma(dev, skb) ?
		                 NETIF_F_SG : 0);

		segs = skb_gso_segment(skb, features);

		/* Verifying header integrity only. */
		if (!segs)
		    return 0;

		if (IS_ERR(segs))
		    return PTR_ERR(segs);

		skb->next = segs;
		DEV_GSO_CB(skb)->destructor = skb->destructor;
		skb->destructor = dev_gso_skb_destructor;

		return 0;
	}
```

分析skb_gso_segment之前，看下析构过程，此时skb经过分片之后已经是一个skb list，通过skb->next串在一起，此时把初始的skb->destructor函数存到skb->cb中，然后把skb->destructor变更为dev_gso_skb_destructor。

dev_gso_skb_destructor会把skb->next一个个通过kfree_skb释放掉，最后调用DEV_GSO_CB(skb)->destructor，即skb初始的析构函数做最后的清理。

skb_gso_segment是通过软件方式模拟网卡分段的函数。

```
	struct sk_buff *skb_gso_segment(struct sk_buff *skb, int features)
	{
		struct sk_buff *segs = ERR_PTR(-EPROTONOSUPPORT);
		struct packet_type *ptype;
		__be16 type = skb->protocol;
		int err;

		skb_reset_mac_header(skb);
		skb->mac_len = skb->network_header - skb->mac_header;
		__skb_pull(skb, skb->mac_len);

		if (unlikely(skb->ip_summed != CHECKSUM_PARTIAL)) {
		    struct net_device *dev = skb->dev;
		    struct ethtool_drvinfo info = {};

		    if (dev && dev->ethtool_ops && dev->ethtool_ops->get_drvinfo)
		        dev->ethtool_ops->get_drvinfo(dev, &info);

		    WARN(1, "%s: caps=(0x%lx, 0x%lx) len=%d data_len=%d "
		        "ip_summed=%d",
		         info.driver, dev ? dev->features : 0L,
		         skb->sk ? skb->sk->sk_route_caps : 0L,
		         skb->len, skb->data_len, skb->ip_summed);

		    if (skb_header_cloned(skb) &&
		        (err = pskb_expand_head(skb, 0, 0, GFP_ATOMIC)))
		        return ERR_PTR(err);

	如果skb header是clone，分离出来
		}

	如果skb->ip_summed 不是 CHECKSUM_PARTIAL，那么报个warning，因为GSO类型的skb其ip_summed一般都是CHECKSUM_PARTIAL

		rcu_read_lock();
		list_for_each_entry_rcu(ptype,
		        &ptype_base[ntohs(type) & PTYPE_HASH_MASK], list) {
		    if (ptype->type == type && !ptype->dev && ptype->gso_segment) {
		        if (unlikely(skb->ip_summed != CHECKSUM_PARTIAL)) {
		            err = ptype->gso_send_check(skb);
		            segs = ERR_PTR(err);
		            if (err || skb_gso_ok(skb, features))
		                break;
		            __skb_push(skb, (skb->data -
		                     skb_network_header(skb)));
		        }
		        segs = ptype->gso_segment(skb, features);
		        break;

	把skb->data指向network header，然后调用inet_gso_segment，四层的gso_segment会在inet_gso_segment中被调用
		    }
		}
		rcu_read_unlock();

		__skb_push(skb, skb->data - skb_mac_header(skb));

	把skb->data再次指向mac header

		return segs;
	}


	static struct sk_buff *inet_gso_segment(struct sk_buff *skb, int features)
	{
		struct sk_buff *segs = ERR_PTR(-EINVAL);
		struct iphdr *iph;
		const struct net_protocol *ops;
		int proto;
		int ihl;
		int id;
		unsigned int offset = 0;

		if (!(features & NETIF_F_V4_CSUM))
		    features &= ~NETIF_F_SG;
	如果设备不支持NETIF_F_V4_CSUM，那么就当设备不支持SG

		if (unlikely(skb_shinfo(skb)->gso_type &
		         ~(SKB_GSO_TCPV4 |
		           SKB_GSO_UDP |
		           SKB_GSO_DODGY |
		           SKB_GSO_TCP_ECN |
		           0)))
		    goto out;
	gso_type不合法，直接返错

		if (unlikely(!pskb_may_pull(skb, sizeof(*iph))))
		    goto out;
	20字节ip头部无法获得，返错

		iph = ip_hdr(skb);
		ihl = iph->ihl * 4;
		if (ihl < sizeof(*iph))
		    goto out;

		if (unlikely(!pskb_may_pull(skb, ihl)))
		    goto out;
	实际ip头部无法获得，返错

		__skb_pull(skb, ihl);
		skb_reset_transport_header(skb);
		iph = ip_hdr(skb);

	OK，现在拿到ip头部了


		id = ntohs(iph->id);

	ip包的id


		proto = iph->protocol & (MAX_INET_PROTOS - 1);
		segs = ERR_PTR(-EPROTONOSUPPORT);

		rcu_read_lock();
		ops = rcu_dereference(inet_protos[proto]);
		if (likely(ops && ops->gso_segment))
		    segs = ops->gso_segment(skb, features);

	如果是tcp，那么调用tcp_tso_segment，如果是udp，那么调用udp4_ufo_fragment


		rcu_read_unlock();

		if (!segs || IS_ERR(segs))
		    goto out;

		skb = segs;
		do {
		    iph = ip_hdr(skb);
		    if (proto == IPPROTO_UDP) {
		        iph->id = htons(id);
		        iph->frag_off = htons(offset >> 3);
		        if (skb->next != NULL)
		            iph->frag_off |= htons(IP_MF);
		        offset += (skb->len - skb->mac_len - iph->ihl * 4);
		    } else
		        iph->id = htons(id++);
		    iph->tot_len = htons(skb->len - skb->mac_len);
		    iph->check = 0;
		    iph->check = ip_fast_csum(skb_network_header(skb), iph->ihl);
		} while ((skb = skb->next));

	对每一个skb segment，填充ip包头，计算ip checksum。如果是tcp segmentation，那么ip头的id递增。如果是udp fragmentation，那么ip头的id不变，每次计算增加的offset，等于是在做ip分片

	out:
		return segs;
	}
```

下面来看TCP协议的分段函数tcp_tso_segment

```
	struct sk_buff *tcp_tso_segment(struct sk_buff *skb, int features)
	{
		struct sk_buff *segs = ERR_PTR(-EINVAL);
		struct tcphdr *th;
		unsigned thlen;
		unsigned int seq;
		__be32 delta;
		unsigned int oldlen;
		unsigned int mss;

		if (!pskb_may_pull(skb, sizeof(*th)))
		    goto out;

		th = tcp_hdr(skb);
		thlen = th->doff * 4;
		if (thlen < sizeof(*th))
		    goto out;

		if (!pskb_may_pull(skb, thlen))
		    goto out;

		oldlen = (u16)~skb->len;
		__skb_pull(skb, thlen);
	把tcp header移到skb header里，把skb->len存到oldlen中，此时skb->len就只有tcp payload的长度

		mss = skb_shinfo(skb)->gso_size;
		if (unlikely(skb->len <= mss))
		    goto out;

		if (skb_gso_ok(skb, features | NETIF_F_GSO_ROBUST)) {
		    /* Packet is from an untrusted source, reset gso_segs. */
		    int type = skb_shinfo(skb)->gso_type;

		    if (unlikely(type &
		             ~(SKB_GSO_TCPV4 |
		               SKB_GSO_DODGY |
		               SKB_GSO_TCP_ECN |
		               SKB_GSO_TCPV6 |
		               0) ||
		             !(type & (SKB_GSO_TCPV4 | SKB_GSO_TCPV6))))
		        goto out;

		    skb_shinfo(skb)->gso_segs = DIV_ROUND_UP(skb->len, mss);
	重新计算skb_shinfo(skb)->gso_segs的个数，基于skb->len和mss值

		    segs = NULL;
		    goto out;
		}


		segs = skb_segment(skb, features);
		if (IS_ERR(segs))
		    goto out;
	skb_segment是真正的分段实现，后面再分析

		delta = htonl(oldlen + (thlen + mss));

		skb = segs;
		th = tcp_hdr(skb);
		seq = ntohl(th->seq);

		do {
		    th->fin = th->psh = 0;

		    th->check = ~csum_fold((__force __wsum)((__force u32)th->check +
		                   (__force u32)delta));
		    if (skb->ip_summed != CHECKSUM_PARTIAL)
		        th->check =
		             csum_fold(csum_partial(skb_transport_header(skb),
		                        thlen, skb->csum));
	对每个分段都要计算tcp checksum

		    seq += mss;
		    skb = skb->next;
		    th = tcp_hdr(skb);

		    th->seq = htonl(seq);

	对每个分段重新计算sequence值


		    th->cwr = 0;
		} while (skb->next);

		delta = htonl(oldlen + (skb->tail - skb->transport_header) +
		          skb->data_len);
		th->check = ~csum_fold((__force __wsum)((__force u32)th->check +
		            (__force u32)delta));
		if (skb->ip_summed != CHECKSUM_PARTIAL)
		    th->check = csum_fold(csum_partial(skb_transport_header(skb),
		                       thlen, skb->csum));

	out:
		return segs;
	}
```

UDP协议的分片函数是udp4_ufo_fragment

```
	struct sk_buff *udp4_ufo_fragment(struct sk_buff *skb, int features)
	{
		struct sk_buff *segs = ERR_PTR(-EINVAL);
		unsigned int mss;
		int offset;
		__wsum csum;

		mss = skb_shinfo(skb)->gso_size;
		if (unlikely(skb->len <= mss))
		    goto out;

		if (skb_gso_ok(skb, features | NETIF_F_GSO_ROBUST)) {
		    /* Packet is from an untrusted source, reset gso_segs. */
		    int type = skb_shinfo(skb)->gso_type;

		    if (unlikely(type & ~(SKB_GSO_UDP | SKB_GSO_DODGY) ||
		             !(type & (SKB_GSO_UDP))))
		        goto out;

		    skb_shinfo(skb)->gso_segs = DIV_ROUND_UP(skb->len, mss);

		    segs = NULL;
		    goto out;
		}

		/* Do software UFO. Complete and fill in the UDP checksum as HW cannot
		 * do checksum of UDP packets sent as multiple IP fragments.
		 */
		offset = skb->csum_start - skb_headroom(skb);
		csum = skb_checksum(skb, offset, skb->len - offset, 0);
		offset += skb->csum_offset;
		*(__sum16 *)(skb->data + offset) = csum_fold(csum);
		skb->ip_summed = CHECKSUM_NONE;

	计算udp的checksum

		/* Fragment the skb. IP headers of the fragments are updated in
		 * inet_gso_segment()
		 */
		segs = skb_segment(skb, features);
	out:
		return segs;
	}
```

udp的分段其实和ip的分片没什么区别，只是多一个计算checksum的步骤

最后来分析下skb_segment

```
	struct sk_buff *skb_segment(struct sk_buff *skb, int features)
	{
		struct sk_buff *segs = NULL;
		struct sk_buff *tail = NULL;
		struct sk_buff *fskb = skb_shinfo(skb)->frag_list;
		unsigned int mss = skb_shinfo(skb)->gso_size;
		unsigned int doffset = skb->data - skb_mac_header(skb);
		unsigned int offset = doffset;
		unsigned int headroom;
		unsigned int len;
		int sg = features & NETIF_F_SG;
		int nfrags = skb_shinfo(skb)->nr_frags;
		int err = -ENOMEM;
		int i = 0;
		int pos;

		__skb_push(skb, doffset);
		headroom = skb_headroom(skb);
		pos = skb_headlen(skb);

	skb->data指向mac header，计算headroom，skb_headlen长度

		do {
		    struct sk_buff *nskb;
		    skb_frag_t *frag;
		    int hsize;
		    int size;

		    len = skb->len - offset;
		    if (len > mss)
		        len = mss;
	len为skb->len减去直到offset的部分。开始时，offset只是mac header + ip header + tcp header的长度，len即tcp payload的长度。随着segment增加, offset每次都增加mss长度。因此len的定义是每个segment的payload长度（最后一个segment的payload可能小于一个mss长度）

		    hsize = skb_headlen(skb) - offset;

	hsize为skb header减去offset后的大小，如果hsize小于0，那么说明payload在skb的frags, frag_list中。随着offset一直增长，必定会有hsize一直<0的情况开始出现，除非skb是一个完全linearize化的skb


		    if (hsize < 0)
		        hsize = 0;

	这种情况说明skb_headlen没有tcp payload的部分，需要pull数据过来


		    if (hsize > len || !sg)
		        hsize = len;

	如果不支持sg同时hsize大于len，那么hsize就为len，此时说明segment的payload还在skb header中


		    if (!hsize && i >= nfrags) {
		        BUG_ON(fskb->len != len);

		        pos += len;
		        nskb = skb_clone(fskb, GFP_ATOMIC);
		        fskb = fskb->next;

		        if (unlikely(!nskb))
		            goto err;

		        hsize = skb_end_pointer(nskb) - nskb->head;
		        if (skb_cow_head(nskb, doffset + headroom)) {
		            kfree_skb(nskb);
		            goto err;
		        }

		        nskb->truesize += skb_end_pointer(nskb) - nskb->head -
		                  hsize;
		        skb_release_head_state(nskb);
		        __skb_push(nskb, doffset);
		    } else {

		        nskb = alloc_skb(hsize + doffset + headroom,
		                 GFP_ATOMIC);

		        if (unlikely(!nskb))
		            goto err;

		        skb_reserve(nskb, headroom);
		        __skb_put(nskb, doffset);

	alloc新的skb，skb->data到skb->head之间保留headroom，skb->tail到skb->data之间保留mac header + ip header + tcp header + hsize的长度


		    }

		    if (segs)
		        tail->next = nskb;
		    else
		        segs = nskb;
		    tail = nskb;


		    __copy_skb_header(nskb, skb);
		    nskb->mac_len = skb->mac_len;
	把老skb的skb_buff内容拷贝到新skb中

		    /* nskb and skb might have different headroom */
		    if (nskb->ip_summed == CHECKSUM_PARTIAL)
		        nskb->csum_start += skb_headroom(nskb) - headroom;
	修正下checksum计算的位置

		    skb_reset_mac_header(nskb);
		    skb_set_network_header(nskb, skb->mac_len);
		    nskb->transport_header = (nskb->network_header +
		                  skb_network_header_len(skb));
		    skb_copy_from_linear_data(skb, nskb->data, doffset);

	把skb->data开始doffset长度的内容拷贝到nskb->data中，即把mac header , ip header, tcp header都复制过去


		    if (fskb != skb_shinfo(skb)->frag_list)
		        continue;

		    if (!sg) {
		        nskb->ip_summed = CHECKSUM_NONE;
		        nskb->csum = skb_copy_and_csum_bits(skb, offset,
		                            skb_put(nskb, len),
		                            len, 0);
		        continue;
		    }

		    frag = skb_shinfo(nskb)->frags;

		    skb_copy_from_linear_data_offset(skb, offset,
		                     skb_put(nskb, hsize), hsize);

	如果hsize不为0，那么拷贝hsize的内容到nskb header中


		    while (pos < offset + len && i < nfrags) {

	offset + len长度超过了pos，即超过了nskb header，这时需要用到frag


		        *frag = skb_shinfo(skb)->frags[i];
		        get_page(frag->page);
		        size = frag->size;

		        if (pos < offset) {
		            frag->page_offset += offset - pos;
		            frag->size -= offset - pos;
		        }


		        skb_shinfo(nskb)->nr_frags++;

		        if (pos + size <= offset + len) {
		            i++;
		            pos += size;
		        } else {
		            frag->size -= pos + size - (offset + len);
		            goto skip_fraglist;
		        }

		        frag++;
		    }

	如果skb header空间不够，那么通过frag，把一个mss的内容拷贝到nskb的frag中


		    if (pos < offset + len) {
		        struct sk_buff *fskb2 = fskb;

		        BUG_ON(pos + fskb->len != offset + len);

		        pos += fskb->len;
		        fskb = fskb->next;

		        if (fskb2->next) {
		            fskb2 = skb_clone(fskb2, GFP_ATOMIC);
		            if (!fskb2)
		                goto err;
		        } else
		            skb_get(fskb2);

		        SKB_FRAG_ASSERT(nskb);
		        skb_shinfo(nskb)->frag_list = fskb2;
		    }

	如果frag都用完还是无法满足mss的大小，那么就要用到frag_list，这段代码跳过去了，因为基本永远不会走到这里


	skip_fraglist:
		    nskb->data_len = len - hsize;
		    nskb->len += nskb->data_len;
		    nskb->truesize += nskb->data_len;
		} while ((offset += len) < skb->len);

	完成一个nskb之后，继续下一个seg，一直到offset >= skb->len

		return segs;

	err:
		while ((skb = segs)) {
		    segs = skb->next;
		    kfree_skb(skb);
		}
		return ERR_PTR(err);
	}
```

