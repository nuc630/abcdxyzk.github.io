---
layout: post
title: "dev_queue_xmi函数详解"
date: 2015-08-25 23:20:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~net
tags:
---
blog.chinaunix.net/uid-20788636-id-3181312.html

前面在分析IPv6的数据流程时，当所有的信息都准备好了之后，例如，出口设备，下一跳的地址，以及链路层地址。就会调用dev.c文件中的dev_queue_xmin函数，该函数是设备驱动程序执行传输的接口。也就是所有的数据包在填充完成后，最终发送数据时，都会调用该函数。

dev_queue_xmit函数只接收一个skb_buff结构作为输入的值。此数据结构包含了此函数所需要的一切信息。Skb->dev是出口设备，skb->data为有效的载荷的开头，其长度为skb->len.下面是2.6.37版本内核中的dev_queue_xmit函数，该版本的内核与之前的版本有了不少的区别。

```
	int dev_queue_xmit(struct sk_buff *skb)
	{
		struct net_device *dev = skb->dev;
		struct netdev_queue *txq;
		struct Qdisc *q;
		int rc = -ENOMEM;

		/* Disable soft irqs for various locks below. Also
		 * stops preemption for RCU.
		 */
		//关闭软中断 - __rcu_read_lock_bh()--->local_bh_disable();
		rcu_read_lock_bh();
		// 选择一个发送队列，如果设备提供了select_queue回调函数就使用它，否则由内核选择一个队列,这里只是Linux内核多队列的实现，但是要真正的使用都队列，需要网卡支持多队列才可以，一般的网卡都只有一个队列。在调用alloc_etherdev分配net_device是，设置队列的个数
		txq = dev_pick_tx(dev, skb);
		//从netdev_queue结构上获取设备的qdisc
		q = rcu_dereference_bh(txq->qdisc);

	#ifdef CONFIG_NET_CLS_ACT
		skb->tc_verd = SET_TC_AT(skb->tc_verd, AT_EGRESS);
	#endif
		//如果硬件设备有队列可以使用，该函数由dev_queue_xmit函数直接调用或由dev_queue_xmit通过qdisc_run函数调用
		trace_net_dev_queue(skb);
		if (q->enqueue) {
			rc = __dev_xmit_skb(skb, q, dev, txq); //使用流控对象发送数据包(包含入队和出队)
			//更详细的内容参考说明3
			goto out;
		}

		//下面的处理是在没有发送队列的情况下
		/* The device has no queue. Common case for software devices:
		 loopback, all the sorts of tunnels...

		 Really, it is unlikely that netif_tx_lock protection is necessary
		 here. (f.e. loopback and IP tunnels are clean ignoring statistics
		 counters.)
		 However, it is possible, that they rely on protection
		 made by us here.

		 Check this and shot the lock. It is not prone from deadlocks.
		 Either shot noqueue qdisc, it is even simpler 8)
		 */
		//首先，确定设备是开启的，并且还要确定队列是运行的，启动和停止队列有驱动程序决定
		//设备没有输出队列典型的是回环设备。这里需要做的就是直接调用dev_start_queue_xmit、、函数，经过驱动发送出去，如果发送失败，就直接丢弃，没有队列可以保存。
		if (dev->flags & IFF_UP) {
			int cpu = smp_processor_id(); /* ok because BHs are off */

			if (txq->xmit_lock_owner != cpu) {

				if (__this_cpu_read(xmit_recursion) > RECURSION_LIMIT)
					goto recursion_alert;

				HARD_TX_LOCK(dev, txq, cpu);

				if (!netif_tx_queue_stopped(txq)) {
					__this_cpu_inc(xmit_recursion);
					rc = dev_hard_start_xmit(skb, dev, txq);//见说明4
					__this_cpu_dec(xmit_recursion);
					if (dev_xmit_complete(rc)) {
						HARD_TX_UNLOCK(dev, txq);
						goto out;
					}
				}
				HARD_TX_UNLOCK(dev, txq);
				if (net_ratelimit())
					printk(KERN_CRIT "Virtual device %s asks to "
					 "queue packet!\n", dev->name);
			} else {
				/* Recursion is It is possible,
				 * unfortunately
				 */
	recursion_alert:
				if (net_ratelimit())
					printk(KERN_CRIT "Dead loop on virtual device "
					 "%s, fix it urgently!\n", dev->name);
			}
		}

		rc = -ENETDOWN;
		rcu_read_unlock_bh();

		kfree_skb(skb);
		return rc;
	out:
		rcu_read_unlock_bh();
		return rc;
	}
```


##### 1. 下面是dev_pick_tx函数。

```
	static struct netdev_queue *dev_pick_tx(struct net_device *dev,
						struct sk_buff *skb)
	{
		int queue_index;
		const struct net_device_ops *ops = dev->netdev_ops;

		if (ops->ndo_select_queue) {
			//选择一个索引，这个策略可以设置，比如优先选择视频和音频队列，而哪个队列邦定哪个策略也是设定的。
			queue_index = ops->ndo_select_queue(dev, skb);
			queue_index = dev_cap_txqueue(dev, queue_index);
		} else {
			struct sock *sk = skb->sk;
			queue_index = sk_tx_queue_get(sk);
			if (queue_index < 0 || queue_index >= dev->real_num_tx_queues) {

				queue_index = 0;
				if (dev->real_num_tx_queues > 1)
					queue_index = skb_tx_hash(dev, skb);

				if (sk) {
					struct dst_entry *dst = rcu_dereference_check(sk->sk_dst_cache, 1);

					if (dst && skb_dst(skb) == dst)
						sk_tx_queue_set(sk, queue_index);
				}
			}
		}

		skb_set_queue_mapping(skb, queue_index);
		return netdev_get_tx_queue(dev, queue_index);
	}
```

##### 2. 下面是其中的一种网卡类型调用函数alloc_etherdev时，

```
	dev = alloc_etherdev(sizeof(struct ether1_priv));
```

其实该函数是一个宏定义：其中第二参数表示的就是队列的数量，这里在Linux2.6.37内核中找到的一种硬件网卡的实现，可用的队列是1个。

```
	#define alloc_etherdev(sizeof_priv) alloc_etherdev_mq(sizeof_priv, 1)
```

下面是alloc_etherdev_mq函数的定义实现。

```
	struct net_device *alloc_etherdev_mq(int sizeof_priv, unsigned int queue_count)
	{
		return alloc_netdev_mq(sizeof_priv, "eth%d", ether_setup, queue_count);
	}
```

##### 3. 
几乎所有的设备都会使用队列调度出口的流量，而内核可以使用对了规则的算法安排那个帧进行发送，使其以最优效率的次序进行传输。这里检查这个队列中是否有enqueue函数，如果有则说明设备会使用这个队列，否则需另外处理。关于enqueue函数的设置，我找到dev_open->dev_activate中调用了qdisc_create_dflt来设置，需要注意的是，这里并不是将传进来的skb直接发送，而是先入队，然后调度队列，具体发送哪个数据包由enqueue和dequeue函数决定，这体现了设备的排队规则    

Enqueue 把一个元素添加的队列

Dequeue 从队列中提取一个元素

Requeue 把一个原先已经提取的元素放回到队列，可以由于传输失败。

if (q->enqueue)为真的话，表明这个设备有队列，可以进行相关的流控。调用__dev_xmit_skb函数进行处理。

```
	static inline int __dev_xmit_skb(struct sk_buff *skb, struct Qdisc *q,
					 struct net_device *dev,
					 struct netdev_queue *txq)
	{
		spinlock_t *root_lock = qdisc_lock(q);
		bool contended = qdisc_is_running(q);
		int rc;

		/*
		 * Heuristic to force contended enqueues to serialize on a
		 * separate lock before trying to get qdisc main lock.
		 * This permits __QDISC_STATE_RUNNING owner to get the lock more often
		 * and dequeue packets faster.
		 */
		if (unlikely(contended))
			spin_lock(&q->busylock);

		spin_lock(root_lock);
		if (unlikely(test_bit(__QDISC_STATE_DEACTIVATED, &q->state))) {
			kfree_skb(skb);
			rc = NET_XMIT_DROP;
		} else if ((q->flags & TCQ_F_CAN_BYPASS) && !qdisc_qlen(q) &&
			 qdisc_run_begin(q)) {
			/*
			 * This is a work-conserving queue; there are no old skbs
			 * waiting to be sent out; and the qdisc is not running -
			 * xmit the skb directly.
			 */
			if (!(dev->priv_flags & IFF_XMIT_DST_RELEASE))
				skb_dst_force(skb);
			__qdisc_update_bstats(q, skb->len);
			if (sch_direct_xmit(skb, q, dev, txq, root_lock)) {
				if (unlikely(contended)) {
					spin_unlock(&q->busylock);
					contended = false;
				}
				__qdisc_run(q);
			} else
				qdisc_run_end(q);

			rc = NET_XMIT_SUCCESS;
		} else {
			skb_dst_force(skb);
			rc = qdisc_enqueue_root(skb, q);
			if (qdisc_run_begin(q)) {
				if (unlikely(contended)) {
					spin_unlock(&q->busylock);
					contended = false;
				}
				__qdisc_run(q);
			}
		}
		spin_unlock(root_lock);
		if (unlikely(contended))
			spin_unlock(&q->busylock);
		return rc;
	}
```

_dev_xmit_skb函数主要做两件事情：  
 （1） 如果流控对象为空的，试图直接发送数据包。  
 （2） 如果流控对象不空，将数据包加入流控对象，并运行流控对象。

当设备进入调度队列准备传输时，qdisc_run函数就会选出下一个要传输的帧，而该函数会间接的调用相关联的队列规则dequeue函数，从对了中取出数据进行传输。

有两个时机将会调用qdisc_run()：  
  1.`__dev_xmit_skb()`  
  2.软中断服务线程NET_TX_SOFTIRQ  

其实，真正的工作有qdisc_restart函数实现。

```
	void __qdisc_run(struct Qdisc *q)
	{
		unsigned long start_time = jiffies;

		while (qdisc_restart(q)) { //返回值大于0，说明流控对象非空。
			/*
			 * Postpone processing if
			 * 1. another process needs the CPU;
			 * 2. we've been doing it for too long.
			 */
			if (need_resched() || jiffies != start_time) { //已经不允许继续运行本流控对象。
				__netif_schedule(q); //将本队列加入软中断的output_queue链表中。
				break;
			}
		}

		qdisc_run_end(q);
	}
```

如果发现本队列运行的时间太长了，将会停止队列的运行，并将队列加入output_queue链表头。


```
	static inline int qdisc_restart(struct Qdisc *q)
	{
		struct netdev_queue *txq;
		struct net_device *dev;
		spinlock_t *root_lock;
		struct sk_buff *skb;

		/* Dequeue packet */
		skb = dequeue_skb(q);//一开始就调用dequeue函数。
		if (unlikely(!skb))
			return 0;
		WARN_ON_ONCE(skb_dst_is_noref(skb));
		root_lock = qdisc_lock(q);
		dev = qdisc_dev(q);
		txq = netdev_get_tx_queue(dev, skb_get_queue_mapping(skb));

		return sch_direct_xmit(skb, q, dev, txq, root_lock);//用于发送数据包
	}
	* Returns to the caller:
	 *                0 - queue is empty or throttled.
	 *                >0 - queue is not empty.
	 */
	int sch_direct_xmit(struct sk_buff *skb, struct Qdisc *q,
			 struct net_device *dev, struct netdev_queue *txq,
			 spinlock_t *root_lock)
	{
		int ret = NETDEV_TX_BUSY;

		/* And release qdisc */
		spin_unlock(root_lock);

		HARD_TX_LOCK(dev, txq, smp_processor_id());
		if (!netif_tx_queue_stopped(txq) && !netif_tx_queue_frozen(txq)) //设备没有被停止，且发送队列没有被冻结
			ret = dev_hard_start_xmit(skb, dev, txq); //发送数据包

		HARD_TX_UNLOCK(dev, txq);

		spin_lock(root_lock);

		if (dev_xmit_complete(ret)) {
			/* Driver sent out skb successfully or skb was consumed */
			//发送成功，返回新的队列的长度
			ret = qdisc_qlen(q);
		} else if (ret == NETDEV_TX_LOCKED) {
			/* Driver try lock failed */
			ret = handle_dev_cpu_collision(skb, txq, q);
		} else {
			/* Driver returned NETDEV_TX_BUSY - requeue skb */
			if (unlikely (ret != NETDEV_TX_BUSY && net_ratelimit()))
				printk(KERN_WARNING "BUG %s code %d qlen %d\n",
				 dev->name, ret, q->q.qlen);
			 //设备繁忙，重新调度发送（利用softirq）
			ret = dev_requeue_skb(skb, q);
		}

		if (ret && (netif_tx_queue_stopped(txq) ||
			 netif_tx_queue_frozen(txq)))
			ret = 0;

		return ret;
	}
```

##### 4. 我们看一下下面的发送函数。

 从此函数可以看出，当驱动使用发送队列的时候会循环从队列中取出包发送, 而不使用队列的时候只发送一次，如果没发送成功就直接丢弃

```
	struct netdev_queue *txq)
	{
		const struct net_device_ops *ops = dev->netdev_ops;//驱动程序的函数集
		int rc = NETDEV_TX_OK;

		if (likely(!skb->next)) {
			if (!list_empty(&ptype_all))
				dev_queue_xmit_nit(skb, dev);//如果dev_add_pack加入的是ETH_P_ALL，那么就会复制一份给你的回调函数。

			/*
			 * If device doesnt need skb->dst, release it right now while
			 * its hot in this cpu cache
			 */
			if (dev->priv_flags & IFF_XMIT_DST_RELEASE)
				skb_dst_drop(skb);

			skb_orphan_try(skb);

			if (vlan_tx_tag_present(skb) &&
			 !(dev->features & NETIF_F_HW_VLAN_TX)) {
				skb = __vlan_put_tag(skb, vlan_tx_tag_get(skb));
				if (unlikely(!skb))
					goto out;

				skb->vlan_tci = 0;
			}

			if (netif_needs_gso(dev, skb)) {
				if (unlikely(dev_gso_segment(skb)))
					goto out_kfree_skb;
				if (skb->next)
					goto gso;
			} else {
				if (skb_needs_linearize(skb, dev) &&
				 __skb_linearize(skb))
					goto out_kfree_skb;

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
			}

			rc = ops->ndo_start_xmit(skb, dev);//调用网卡的驱动程序发送数据。不同的网络设备有不同的发送函数
			trace_net_dev_xmit(skb, rc);
			if (rc == NETDEV_TX_OK)
				txq_trans_update(txq);
			return rc;
		}

	gso:
		do {
			struct sk_buff *nskb = skb->next;

			skb->next = nskb->next;
			nskb->next = NULL;

			/*
			 * If device doesnt need nskb->dst, release it right now while
			 * its hot in this cpu cache
			 */
			if (dev->priv_flags & IFF_XMIT_DST_RELEASE)
				skb_dst_drop(nskb);

			rc = ops->ndo_start_xmit(nskb, dev); //调用网卡的驱动程序发送数据。不同的网络设备有不同的发送函数
			trace_net_dev_xmit(nskb, rc);
			if (unlikely(rc != NETDEV_TX_OK)) {
				if (rc & ~NETDEV_TX_MASK)
					goto out_kfree_gso_skb;
				nskb->next = skb->next;
				skb->next = nskb;
				return rc;
			}
			txq_trans_update(txq);
			if (unlikely(netif_tx_queue_stopped(txq) && skb->next))
				return NETDEV_TX_BUSY;
		} while (skb->next);

	out_kfree_gso_skb:
		if (likely(skb->next == NULL))
			skb->destructor = DEV_GSO_CB(skb)->destructor;
	out_kfree_skb:
		kfree_skb(skb);
	out:
		return rc;
	}
```

##### 5.下面看一下dev_queue_xmit_nit函数。
对于通过socket(AF_PACKET,SOCK_RAW,htons(ETH_P_ALL))创建的原始套接口，不但可以接受从外部输入的数据包，而且对于由于本地输出的数据包，如果满足条件，也可以能接受。

该函数就是用来接收由于本地输出的数据包，在链路层的输出过程中，会调用此函数，将满足条件的数据包输入到RAW套接口，

```
	static void dev_queue_xmit_nit(struct sk_buff *skb, struct net_device *dev)
	{
		struct packet_type *ptype;

	#ifdef CONFIG_NET_CLS_ACT
		if (!(skb->tstamp.tv64 && (G_TC_FROM(skb->tc_verd) & AT_INGRESS)))
			net_timestamp_set(skb);-----------------（1）
	#else
		net_timestamp_set(skb);
	#endif

		rcu_read_lock();
		list_for_each_entry_rcu(ptype, &ptype_all, list) {-----------------（2）
			/* Never send packets back to the socket
			 * they originated from - MvS (miquels@drinkel.ow.org)
			 */
			if ((ptype->dev == dev || !ptype->dev) &&
			 (ptype->af_packet_priv == NULL ||
			 (struct sock *)ptype->af_packet_priv != skb->sk)) {-----------------（3）
				struct sk_buff *skb2 = skb_clone(skb, GFP_ATOMIC); -----------------（4）
				if (!skb2)
					break;

				/* skb->nh should be correctly
				 set by sender, so that the second statement is
				 just protection against buggy protocols.
				 */
				skb_reset_mac_header(skb2);

				if (skb_network_header(skb2) < skb2->data ||
				 skb2->network_header > skb2->tail) {
					if (net_ratelimit())
						printk(KERN_CRIT "protocol %04x is "
						 "buggy, dev %s\n",
						 ntohs(skb2->protocol),
						 dev->name);
					skb_reset_network_header(skb2); -----------------（5）
				}

				skb2->transport_header = skb2->network_header;
				skb2->pkt_type = PACKET_OUTGOING;
				ptype->func(skb2, skb->dev, ptype, skb->dev); -----------------（6）
			}
		}
		rcu_read_unlock();
	}
```

说明：  
（1） 记录该数据包输入的时间戳  
（2） 遍历ptype_all链表，查找所有符合输入条件的原始套接口，并循环将数据包输入到满足条件的套接口  
（3） 数据包的输出设备与套接口的输入设备相符或者套接口不指定输入设备，并且该数据包不是有当前用于比较的套接口输出，此时该套接口满足条件，数据包可以输入  
（4） 由于该数据包是额外输入到这个原始套接口的，因此需要克隆一个数据包  
（5） 校验数据包是否有效  
（6） 将数据包输入原始套接口  

##### 6. 对于lookback设备来说处理有些不同。它的hard_start_xmit函数是loopback_xmit

在net/lookback.c文件中，定义的struct net_device_ops loopback_ops结构体

```
	static const struct net_device_ops loopback_ops = {
		.ndo_init = loopback_dev_init,
		.ndo_start_xmit= loopback_xmit,
		.ndo_get_stats64 = loopback_get_stats64,
	};
```

从这里可以看到起发送函数为loopback_xmit函数。

```
	static netdev_tx_t loopback_xmit(struct sk_buff *skb,
					 struct net_device *dev)
	{
		struct pcpu_lstats *lb_stats;
		int len;

		skb_orphan(skb);

		skb->protocol = eth_type_trans(skb, dev);

		/* it's OK to use per_cpu_ptr() because BHs are off */
		lb_stats = this_cpu_ptr(dev->lstats);

		len = skb->len;
		if (likely(netif_rx(skb) == NET_RX_SUCCESS)) {//直接调用了netif_rx进行了接收处理
			u64_stats_update_begin(&lb_stats->syncp);
			lb_stats->bytes += len;
			lb_stats->packets++;
			u64_stats_update_end(&lb_stats->syncp);
		}

		return NETDEV_TX_OK;
	}
```

##### 7. 已经有了dev_queue_xmit函数，为什么还需要软中断来发送呢？

dev_queue_xmit是对skb做些最后的处理并且第一次尝试发送,软中断是将前者发送失败或者没发完的包发送出去。

主要参考文献：

Linux发送函数dev_queue_xmit分析  http://shaojiashuai123456.iteye.com/blog/842236 

TC流量控制实现分析（初步）  http://blog.csdn.net/wwwlkk/article/details/5929308

Linux内核源码剖析 TCP/IP实现

