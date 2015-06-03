---
layout: post
title: "Receive packet steering patch详解"
date: 2015-06-03 15:39:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://simohayha.iteye.com/blog/720850

Receive packet steering简称rps，是google贡献给linux kernel的一个patch，主要的功能是解决多核情况下，网络协议栈的软中断的负载均衡。这里的负载均衡也就是指能够将软中断均衡的放在不同的cpu核心上运行。

简介在这里：  
http://lwn.net/Articles/362339/

linux现在网卡的驱动支持两种模式，一种是NAPI，一种是非NAPI模式，这两种模式的区别，我前面的blog都有介绍，这里就再次简要的介绍下。

在NAPI中，中断收到数据包后调用__napi_schedule调度软中断，然后软中断处理函数中会调用注册的poll回掉函数中调用netif_receive_skb将数据包发送到3层，没有进行任何的软中断负载均衡。

在非NAPI中，中断收到数据包后调用netif_rx，这个函数会将数据包保存到input_pkt_queue，然后调度软中断，这里为了兼容NAPI的驱动，他的poll方法默认是process_backlog，最终这个函数会从input_pkt_queue中取得数据包然后发送到3层。

通过比较我们可以看到，不管是NAPI还是非NAPI的话都无法做到软中断的负载均衡，因为软中断此时都是运行在在硬件中断相应的cpu上。也就是说如果始终是cpu0相应网卡的硬件中断，那么始终都是cpu0在处理软中断，而此时cpu1就被浪费了，因为无法并行的执行多个软中断。

google的这个patch的基本原理是这样的,根据数据包的源地址，目的地址以及目的和源端口(这里它是将两个端口组合成一个4字节的无符数进行计算的，后面会看到)计算出一个hash值，然后根据这个hash值来选择软中断运行的cpu，从上层来看，也就是说将每个连接和cpu绑定，并通过这个hash值，来均衡软中断在多个cpu上。

这个介绍比较简单，我们来看代码是如何实现的。

它这里主要是hook了两个内核的函数，一个是netif_rx主要是针对非NAPI的驱动，一个是netif_receive_skb这个主要是针对NAPI的驱动，这两个函数我前面blog都有介绍过，想了解可以看我前面的blog，现在这里我只介绍打过patch的实现。

在看netif_rx和netif_receive_skb之前，我们先来看这个patch中两个重要的函数get_rps_cpu和enqueue_to_backlog，我们一个个看。

先来看相关的两个数据结构，首先是netdev_rx_queue，它表示对应的接收队列，因为有的网卡可能硬件上就支持多队列的模式，此时对应就会有多个rx队列，这个结构是挂载在net_device中的，也就是每个网络设备最终都会有一个或者多个rx队列。这个结构在sys文件系统中的表示类似这样的/sys/class/net/<device>/queues/rx-<n> 几个队列就是rx-n.
```
	struct netdev_rx_queue {
		// 保存了当前队列的rps map
		struct rps_map *rps_map;
		// 对应的kobject
		struct kobject kobj;
		// 指向第一个rx队列
		struct netdev_rx_queue *first;
		// 引用计数
		atomic_t count;
	} ____cacheline_aligned_in_smp;
```


然后就是rps_map，其实这个也就是保存了能够执行数据包的cpu。
```
	struct rps_map {
		// cpu的个数，也就是cpus数组的个数
		unsigned int len;
		// RCU锁
		struct rcu_head rcu;
		// 保存了cpu的id.
		u16 cpus[0];
	};
```


看完上面的结构，我们来看函数的实现。
get_rps_cpu主要是通过传递进来的skb然后来选择这个skb所应该被处理的cpu。它的逻辑很简单，就是通过skb计算hash，然后通过hash从对应的队列的rps_mapping中取得对应的cpu id。

这里有个要注意的就是这个hash值是可以交给硬件网卡去计算的，作者自己说是最好交由硬件去计算这个hash值，因为如果是软件计算的话会导致CPU 缓存不命中，带来一定的性能开销。

还有就是rps_mapping这个值是可以通过sys 文件系统设置的，位置在这里：
/sys/class/net/<device>/queues/rx-<n>/rps_cpus 。

```
	static int get_rps_cpu(struct net_device *dev, struct sk_buff *skb)
	{
		struct ipv6hdr *ip6;
		struct iphdr *ip;
		struct netdev_rx_queue *rxqueue;
		struct rps_map *map;
		int cpu = -1;
		u8 ip_proto;
		u32 addr1, addr2, ports, ihl;
		// rcu锁
		rcu_read_lock();
		// 取得设备对应的rx 队列
		if (skb_rx_queue_recorded(skb)) {
		..........................................
			rxqueue = dev->_rx + index;
		} else
			rxqueue = dev->_rx;

		if (!rxqueue->rps_map)
			goto done;
		// 如果硬件已经计算，则跳过计算过程
		if (skb->rxhash)
			goto got_hash; /* Skip hash computation on packet header */

		switch (skb->protocol) {
		case __constant_htons(ETH_P_IP):
			if (!pskb_may_pull(skb, sizeof(*ip)))
				goto done;
			// 得到计算hash的几个值
			ip = (struct iphdr *) skb->data;
			ip_proto = ip->protocol;
			// 两个地址
			addr1 = ip->saddr;
			addr2 = ip->daddr;
			// 得到ip头
			ihl = ip->ihl;
			break;
		case __constant_htons(ETH_P_IPV6):
			..........................................
			break;
		default:
			goto done;
		}
		ports = 0;
		switch (ip_proto) {
		case IPPROTO_TCP:
		case IPPROTO_UDP:
		case IPPROTO_DCCP:
		case IPPROTO_ESP:
		case IPPROTO_AH:
		case IPPROTO_SCTP:
		case IPPROTO_UDPLITE:
			if (pskb_may_pull(skb, (ihl * 4) + 4))
			// 我们知道tcp头的前4个字节就是源和目的端口，因此这里跳过ip头得到tcp头的前4个字节
				ports = *((u32 *) (skb->data + (ihl * 4)));
			break;

		default:
			break;
		}
		// 计算hash
		skb->rxhash = jhash_3words(addr1, addr2, ports, hashrnd);
		if (!skb->rxhash)
			skb->rxhash = 1;

	got_hash:
		// 通过rcu得到对应rps map
		map = rcu_dereference(rxqueue->rps_map);
		if (map) {
			// 取得对应的cpu
			u16 tcpu = map->cpus[((u64) skb->rxhash * map->len) >> 32];
			// 如果cpu是online的，则返回计算出的这个cpu，否则跳出循环。
			if (cpu_online(tcpu)) {
				cpu = tcpu;
				goto done;
			}
		}

	done:
		rcu_read_unlock();
		// 如果上面失败，则返回-1.
		return cpu;
	}
```


然后是enqueue_to_backlog这个方法，首先我们知道在每个cpu都有一个softnet结构，而他有一个input_pkt_queue的队列，以前这个主要是用于非NAPi的驱动的，而这个patch则将这个队列也用与NAPI的处理中了。也就是每个cpu现在都会有一个input_pkt_queue队列，用于保存需要处理的数据包队列。这个队列作用现在是，如果发现不属于当前cpu处理的数据包，则我们可以直接将数据包挂载到他所属的cpu的input_pkt_queue中。

enqueue_to_backlog接受一个skb和cpu为参数，通过cpu来判断skb如何处理。要么加入所属的input_pkt_queue中，要么schecule 软中断。

还有个要注意就是我们知道NAPI为了兼容非NAPI模式，有个backlog的napi_struct结构，也就是非NAPI驱动会schedule backlog这个napi结构，而在enqueue_to_backlog中则是利用了这个结构，也就是它会schedule backlog，因为它会将数据放到input_pkt_queue中，而backlog的pool方法process_backlog就是从input_pkt_queue中取得数据然后交给上层处理。

这里还有一个会用到结构就是 rps_remote_softirq_cpus，它主要是保存了当前cpu上需要去另外的cpu schedule 软中断的cpu 掩码。因为我们可能将要处理的数据包放到了另外的cpu的input queue上，因此我们需要schedule 另外的cpu上的napi(也就是软中断),所以我们需要保存对应的cpu掩码，以便于后面遍历，然后schedule。

而这里为什么mask有两个元素，注释写的很清楚：
```
	/*
	 * This structure holds the per-CPU mask of CPUs for which IPIs are scheduled
	 * to be sent to kick remote softirq processing.  There are two masks since
	 * the sending of IPIs must be done with interrupts enabled.  The select field
	 * indicates the current mask that enqueue_backlog uses to schedule IPIs.
	 * select is flipped before net_rps_action is called while still under lock,
	 * net_rps_action then uses the non-selected mask to send the IPIs and clears
	 * it without conflicting with enqueue_backlog operation.
	 */
	struct rps_remote_softirq_cpus {
		// 对应的cpu掩码
		cpumask_t mask[2];
		// 表示应该使用的数组索引
		int select;
	};
```

```
	static int enqueue_to_backlog(struct sk_buff *skb, int cpu)
	{
		struct softnet_data *queue;
		unsigned long flags;
		// 取出传递进来的cpu的softnet-data结构
		queue = &per_cpu(softnet_data, cpu);

		local_irq_save(flags);
		__get_cpu_var(netdev_rx_stat).total++;
		// 自旋锁
		spin_lock(&queue->input_pkt_queue.lock);
		// 如果保存的队列还没到上限
		if (queue->input_pkt_queue.qlen <= netdev_max_backlog) {
		// 如果当前队列的输入队列长度不为空
			if (queue->input_pkt_queue.qlen) {
	enqueue:
				// 将数据包加入到input_pkt_queue中,这里会有一个小问题，我们后面再说。
				__skb_queue_tail(&queue->input_pkt_queue, skb);
				spin_unlock_irqrestore(&queue->input_pkt_queue.lock,
					flags);
				return NET_RX_SUCCESS;
			}

			/* Schedule NAPI for backlog device */
			// 如果可以调度软中断
			if (napi_schedule_prep(&queue->backlog)) {
				// 首先判断数据包该不该当前的cpu处理
				if (cpu != smp_processor_id()) {
					// 如果不该，
					struct rps_remote_softirq_cpus *rcpus =
						&__get_cpu_var(rps_remote_softirq_cpus);

					cpu_set(cpu, rcpus->mask[rcpus->select]);
					__raise_softirq_irqoff(NET_RX_SOFTIRQ);
				} else
					// 如果就是应该当前cpu处理，则直接schedule 软中断，这里可以看到传递进去的是backlog
					__napi_schedule(&queue->backlog);
			}
			goto enqueue;
		}

		spin_unlock(&queue->input_pkt_queue.lock);

		__get_cpu_var(netdev_rx_stat).dropped++;
		local_irq_restore(flags);

		kfree_skb(skb);
		return NET_RX_DROP;
	}
```


这里会有一个小问题，那就是假设此时一个属于cpu0的包进入处理，此时我们运行在cpu1,此时将数据包加入到input队列，然后cpu0上面刚好又来了一个cpu0需要处理的数据包，此时由于qlen不为0则又将数据包加入到input队列中，我们会发现cpu0上的napi没机会进行调度了。

google的patch对这个是这样处理的，在软中断处理函数中当数据包处理完毕，会调用net_rps_action来调度前面保存到其他cpu上的input队列。

下面就是代码片断（net_rx_action）

```
	// 得到对应的rcpus.
	rcpus = &__get_cpu_var(rps_remote_softirq_cpus);
		select = rcpus->select;
		// 翻转select，防止和enqueue_backlog冲突
		rcpus->select ^= 1;

		// 打开中断，此时下面的调度才会起作用.
		local_irq_enable();
		// 这个函数里面调度对应的远程cpu的napi.
		net_rps_action(&rcpus->mask[select]);
```


然后就是net_rps_action，这个函数很简单，就是遍历所需要处理的cpu，然后调度napi
```
	static void net_rps_action(cpumask_t *mask)
	{
		int cpu;

		/* Send pending IPI's to kick RPS processing on remote cpus. */
		// 遍历
		for_each_cpu_mask_nr(cpu, *mask) {
			struct softnet_data *queue = &per_cpu(softnet_data, cpu);
			if (cpu_online(cpu))
				// 到对应的cpu调用csd方法。
				__smp_call_function_single(cpu, &queue->csd, 0);
		}
		// 清理mask
		cpus_clear(*mask);
	}
```


上面我们看到会调用csd方法，而上面的csd回掉就是被初始化为trigger_softirq函数。
```
	static void trigger_softirq(void *data)
	{
		struct softnet_data *queue = data;
		// 调度napi可以看到依旧是backlog 这个napi结构体。
		__napi_schedule(&queue->backlog);
		__get_cpu_var(netdev_rx_stat).received_rps++;
	}
```


上面的函数都分析完毕了，剩下的就很简单了。

首先来看netif_rx如何被修改的，它被修改的很简单，首先是得到当前skb所应该被处理的cpu id，然后再通过比较这个cpu和当前正在处理的cpu id进行比较来做不同的处理。

```
	int netif_rx(struct sk_buff *skb)
	{
		int cpu;

		/* if netpoll wants it, pretend we never saw it */
		if (netpoll_rx(skb))
			return NET_RX_DROP;

		if (!skb->tstamp.tv64)
			net_timestamp(skb);
		// 得到cpu id。
		cpu = get_rps_cpu(skb->dev, skb);
		if (cpu < 0)
			cpu = smp_processor_id();
		// 通过cpu进行队列不同的处理
		return enqueue_to_backlog(skb, cpu);
	}
```


然后是netif_receive_skb,这里patch将内核本身的这个函数改写为__netif_receive_skb。然后当返回值小于0,则说明不需要对队列进行处理，此时直接发送到3层。
```
	int netif_receive_skb(struct sk_buff *skb)
	{
		int cpu;

		cpu = get_rps_cpu(skb->dev, skb);

		if (cpu < 0)
			return __netif_receive_skb(skb);
		else
			return enqueue_to_backlog(skb, cpu);
	}
```


最后来总结一下，可以看到input_pkt_queue是一个FIFO的队列，而且如果当qlen有值的时候，也就是在另外的cpu有数据包放到input_pkt_queue中，则当前cpu不会调度napi，而是将数据包放到input_pkt_queue中，然后等待trigger_softirq来调度napi。

因此这个patch完美的解决了软中断在多核下的均衡问题，并且没有由于是同一个连接会map到相同的cpu，并且input_pkt_queue的使用，因此乱序的问题也不会出现。

