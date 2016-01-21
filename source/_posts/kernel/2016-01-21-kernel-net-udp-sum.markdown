---
layout: post
title: "udp checksum"
date: 2016-01-21 16:43:00 +0800
comments: false
categories:
- 2016
- 2016~01
- kernel
- kernel~net
tags:
---
http://wenx05124561.blog.163.com/blog/static/124000805201242032041268/

#### a. 网卡设备属性

```
	#define NETIF_F_IP_CSUM     2   /* 基于IPv4的L4层checksum. */  
	#define NETIF_F_NO_CSUM     4   /* 设备可靠不需要L4层checksum. loopack. */  
	#define NETIF_F_HW_CSUM     8   /* 基于所有协议的L4层checksum*/  
	#define NETIF_F_IPV6_CSUM   16  /* 基于IPv6的L4层checksum*/  
```

通过ethtool -k eth0可以查看网卡是否支持硬件checksum，tx-checksumming: on  表明支持发送hardware checksum。

#### b. linux UDP checksum数据结构

```
	union {
		__wsum	csum;
		struct {
			__u16	csum_start;
			__u16	csum_offset;
		};
	};
```

1） skb->csum和skb->ip_summed这两个域也是与4层校验相关的，这两个域的含义依赖于skb表示的是一个输入包还是一个输出包。

2） 当网卡设备能提供硬件checksum并且作为输出包的时候，表示为skb->csum_start和skb->csum_offset

csum_start: Offset from skb->head where checksumming should start

csum_offset: Offset from csum_start where checksum should be stored

当数据包是一个输入包时

skb->ip_summed表示的是四层校验的状态，下面的几个宏定义表示了设备驱动传递给4层的一些信息。

```
	#define CHECKSUM_NONE 0
	#define CHECKSUM_UNNECESSARY 1
	#define CHECKSUM_COMPLETE 2
``` 

skb->csum:存放硬件或者软件计算的payload的checksum不包括伪头，但是是否有意义由skb->ip_summed的值决定。


CHECKSUM_NONE表示csum域中的校验值是无意义的，需要L4层自己校验payload和伪头。有可能是硬件检验出错或者硬件没有校验功能，协议栈软件更改如pskb_trim_rcsum函数。

CHECKSUM_UNNECESSARY表示网卡或者协议栈已经计算和验证了L4层的头和校验值。也就是计算了tcp udp的伪头。还有一种情况就是回环，因为在回环中错误发生的概率太低了，因此就不需要计算校验来节省cpu事件。

CHECKSUM_COMPLETE表示网卡已经计算了L4层payload的校验，并且csum已经被赋值，此时L4层的接收者只需要加伪头并验证校验结果。

1) 在L4层发现如果udp->check位段被设为0，那么skb->ip_summed直接设为CHECKSUM_UNNECESSARY，放行该报文。

2) 如果skb->ip_summed为CHECKSUM_COMPLETE，则把skb->csum加上伪头进行校验，成功则将skb->ip_summed设为CHECKSUM_UNNECESSARY， 放行该数据包。

3) 通过上述后skb->ip_summed还不是CHECKSUM_UNNECESSARY，那么重新计算伪头赋给skb->csum。

4) 将还不是CHECKSUM_UNNECESSARY的数据报文的payload加上skb->csum进行checksum计算，成功将设为CHECKSUM_UNNECESSARY并放行，失败则丢弃。

```
	static inline int udp4_csum_init(struct sk_buff *skb, struct udphdr *uh, 
					int proto)
	{
		const struct iphdr *iph;
		int err; 

		UDP_SKB_CB(skb)->partial_cov = 0; 
		UDP_SKB_CB(skb)->cscov = skb->len;

		if (proto == IPPROTO_UDPLITE) {
			err = udplite_checksum_init(skb, uh); 
			if (err)
				return err; 
		}    

		iph = ip_hdr(skb);
		if (uh->check == 0) { 
			skb->ip_summed = CHECKSUM_UNNECESSARY;
		} else if (skb->ip_summed == CHECKSUM_COMPLETE) {
			if (!csum_tcpudp_magic(iph->saddr, iph->daddr, skb->len,
					proto, skb->csum))
				skb->ip_summed = CHECKSUM_UNNECESSARY;
		}    
		if (!skb_csum_unnecessary(skb))
			skb->csum = csum_tcpudp_nofold(iph->saddr, iph->daddr,
								skb->len, proto, 0);
		/* Probably, we should checksum udp header (it should be in cache
		 * in any case) and data in tiny packets (< rx copybreak).
		 */

		return 0;
	}
```

```
	if (udp_lib_checksum_complete(skb))
		goto csum_error;
```

```
	static inline int udp_lib_checksum_complete(struct sk_buff *skb)
	{
		return !skb_csum_unnecessary(skb) &&
			__udp_lib_checksum_complete(skb);
	}

	static inline __sum16 __udp_lib_checksum_complete(struct sk_buff *skb)
	{
		return __skb_checksum_complete_head(skb, UDP_SKB_CB(skb)->cscov);
	}

	__sum16 __skb_checksum_complete_head(struct sk_buff *skb, int len)
	{
		__sum16 sum;

		sum = csum_fold(skb_checksum(skb, 0, len, skb->csum));
		if (likely(!sum)) {
			if (unlikely(skb->ip_summed == CHECKSUM_COMPLETE))
				netdev_rx_csum_fault(skb->dev);
			skb->ip_summed = CHECKSUM_UNNECESSARY;
		}
		return sum;
	}
```

#### 当数据包是输出包时

skb->csum表示为csum_start和csum_offset，它表示硬件网卡存放将要计算的校验值的地址，和最后填充的便宜。这个域在输出包时使用，只在校验值在硬件计算的情况下才对于网卡真正有意义。硬件checksum功能只能用于非分片报文。
而此时ip_summed可以被设置的值有下面两种：

```
	#define CHECKSUM_NONE		0
	#define CHECKSUM_PARTIAL	3
```

CHECKSUM_NONE 表示协议栈计算好了校验值，设备不需要做任何事。CHECKSUM_PARTIAL表示协议栈算好了伪头需要硬件计算payload checksum。

1）对于UDP socket开启了UDP_CSUM_NOXMIT /* UDP csum disabled */

```
	uh->check = 0；
	skb->ip_summed = CHECKSUM_NONE;
```

2）软件udp checksum
```
	struct iphdr *iph = ip_hdr(skb);
	struct udphdr *uh = udp_hdr(skb);
	uh->check = 0;
	skb->csum = csum_partial(skb_transport_header (skb), skb->len, 0);//skb->data指向传输层头
	uh->check = csum_tcpudp_magic(iph->saddr, iph->daddr, skb->len, iph->protocol, skb->csum);
	skb->ip_summed = CHECKSUM_NONE;
	//Todo: scatter and gather
```

3)  硬件checksum: 只能是ip报文长度小于mtu的数据报(没有分片的报文)。

CHECKSUM_PARTIAL表示使用硬件checksum ，L4层的伪头的校验已经完毕，并且已经加入uh->check字段中，此时只需要设备计算整个头4层头的校验值。

（对于支持scatter and gather的报文必须要传输层头在线性空间才能使用硬件checksum功能）

```
	uh->check = ~csum_tcpudp_magic(iph->saddr, iph->daddr, skb->len, IPPROTO_UDP, 0);
	skb->csum_start = skb_transport_header (skb) - skb->head;
	skb->csum_offset = offsetof(struct udphdr, check);
	skb->ip_summed = CHECKSUM_PARTIAL;
```

最后在dev_queue_xmit发送的时候发现设备不支持硬件checksum就会进行软件计算

```
	int dev_hard_start_xmit(struct sk_buff *skb, struct net_device *dev,
					struct netdev_queue *txq)

	{
		.......

				/* If packet is not checksummed and device does not
				 * support checksumming for this protocol, complete
				 * checksumming here.
				 */
				if (skb->ip_summed == CHECKSUM_PARTIAL) {
					skb_set_transport_header(skb, skb->csum_start -
							skb_headroom(skb));
					if (!dev_can_checksum(dev, skb) &&
							skb_checksum_help(skb))
						goto out_kfree_skb;
				}
		........

```
