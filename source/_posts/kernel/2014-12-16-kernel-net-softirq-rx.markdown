---
layout: post
title: "收包软中断和netif_rx"
date: 2014-12-16 15:30:00 +0800
comments: false
categories:
- 2014
- 2014~12
- kernel
- kernel~net
tags:
---
##### 初始化报文接收软中断
```
	static int __init net_dev_init(void)
	{
		......
		open_softirq(NET_RX_SOFTIRQ, net_rx_action);
		......
	}
```

##### 报文接收软中断的处理函数net_rx_action详解：
```
	static void net_rx_action(struct softirq_action *h)
	{
		/*取得本地cpu 的softnet_data 的poll_list  链表*/
		struct list_head *list = &__get_cpu_var(softnet_data).poll_list;
		/*设置软中断处理程序一次允许的最大执行时间为2个jiffies*/
		unsigned long time_limit = jiffies + 2;

		/*设置软中断接收函数一次最多处理的报文个数为 300 */
		int budget = netdev_budget;
		/*关闭本地cpu的中断，下面判断list是否为空时防止硬中断抢占*/
		local_irq_disable();
		/*循环处理pool_list 链表上的等待处理的napi*/
		while (!list_empty(list))
		{
			struct napi_struct *n;
			int work, weight;

			/*如果处理报文超出一次处理最大的个数
			  或允许时间超过最大时间就停止执行，
			  跳到softnet_break 处*/
			if (unlikely(budget <= 0 || time_after(jiffies, time_limit)))
			{
				goto softnet_break;
			}
			/*使能本地中断，上面判断list为空已完成，下面调用NAPI
			  的轮询函数是在硬中断开启的情况下执行*/
			local_irq_enable();

			/* 取得softnet_data pool_list 链表上的一个napi,
			   即使现在硬中断抢占软中断，会把一个napi挂到pool_list的尾端
			   软中断只会从pool_list 头部移除一个pool_list，这样不存在临界区*/
			n = list_entry(list->next, struct napi_struct, poll_list);
			/*用weighe 记录napi 一次轮询允许处理的最大报文数*/
			weight = n->weight;
			/* work 记录一个napi总共处理的报文数*/
			work = 0;

			/*如果取得的napi状态是被调度的，就执行napi的轮询处理函数*/
			if (test_bit(NAPI_STATE_SCHED, &n->state))
			{
				work = n->poll(n, weight);
			}
			WARN_ON_ONCE(work > weight);
			/*预算减去已经处理的报文数*/
			budget -= work;
			/*禁止本地CPU 的中断，下面会有把没执行完的NAPI挂到softnet_data
			  尾部的操作，和硬中断存在临界区。同时while循环时判断list是否
			  为空时也要禁止硬中断抢占*/
			local_irq_disable();

			/*如果napi 一次轮询处理的报文数正好等于允许处理的最大数,
			  说明一次轮询没处理完全部需要处理的报文*/
			if (unlikely(work == weight))
			{
				/*如果napi已经被禁用，就把napi 从 softnet_data 的pool_list 上移除*/
				if (unlikely(napi_disable_pending(n)))
				{
					local_irq_enable();
					napi_complete(n);
					local_irq_disable();
				}
				else
				{
					/*否则，把napi 移到 pool_list 的尾端*/
					list_move_tail(&n->poll_list, list);
				}
			}
		}
	out:
		local_irq_enable();
		return;

		/*如果处理时间超时，或处理的报文数到了最多允许处理的个数，
		  说明还有napi 上有报文需要处理，调度软中断。
		  否则，说明这次软中断处理完全部的napi上的需要处理的报文，不再需要
		  调度软中断了*/
	softnet_break:
		__get_cpu_var(netdev_rx_stat).time_squeeze++;
		__raise_softirq_irqoff(NET_RX_SOFTIRQ);
		goto out;
	}
```

##### 虚拟NAPI backlog 的轮询函数process_backlog（）:  
参数：  
napi : 本地cpu上softnet_data 的backlog .  
quota :  一次轮询可以处理的最多报文数。

###### 函数详解：
```	
	static int process_backlog(struct napi_struct *napi, int quota)
	{
		int work = 0;

		/*取得本地CPU上的softnet_data  数据*/
		struct softnet_data *queue = &__get_cpu_var(softnet_data);

		/*开始计时，一旦允许时间到，就退出轮询*/
		unsigned long start_time = jiffies;
		napi->weight = weight_p;

		/*循环从softnet_data 的输入队列取报文并处理，直到队列中没有报文了,
		 或处理的报文数大于了允许的上限值了，
		 或轮询函数执行时间大于一个jiffies 了
		*/
		do
		{
			struct sk_buff *skb;
			/*禁用本地中断，要存队列中取skb,防止抢占*/
			local_irq_disable();

			/*从softnet_data 的输入队列中取得一个skb*/
			skb = __skb_dequeue(&queue->input_pkt_queue);

			/*如果队列中没有skb,则使能中断并退出轮询*/
			if (!skb)
			{
				/*把napi 从 softnet_data 的 pool_list 链表上摘除*/
				__napi_complete(napi);
				/*使能本地CPU的中断*/
				local_irq_enable();
				break;
			}
			/*skb 已经摘下来了，使能中断*/
			local_irq_enable();

			/*把skb送到协议栈相关协议模块进行处理,详细处理见后续章节*/
			netif_receive_skb(skb);
		} while (++work < quota && jiffies == start_time);
		/*返回处理报文个数*/
		return work;
	}
```

##### linux旧的收包方式提供给驱动的接口netif_rx():
```	
	int netif_rx(struct sk_buff *skb)
	{
		struct softnet_data *queue;
		unsigned long flags;

		/*如果接收skb的时间戳没设定，设定接收时间戳*/
		if (!skb->tstamp.tv64)
		{
			net_timestamp(skb);
		}

		/*禁止本地cpu的中断*/
		local_irq_save(flags);

		/*取得本地cpu的softnet_data*/
		queue = &__get_cpu_var(softnet_data);
					   
		/*每个CPU都有一个统计数据，增加统计数据*/
		__get_cpu_var(netdev_rx_stat).total++;

		/*如果本地CPU的输入队列中的skb 个数小于允许的最多的个数*/
		if (queue->input_pkt_queue.qlen <= netdev_max_backlog)
		{
			/*如果本地cpu的输入队列长度不为0,表示输入队列已经有skb了，
			并且特殊的napi backlog 已经挂入了softnet_data  的
			pool_list上了*/
			if (queue->input_pkt_queue.qlen)
			{
	enqueue:
				/*把skb 放入CPU的输入队列 input_pkt_queue*/
				__skb_queue_tail(&queue->input_pkt_queue, skb);
						  
				/*使能中断 并 返回*/
				local_irq_restore(flags);
				return NET_RX_SUCCESS;
			}
			/*如果输入队列为空，则把 特殊的napi backlog 挂到softnet_data
			的 pool_list 上 并返回把skb放入输入队列并返回*/
			napi_schedule(&queue->backlog);
			goto enqueue;
		}
		/*如果本地cpu的输入队列已经满了，则丢弃报文，
		  并增加丢包计数并返回*/
		__get_cpu_var(netdev_rx_stat).dropped++;
		local_irq_restore(flags);

		kfree_skb(skb);
		return NET_RX_DROP;
	}
```

