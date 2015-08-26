---
layout: post
title: "NAPI机制分析"
date: 2015-08-26 25:29:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/shanshanpt/article/details/20564845

NAPI 的核心在于：在一个繁忙网络，每次有网络数据包到达时，不需要都引发中断，因为高频率的中断可能会影响系统的整体效率，假象一个场景，我们此时使用标准的 100M 网卡，可能实际达到的接收速率为 80MBits/s，而此时数据包平均长度为 1500Bytes，则每秒产生的中断数目为：
```
	80M bits/s / (8 Bits/Byte * 1500 Byte) = 6667 个中断 /s
```

每秒 6667 个中断，对于系统是个很大的压力，此时其实可以转为使用轮询 (polling) 来处理，而不是中断;但轮询在网络流量较小的时没有效率，因此低流量时，基于中断的方式则比较合适，这就是 NAPI 出现的原因，在低流量时候使用中断接收数据包，而在高流量时候则使用基于轮询的方式接收。

现在内核中 NIC 基本上已经全部支持 NAPI 功能，由前面的叙述可知，NAPI 适合处理高速率数据包的处理，而带来的好处则是：

  1、中断缓和 (Interrupt mitigation)，由上面的例子可以看到，在高流量下，网卡产生的中断可能达到每秒几千次，而如果每次中断都需要系统来处理，是一个很大的压力，而 NAPI 使用轮询时是禁止了网卡的接收中断的，这样会减小系统处理中断的压力；

  2、数据包节流 (Packet throttling)，NAPI 之前的 Linux NIC 驱动总在接收到数据包之后产生一个 IRQ，接着在中断服务例程里将这个 skb 加入本地的 softnet，然后触发本地 NET_RX_SOFTIRQ 软中断后续处理。如果包速过高，因为 IRQ 的优先级高于 SoftIRQ，导致系统的大部分资源都在响应中断，但 softnet 的队列大小有限，接收到的超额数据包也只能丢掉，所以这时这个模型是在用宝贵的系统资源做无用功。而 NAPI 则在这样的情况下，直接把包丢掉，不会继续将需要丢掉的数据包扔给内核去处理，这样，网卡将需要丢掉的数据包尽可能的早丢弃掉，内核将不可见需要丢掉的数据包，这样也减少了内核的压力。

对NAPI 的使用，一般包括以下的几个步骤：

  1、在中断处理函数中，先禁止接收中断，且告诉网络子系统，将以轮询方式快速收包，其中禁止接收中断完全由硬件功能决定，而告诉内核将以轮询方式处理包则是使用函数 netif_rx_schedule()，也可以使用下面的方式，其中的 netif_rx_schedule_prep 是为了判定现在是否已经进入了轮询模式：

将网卡预定为轮询模式
```
	void netif_rx_schedule(struct net_device *dev);
```
或者
```
	if (netif_rx_schedule_prep(dev))
		__netif_rx_schedule(dev);
```

  2、在驱动中创建轮询函数，它的工作是从网卡获取数据包并将其送入到网络子系统，其原型是：

NAPI 的轮询方法
```
	int (*poll)(struct net_device *dev, int *budget);
```

这里的轮询函数用于在将网卡切换为轮询模式之后，用 poll() 方法处理接收队列中的数据包，如队列为空，则重新切换为中断模式。切换回中断模式需要先关闭轮询模式，使用的是函数 netif_rx_complete ()，接着开启网卡接收中断 .。

退出轮询模式
```
	void netif_rx_complete(struct net_device *dev);
```

  3、在驱动中创建轮询函数，需要和实际的网络设备 struct net_device 关联起来，这一般在网卡的初始化时候完成，示例代码如下：

设置网卡支持轮询模式
```
	dev->poll = my_poll;
	dev->weight = 64;
```

里面另外一个字段为权重 (weight)，该值并没有一个非常严格的要求，实际上是个经验数据，一般 10Mb 的网卡，我们设置为 16，而更快的网卡，我们则设置为 64。

NAPI的一些相关Interface

下面是 NAPI 功能的一些接口，在前面都基本有涉及，我们简单看看：

```
	netif_rx_schedule(dev)
```

在网卡的中断处理函数中调用，用于将网卡的接收模式切换为轮询

```
	netif_rx_schedule_prep(dev)
```

在网卡是 Up 且运行状态时，将该网卡设置为准备将其加入到轮询列表的状态，可以将该函数看做是 netif_rx_schedule(dev) 的前半部分
```
	__netif_rx_schedule(dev)
```

将设备加入轮询列表，前提是需要 netif_schedule_prep(dev) 函数已经返回了 1

```
	__netif_rx_schedule_prep(dev)
```

与 netif_rx_schedule_prep(dev) 相似，但是没有判断网卡设备是否 Up 及运行，不建议使用

```
	netif_rx_complete(dev)
```

用于将网卡接口从轮询列表中移除，一般在轮询函数完成之后调用该函数。

```
	__netif_rx_complete(dev)
```

#### Newer newer NAPI

其实之前的 NAPI(New API) 这样的命名已经有点让人忍俊不禁了，可见 Linux 的内核极客们对名字的掌控，比对代码的掌控差太多，于是乎，连续的两次对 NAPI 的重构，被戏称为 Newer newer NAPI 了。

与 netif_rx_complete(dev) 类似，但是需要确保本地中断被禁止

Newer newer NAPI

在最初实现的 NAPI 中，有 2 个字段在结构体 net_device 中，分别为轮询函数 poll() 和权重 weight，而所谓的 Newer newer NAPI，是在 2.6.24 版内核之后，对原有的 NAPI 实现的几次重构，其核心是将 NAPI 相关功能和 net_device 分离，这样减少了耦合，代码更加的灵活，因为 NAPI 的相关信息已经从特定的网络设备剥离了，不再是以前的一对一的关系了。例如有些网络适配器，可能提供了多个 port，但所有的 port 却是共用同一个接受数据包的中断，这时候，分离的 NAPI 信息只用存一份，同时被所有的 port 来共享，这样，代码框架上更好地适应了真实的硬件能力。Newer newer NAPI 的中心结构体是napi_struct:

NAPI 结构体
```
	/* 
	 * Structure for NAPI scheduling similar to tasklet but with weighting 
	*/ 
	struct napi_struct { 
		/* The poll_list must only be managed by the entity which 
		 * changes the state of the NAPI_STATE_SCHED bit.  This means 
		 * whoever atomically sets that bit can add this napi_struct 
		 * to the per-cpu poll_list, and whoever clears that bit 
		 * can remove from the list right before clearing the bit. 
		 */ 
		struct list_head      poll_list; 

		unsigned long          state; 
		int              weight; 
		int              (*poll)(struct napi_struct *, int); 
	 #ifdef CONFIG_NETPOLL 
		spinlock_t          poll_lock; 
		int              poll_owner; 
	 #endif 

		unsigned int          gro_count; 

		struct net_device      *dev; 
		struct list_head      dev_list; 
		struct sk_buff          *gro_list; 
		struct sk_buff          *skb; 
	};
```

熟悉老的 NAPI 接口实现的话，里面的字段 poll_list、state、weight、poll、dev、没什么好说的，gro_count 和 gro_list 会在后面讲述 GRO 时候会讲述。需要注意的是，与之前的 NAPI 实现的最大的区别是该结构体不再是 net_device 的一部分，事实上，现在希望网卡驱动自己单独分配与管理 napi 实例，通常将其放在了网卡驱动的私有信息，这样最主要的好处在于，如果驱动愿意，可以创建多个 napi_struct，因为现在越来越多的硬件已经开始支持多接收队列 (multiple receive queues)，这样，多个 napi_struct 的实现使得多队列的使用也更加的有效。

与最初的 NAPI 相比较，轮询函数的注册有些变化，现在使用的新接口是：
```
	void netif_napi_add(struct net_device *dev, struct napi_struct *napi, 
						int (*poll)(struct napi_struct *, int), int weight)
```

熟悉老的 NAPI 接口的话，这个函数也没什么好说的。

值得注意的是，前面的轮询 poll() 方法原型也开始需要一些小小的改变：
```
	int (*poll)(struct napi_struct *napi, int budget);
```

大部分 NAPI 相关的函数也需要改变之前的原型，下面是打开轮询功能的 API：
```
	void netif_rx_schedule(struct net_device *dev, 
							struct napi_struct *napi); 
	/* ...or... */ 
	int netif_rx_schedule_prep(struct net_device *dev, 
							struct napi_struct *napi); 
	void __netif_rx_schedule(struct net_device *dev, 
							struct napi_struct *napi);
```

轮询功能的关闭则需要使用：
```
	void netif_rx_complete(struct net_device *dev, 
							struct napi_struct *napi);
```

因为可能存在多个 napi_struct 的实例，要求每个实例能够独立的使能或者禁止，因此，需要驱动作者保证在网卡接口关闭时，禁止所有的 napi_struct 的实例。

函数 netif_poll_enable() 和 netif_poll_disable() 不再需要，因为轮询管理不再和 net_device 直接管理，取而代之的是下面的两个函数：
```
	void napi_enable(struct napi *napi); 
	void napi_disable(struct napi *napi);
```

