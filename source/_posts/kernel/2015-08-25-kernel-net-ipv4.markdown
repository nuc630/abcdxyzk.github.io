---
layout: post
title: "linux下ip协议(V4)的实现"
date: 2015-08-25 23:34:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~net
tags:
---

这次主要介绍的是ip层的切片与组包的实现。

首先来看一下分片好的帧的一些概念：

1 第一个帧的offset位非0并且MF位为1

2 所有的在第一个帧和最后一个帧之间的帧都拥有长度大于0的域

3 最后一个帧MF位为0 并且offset位非0。(这样就能判断是否是最后一个帧了).

这里要注意在linux中，ip头的frag_off域包含了 rfcip头的定义中的nf,df,以及offset域，因此我们每次需要按位与来取得相应的域的值,看下面

ip_local_deliver的代码片段就清楚了：

```
		// 取出mf位和offset域，从而决定是否要组包。
		if (ip_hdr(skb)->frag_off & htons(IP_MF | IP_OFFSET)) {
			if (ip_defrag(skb, IP_DEFRAG_LOCAL_DELIVER))
				return 0;
		}
```

而fragmentation/defragmentation 子系统的初始化是通过ipfrag_init来实现了，而它是被inet_init来调用的。它主要做的是注册sys文件系统节点，并开启一个定时器，以及初始化一些相关的变量.这个函数的初始化以及相关的数据结构的详细介绍，我们会在后面的组包小节中介绍。现在我们先来看切片的处理。

相对于组包，切片逻辑什么的都比较简单。切片的主要函数是ip_fragment.它的输入包包括下面几种：

1 要被转发的包(没有切片的)。

2 要被转发的包(已经被路由器或者源主机切片了的).

3 被本地函数所创建的buffer，简而言之也就是本地所要传输的数据包(还未加包头)，但是需要被切片的。

而ip_fragment所必须处理下面几种情况：

1 一大块数据需要被分割为更小的部分。

2 一堆数据片段(我的上篇blog有介绍，也就是ip_append_data已经切好的数据包，或者tcp已经切好的数据包)不需要再被切片。

上面的两种情况其实就是看高层(4层)协议有没有做切片工作(按照PMTU）了。如果已经被切片(其实也算不上切片(4层不能处理ip头)，只能说i4层为了ip层更好的处理数据包，从而帮ip层做了一部分工作)，则ip层所做的很简单，就是给每个包加上ip头就可以了。

切片分为两种类型，一种是fast (或者说 efficient)切片，这种也就是4层已经切好片，这里只需要加上ip头就可以了，一种是slow切片，也就是需要现在切片。

下来来看切片的主要任务：

1 将数据包切片为MTU大小(通过ptmu).

2 初始化每一个fragment的ip 头。还要判断一些option的copy位，因为并不是每一种option都要放在所有已切片的fragment 的ip头中的。

3 计算ip层的校验值。

4 通过netfilter过滤。

5 update 一些kernel 域以及snmp 统计值。


接下来来看ip_fragment的具体实现：

```
	int ip_fragment(struct sk_buff *skb, int (*output)(struct sk_buff*))
```

第一个参数skb表示将要被切片的ip包，第二个参数是一个传输切片的输出函数(切片完毕后就交给这个函数处理)。比如ip_finish_output2类似的。


这个函数我们来分段看，首先来看它进行切片前的一些准备工作：


```
		// 先是取出了一些下面将要使用的变量。
		struct iphdr *iph;
		int raw = 0;
		int ptr;
		struct net_device *dev;
		struct sk_buff *skb2;
		unsigned int mtu, hlen, left, len, ll_rs, pad;
		int offset;
		__be16 not_last_frag;
		// 路由表
		struct rtable *rt = skb->rtable;
		int err = 0;
		// 网络设备
		dev = rt->u.dst.dev;

		// ip头
		iph = ip_hdr(skb);
		// 判断DF位，我们知道如果df位被设置了话就表示不要被切片，这时ip_fragment将会发送一个icmp豹纹返回到源主机。这里主要是为forward数据所判断。
		if (unlikely((iph->frag_off & htons(IP_DF)) && !skb->local_df)) {
			IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGFAILS);
			icmp_send(skb, ICMP_DEST_UNREACH, ICMP_FRAG_NEEDED,
				  htonl(ip_skb_dst_mtu(skb)));
			kfree_skb(skb);
			return -EMSGSIZE;
		}
		// 得到ip头的长度
		hlen = iph->ihl * 4;
		// 得到mtu的大小。这里要注意，他的大小减去了hlen，也就是ip头的大小。
		mtu = dst_mtu(&rt->u.dst) - hlen;    /* Size of data space */
		IPCB(skb)->flags |= IPSKB_FRAG_COMPLETE;
```


不管是slow还是fast 被切片的任何一个帧如果传输失败，ip_fragment都会立即返回一个错误给4层，并且紧跟着的帧也不会再被传输，然后将处理方法交给4层去做。

接下来我们来看fast 切片。 一般用fast切片的都是经由4层的ip_append_data和ip_push_pending函数(udp)将数据包已经切片好的，或者是tcp层已经切片好的数据包，才会用fast切片.

这里要主要几个问题：  
1 每一个切片的大小都不能超过PMTU。  
2 只有最后一个切片才会有3层的整个数据包的大小。  
3 每一个切片都必须有足够的大小来允许2层加上自己的头。  

我们先看一下skb_pagelen这个函数(下面的处理会用到),这个函数用来得到当前skb的len，首先我们要知道(我前面的blog有介绍)在sk_write_queue的sk_buff队列中，每一个sk_buff的len = x(也就是么一个第一个切片的包的l4 payload的长度) + S1 (这里表示所有的frags域的数据的总大小，也就是data_len的长度)。可以先看下面的图：

![](/images/kernel/2015-08-25-21.jpg)


很容易一目了然。

```
	static inline int skb_pagelen(const struct sk_buff *skb)
	{
		int i, len = 0;
		// 我们知道如果设备支持S/G IO的话，nr_frags会包含一些L4 payload，因此我们需要先遍历nr_frags.然后加入它的长度。
		for (i = (int)skb_shinfo(skb)->nr_frags - 1; i >= 0; i--)
			len += skb_shinfo(skb)->frags[i].size;
		// 最后加上skb_headlen,而skb_headlen = skb->len - skb->data_len;因此这里就会返回这个数据包的len。
		return len + skb_headlen(skb);
	}
```

```
		// 通过上一篇blog我们知道，如果4层将数据包分片了，那么就会把这些数据包放到skb的frag_list链表中，因此我们这里首先先判断frag_list链表是否为空，为空的话我们将会进行slow 切片。
		if (skb_shinfo(skb)->frag_list) {
			struct sk_buff *frag;
			// 取得第一个数据报的len.我们知道当sk_write_queue队列被flush后，除了第一个切好包的另外的包都会加入到frag_list中，而这里我们我们需要得到的第一个包(也就是本身这个sk_buff）的长度。
			int first_len = skb_pagelen(skb);
			int truesizes = 0;
			// 接下来的判断都是为了确定我们能进行fast切片。切片不能被共享，这是因为在fast path 中，我们需要加给每个切片不同的ip头(而并不会复制每个切片)。因此在fast path中是不可接受的。而在slow path中，就算有共享也无所谓，因为他会复制每一个切片，使用一个新的buff。

			// 判断第一个包长度是否符合一些限制(包括mtu，mf位等一些限制).如果第一个数据报的len没有包含mtu的大小这里之所以要把第一个切好片的数据包单独拿出来检测，是因为一些域是第一个包所独有的(比如IP_MF要为1）。这里由于这个mtu是不包括hlen的mtu，因此我们需要减去一个hlen。
			if (first_len - hlen > mtu ||
				((first_len - hlen) & 7) ||
				(iph->frag_off & htons(IP_MF|IP_OFFSET)) ||
				skb_cloned(skb))
				goto slow_path;
			// 遍历剩余的frag。
			for (frag = skb_shinfo(skb)->frag_list; frag; frag = frag->next) {
				/* Correct geometry. */
				// 判断每个帧的mtu，以及相关的东西，如果不符合条件则要进行slow path,基本和上面的第一个skb的判断类似。
				if (frag->len > mtu ||
					((frag->len & 7) && frag->next) ||
					skb_headroom(frag) < hlen)
					goto slow_path;
				// 判断是否共享。
				/* Partially cloned skb? */
				if (skb_shared(frag))
					goto slow_path;

				BUG_ON(frag->sk);
				// 进行socket的一些操作。
				if (skb->sk) {
					sock_hold(skb->sk);
					frag->sk = skb->sk;
					frag->destructor = sock_wfree;
					truesizes += frag->truesize;
				}
			}

			// 通过上面的检测，都通过了，因此我们可以进行fast path切片了。

			// 先是设置一些将要处理的变量的值。
			err = 0;
			offset = 0;
			// 取得frag_list列表
			frag = skb_shinfo(skb)->frag_list;
			skb_shinfo(skb)->frag_list = NULL;

			// 得到数据(不包括头)的大小。
			skb->data_len = first_len - skb_headlen(skb);
			skb->truesize -= truesizes;
			// 得到
			skb->len = first_len;
			iph->tot_len = htons(first_len);
			// 设置mf位
			iph->frag_off = htons(IP_MF);
			// 执行校验
			ip_send_check(iph);

			for (;;) {
				// 开始进行发送。
				if (frag) {
					// 设置校验位
					frag->ip_summed = CHECKSUM_NONE;
					// 设置相应的头部。
					skb_reset_transport_header(frag);
					__skb_push(frag, hlen);
					skb_reset_network_header(frag);
					// 复制ip头。
					memcpy(skb_network_header(frag), iph, hlen);
					// 修改每个切片的ip头的一些属性。
					iph = ip_hdr(frag);
					iph->tot_len = htons(frag->len);
					// 将当前skb的一些属性付给将要传递的切片好的帧。
					ip_copy_metadata(frag, skb);
					if (offset == 0)
					// 处理ip_option
						ip_options_fragment(frag);
					offset += skb->len - hlen;
					// 设置位移。
					iph->frag_off = htons(offset>>3);
					if (frag->next != NULL)
						iph->frag_off |= htons(IP_MF);
					/* Ready, complete checksum */
					ip_send_check(iph);
				}
				// 调用输出函数。
				err = output(skb);

				if (!err)
					IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGCREATES);
				if (err || !frag)
					break;
				// 处理链表中下一个buf。
				skb = frag;
				frag = skb->next;
				skb->next = NULL;
			}

			if (err == 0) {
				IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGOKS);
				return 0;
			}
			// 释放内存。
			while (frag) {
				skb = frag->next;
				kfree_skb(frag);
				frag = skb;
			}
			IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGFAILS);
			return err;
		}

```


再接下来我们来看slow fragmentation：

```
		// 切片开始的位移
		left = skb->len - hlen;      /* Space per frame */
		// 而ptr就是切片开始的指针。
		ptr = raw + hlen;       /* Where to start from */

		/* for bridged IP traffic encapsulated inside f.e. a vlan header,
		 * we need to make room for the encapsulating header
		 */
		// 处理桥接的相关操作。
		pad = nf_bridge_pad(skb);
		ll_rs = LL_RESERVED_SPACE_EXTRA(rt->u.dst.dev, pad);
		mtu -= pad;

		// 其实也就是取出取出ip offset域。
		offset = (ntohs(iph->frag_off) & IP_OFFSET) << 3;
		// not_last_frag，顾名思义，其实也就是表明这个帧是否是最后一个切片。
		not_last_frag = iph->frag_off & htons(IP_MF);


		// 开始为循环处理，每一个切片创建一个skb buffer。
		while (left > 0) {
			len = left;
			// 如果len大于mtu，我们设置当前的将要切片的数据大小为mtu。
			if (len > mtu)
				len = mtu;
			// 长度也必须位对齐。
			if (len < left)  {
				len &= ~7;
			}
			// malloc一个新的buff。它的大小包括ip payload,ip head,以及L2 head.
			if ((skb2 = alloc_skb(len+hlen+ll_rs, GFP_ATOMIC)) == NULL) {
				NETDEBUG(KERN_INFO "IP: frag: no memory for new fragment!\n");
				err = -ENOMEM;
				goto fail;
			}
			// 调用ip_copy_metadata复制一些相同的值的域。
			ip_copy_metadata(skb2, skb);
			// 进行skb的相关操作。为了加上ip头。
			skb_reserve(skb2, ll_rs);
			skb_put(skb2, len + hlen);
			skb_reset_network_header(skb2);
			skb2->transport_header = skb2->network_header + hlen;
			// 将每一个分片的ip包都关联到源包的socket上。
			if (skb->sk)
				skb_set_owner_w(skb2, skb->sk);
			// 开始填充新的ip包的数据。

			// 先拷贝包头。
			skb_copy_from_linear_data(skb, skb_network_header(skb2), hlen);
			// 拷贝数据部分，这个函数实现的比较复杂。
			if (skb_copy_bits(skb, ptr, skb_transport_header(skb2), len))
				BUG();
			left -= len;
			// 填充相应的ip头。
			iph = ip_hdr(skb2);
			iph->frag_off = htons((offset >> 3));

			// 第一个包，因此进行ip_option处理。
			if (offset == 0)
				ip_options_fragment(skb);
			// 不是最后一个包，因此设置mf位。
			if (left > 0 || not_last_frag)
				iph->frag_off |= htons(IP_MF);
			// 移动指针以及更改位移大小。
			ptr += len;
			offset += len;
			// update包头的大小。
			iph->tot_len = htons(len + hlen);
			// 重新计算校验。
			ip_send_check(iph);
			//最终输出。
			err = output(skb2);
			if (err)
				goto fail;

			IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGCREATES);
		}
		kfree_skb(skb);
		IP_INC_STATS(dev_net(dev), IPSTATS_MIB_FRAGOKS);
		return err;
```


接下来来看ip组包的实现。首先要知道每一个切片(属于同一个源包的)的ip包 id都是相同的。

首先来看相应的数据结构。在内核中，每一个ip包(切片好的)都是一个struct ipq链表。而不同的数据包(这里指不是属于同一个源包的数据包)都保

存在一个hash表中。也就是ip4_frags这个变量：

```
	static struct inet_frags ip4_frags;

	#define INETFRAGS_HASHSZ        64

	struct inet_frags {
		struct hlist_head   hash[INETFRAGS_HASHSZ];
		rwlock_t        lock;
		// 随机值，它被用在计算hash值上面，下面会介绍到，过一段时间，内核就会更新这个值。
		u32         rnd;
		int         qsize;
		int         secret_interval;
		struct timer_list   secret_timer;
		// hash函数
		unsigned int        (*hashfn)(struct inet_frag_queue *);
		void            (*constructor)(struct inet_frag_queue *q,
							void *arg);
		void            (*destructor)(struct inet_frag_queue *);
		void            (*skb_free)(struct sk_buff *);
		int         (*match)(struct inet_frag_queue *q,
							void *arg);
		void            (*frag_expire)(unsigned long data);
	};

	struct ipq {
		struct inet_frag_queue q;
		u32     user;
		// 都是ip头相关的一些域。
		__be32      saddr;
		__be32      daddr;
		__be16      id;
		u8      protocol;
		int             iif;
		unsigned int    rid;
		struct inet_peer *peer;
	};

	struct inet_frag_queue {
		struct hlist_node   list;
		struct netns_frags  *net;
		// 基于LRU算法，主要用在GC上。
		struct list_head    lru_list;   /* lru list member */
		spinlock_t      lock;
		atomic_t        refcnt;
		// 属于同一个源的数据包的定时器，当定时器到期，切片还没到达，此时就会drop掉所有的数据切片。
		struct timer_list   timer;      /* when will this queue expire? */
		// 保存有所有的切片链表(从属于同一个ip包)
		struct sk_buff      *fragments; /* list of received fragments */
		ktime_t         stamp;
		int         len;        /* total length of orig datagram */
		// 表示从源ip包已经接收的字节数。
		int         meat;
		// 这个域主要可以设置为下面的3种值。
		__u8            last_in;    /* first/last segment arrived? */

	// 完成，第一个帧以及最后一个帧。
	#define INET_FRAG_COMPLETE  4
	#define INET_FRAG_FIRST_IN  2
	#define INET_FRAG_LAST_IN   1
	};
```

看下面的图就一目了然了：

![](/images/kernel/2015-08-25-22.jpg)

首先来看组包要解决的一些问题：

1 fragment必须存储在内存中，知道他们全部都被网络子系统处理。才会释放，因此内存会是个巨大的浪费。

2 这里虽然使用了hash表，可是假设恶意攻击者得到散列算法并且伪造数据包来尝试着降低一些hash表中的元素的比重，从而使执行变得缓慢。这里linux使用一个定时器通过制造的随机数来使hash值的生成不可预测。

这个定时器的初始化是通过ipfrag_init(它会初始化上面提到的ip4_frags全局变量)调用inet_frags_init进行的：

```
	void inet_frags_init(struct inet_frags *f)
	{
		int i;

		for (i = 0; i < INETFRAGS_HASHSZ; i++)
			INIT_HLIST_HEAD(&f->hash[i]);

		rwlock_init(&f->lock);

		f->rnd = (u32) ((num_physpages ^ (num_physpages>>7)) ^
					   (jiffies ^ (jiffies >> 6)));
		// 安装定时器，当定时器到期就会调用inet_frag_secret_rebuild方法。
		setup_timer(&f->secret_timer, inet_frag_secret_rebuild,
				(unsigned long)f);
		f->secret_timer.expires = jiffies + f->secret_interval;
		add_timer(&f->secret_timer);
	}

	static void inet_frag_secret_rebuild(unsigned long dummy)
	{
	................................................

		write_lock(&f->lock);
		// 得到随机值
		get_random_bytes(&f->rnd, sizeof(u32));

		// 然后通过这个随机值重新计算整个hash表的hash值。
		for (i = 0; i < INETFRAGS_HASHSZ; i++) {
			struct inet_frag_queue *q;
			struct hlist_node *p, *n;

			hlist_for_each_entry_safe(q, p, n, &f->hash[i], list) {
				unsigned int hval = f->hashfn(q);

				if (hval != i) {
					hlist_del(&q->list);

					/* Relink to new hash chain. */
					hlist_add_head(&q->list, &f->hash[hval]);
				}
			}
		}
	..............................................
	}
```


3 ip协议是不可靠的，因此切片有可能被丢失。内核处理这个，是使用了一个定时器(每个数据包(也就是这个切片从属于的那个数据包)).当定时器到期，而切片没有到达，就会丢弃这个包。

4 由于ip协议是无连接的，因此当高层决定重传数据包的时候，组包时有可能会出现多个重复分片的情况。这是因为ip包是由4个域来判断的，源和目的地址，包id以及4层的协议类型。而最主要的是包id。可是包id只有16位，因此一个gigabit网卡几乎在半秒时间就能用完这个id一次。而第二次重传的数据包有可能走的和第一个第一次时不同的路径，因此内核必须每个切片都要检测和前面接受的切片的重叠情况的发生。

先来看ip_defrag用到的几个函数：

inet_frag_create: 创建一个新的ipq实例

ip_evitor: remove掉所有的未完成的数据包。它每次都会update一个LRU链表。每次都会把一个新的ipq数据结构加到ipq_lru_list的结尾。

ip_find: 发现切片所从属的数据包的切片链表。

ip_frag_queue: 排队一个给定的切片刀一个切片列表。这个经常和上一个方法一起使用。

ip_frag_reasm: 当所有的切片都到达后，build一个ip数据包。

ip_frag_destroy: remove掉传进来的ipq数据结构。包括和他有联系的所有的ip切片。

ipq_put: 将引用计数减一，如果为0，则直接调用ip_frag_destroy.

```
	static inline void inet_frag_put(struct inet_frag_queue *q, struct inet_frags *f)
	{
		if (atomic_dec_and_test(&q->refcnt))
			inet_frag_destroy(q, f, NULL);
	}
```


ipq_kill: 主要用在gc上，标记一个ipq数据结构可以被remove，由于一些帧没有按时到达。

接下来来看ip_defrag的实现。

```
	int ip_defrag(struct sk_buff *skb, u32 user)
	{
		struct ipq *qp;
		struct net *net;

		net = skb->dev ? dev_net(skb->dev) : dev_net(skb->dst->dev);
		IP_INC_STATS_BH(net, IPSTATS_MIB_REASMREQDS);

		// 如果内存不够，则依据lru算法进行清理。
		if (atomic_read(&net->ipv4.frags.mem) > net->ipv4.frags.high_thresh)
			ip_evictor(net);

		// 查找相应的iqp，如果不存在则会新创建一个(这些都在ip_find里面实现)
		if ((qp = ip_find(net, ip_hdr(skb), user)) != NULL) {
			int ret;

			spin_lock(&qp->q.lock);
			// 排队进队列。
			ret = ip_frag_queue(qp, skb);

			spin_unlock(&qp->q.lock);
			ipq_put(qp);
			return ret;
		}

		IP_INC_STATS_BH(net, IPSTATS_MIB_REASMFAILS);
		kfree_skb(skb);
		return -ENOMEM;
	}
```



我们可以看到这里最重要的一个函数其实是ip_frag_queue,它主要任务是：

1 发现输入帧在源包的位置。  
2 基于blog刚开始所描述的，判断是否是最后一个切片。  
3 插入切片到切片列表(从属于相同的ip包)  
4 update 垃圾回收所用到的ipq的一些相关域。  
5 校验l4层的校验值(在硬件计算).  


```
	// 其中qp是源ip包的所有切片链表，而skb是将要加进来切片。
	static int ip_frag_queue(struct ipq *qp, struct sk_buff *skb)
	{
		.............................
		//  INET_FRAG_COMPLETE表示所有的切片包都已经抵达，这个时侯就不需要再组包了，因此这里就是校验函数有没有被错误的调用。
		if (qp->q.last_in & INET_FRAG_COMPLETE)
			goto err;
		.................................................
		// 将offset 8字节对齐、
		offset = ntohs(ip_hdr(skb)->frag_off);
		flags = offset & ~IP_OFFSET;
		offset &= IP_OFFSET;
		offset <<= 3;     /* offset is in 8-byte chunks */
		ihl = ip_hdrlen(skb);

		// 计算这个新的切片包的结束位置。
		end = offset + skb->len - ihl;
		err = -EINVAL;

		// MF没有设置，表明这个帧是最后一个帧。进入相关处理。
		if ((flags & IP_MF) == 0) {
			/* If we already have some bits beyond end
			 * or have different end, the segment is corrrupted.
			 */
		// 设置相应的len位置，以及last_in域。
			if (end < qp->q.len ||
				((qp->q.last_in & INET_FRAG_LAST_IN) && end != qp->q.len))
				goto err;
			qp->q.last_in |= INET_FRAG_LAST_IN;
			qp->q.len = end;
		} else {
			// 除了最后一个切片，每个切片都必须是8字节的倍数。
			if (end&7) {
				// 不是8字节的倍数，kernel截断这个切片。此时就需要l4层的校验重新计算，因此设置ip_summed为 CHECKSUM_NONE
				end &= ~7;
				if (skb->ip_summed != CHECKSUM_UNNECESSARY)
					skb->ip_summed = CHECKSUM_NONE;
			}
			if (end > qp->q.len) {
				// 数据包太大，并且是最后一个包，则表明这个数据包出错，因此drop它。
				/* Some bits beyond end -> corruption. */
				if (qp->q.last_in & INET_FRAG_LAST_IN)
					goto err;
				qp->q.len = end;
			}
		}
		// ip头不能被切片，因此end肯定会大于offset。
		if (end == offset)
			goto err;

		err = -ENOMEM;
		// remove掉ip头。
		if (pskb_pull(skb, ihl) == NULL)
			goto err;
		// trim掉一些padding，然后重新计算checksum。
		err = pskb_trim_rcsum(skb, end - offset);
		if (err)
			goto err;

		// 接下来遍历并将切片(为了找出当前将要插入的切片的位置)，是以offset为基准。这里要合租要FRAG_CB宏是用来提取sk_buff->cb域。
		prev = NULL;
		for (next = qp->q.fragments; next != NULL; next = next->next) {
			if (FRAG_CB(next)->offset >= offset)
				break;  /* bingo! */
			prev = next;
		}
		// 当prev!=NULL时，说明这个切片要插入到列表当中。
		if (prev) {
			// 计算有没有重叠。
			int i = (FRAG_CB(prev)->offset + prev->len) - offset;
			// 大于0.证明有重叠，因此进行相关处理
			if (i > 0) {
				// 将重叠部分用新的切片覆盖。
				offset += i;
				err = -EINVAL;
				if (end <= offset)
					goto err;
				err = -ENOMEM;
				//移动i个位置。
				if (!pskb_pull(skb, i))
					goto err;
				// 需要重新计算L4的校验。
				if (skb->ip_summed != CHECKSUM_UNNECESSARY)
					skb->ip_summed = CHECKSUM_NONE;
			}
		}

		err = -ENOMEM;

		while (next && FRAG_CB(next)->offset < end) {
			// 和上面的判断很类似，也是先计算重叠数。这里要注意重叠分为两种情况：1；一个或多个切片被新的切片完全覆盖。2；被部分覆盖，因此这里我们需要分两种情况进行处理。
			int i = end - FRAG_CB(next)->offset; /* overlap is 'i' bytes */

			if (i < next->len) {
				// 被部分覆盖的情况。将新的切片offset移动i字节，然后remove掉老的切片中的i个字节。
				/* Eat head of the next overlapped fragment
				 * and leave the loop. The next ones cannot overlap.
				 */
				if (!pskb_pull(next, i))
					goto err;
				FRAG_CB(next)->offset += i;
				// 将接收到的源数据报的大小减去i，也就是remove掉不完全覆盖的那一部分。
				qp->q.meat -= i;
				// 重新计算l4层的校验。
				if (next->ip_summed != CHECKSUM_UNNECESSARY)
					next->ip_summed = CHECKSUM_NONE;
				break;
			} else {
				// 老的切片完全被新的切片覆盖，此时只需要remove掉老的切片就可以了。
				struct sk_buff *free_it = next;
				next = next->next;

				if (prev)
					prev->next = next;
				else
					qp->q.fragments = next;
				// 将qp的接受字节数更新。
				qp->q.meat -= free_it->len;
				frag_kfree_skb(qp->q.net, free_it, NULL);
			}
		}

		FRAG_CB(skb)->offset = offset;

	....................................................
		atomic_add(skb->truesize, &qp->q.net->mem);
		// offset为0说明是第一个切片，因此设置相应的位。
		if (offset == 0)
			qp->q.last_in |= INET_FRAG_FIRST_IN;

		if (qp->q.last_in == (INET_FRAG_FIRST_IN | INET_FRAG_LAST_IN) &&
			qp->q.meat == qp->q.len)
			// 所有条件的满足了，就开始buildip包。
			return ip_frag_reasm(qp, prev, dev);
		write_lock(&ip4_frags.lock);
		// 从将此切片加入到lry链表中。
		list_move_tail(&qp->q.lru_list, &qp->q.net->lru_list);
		write_unlock(&ip4_frags.lock);
		return -EINPROGRESS;

	err:
		kfree_skb(skb);
		return err;
	}
```


如果网络设备提供L4层的硬件校验的话，输入ip帧还会进行L4的校验计算。当帧通过ip_frag_reasm组合好，它会进行校验的重新计算。我们这里通过设置skb->ip_summed到CHECKSUM_NONE，来表示需要娇艳的标志。

最后来看下GC。

内核为ip切片数据包实现了两种类型的垃圾回收。

1 系统内存使用限制。

2 组包的定时器

这里有一个全局的ip_frag_mem变量，来表示当前被切片所占用的内存数。每次一个新的切片被加入，这个值都会更新。而所能使用的最大内存可以在运行时改变，是通过/proc的sysctl_ipfrag_high_thresh来改变的，因此我们能看到当ip_defrag时，一开始会先判断内存的限制：

```
	if (atomic_read(&net->ipv4.frags.mem) > net->ipv4.frags.high_thresh)
			ip_evictor(net);
```


当一个切片数据包到达后，内核会启动一个组包定时器，他是为了避免一个数据包占据ipq_hash太长时间，因此当定时器到期后，它就会清理掉在hash表中的相应的qp结构(也就是所有的未完成切片包).这个处理函数就是ip_expire,它的初始化是在ipfrag_init进行的。:

```
	static void ip_expire(unsigned long arg)
	{
		struct ipq *qp;
		struct net *net;
		// 取出相应的qp，以及net域。
		qp = container_of((struct inet_frag_queue *) arg, struct ipq, q);
		net = container_of(qp->q.net, struct net, ipv4.frags);

		spin_lock(&qp->q.lock);
		// 如果数据包已经传输完毕，则不进行任何处理，直接退出。
		if (qp->q.last_in & INET_FRAG_COMPLETE)
			goto out;
		// 调用ipq_kill，这个函数主要是减少qp的引用计数，并从相关链表(比如LRU_LIST)中移除它。
		ipq_kill(qp);

		IP_INC_STATS_BH(net, IPSTATS_MIB_REASMTIMEOUT);
		IP_INC_STATS_BH(net, IPSTATS_MIB_REASMFAILS);

		// 如果是第一个切片，则发送一个ICMP给源主机。
		if ((qp->q.last_in & INET_FRAG_FIRST_IN) && qp->q.fragments != NULL) {
			struct sk_buff *head = qp->q.fragments;

			/* Send an ICMP "Fragment Reassembly Timeout" message. */
			if ((head->dev = dev_get_by_index(net, qp->iif)) != NULL) {
				icmp_send(head, ICMP_TIME_EXCEEDED, ICMP_EXC_FRAGTIME, 0);
				dev_put(head->dev);
			}
		}
	out:
		spin_unlock(&qp->q.lock);
		ipq_put(qp);
	}
```

