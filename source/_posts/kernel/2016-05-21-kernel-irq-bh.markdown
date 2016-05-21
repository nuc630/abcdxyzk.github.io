---
layout: post
title: "linux 中断下半部"
date: 2016-05-21 10:40:00 +0800
comments: false
categories:
- 2016
- 2016~05
- kernel
- kernel~irq
tags:
---

http://blog.chinaunix.net/uid-24203478-id-3111803.html

与Linux中断息息相关的一个重要概念是Linux中断分为两个半部：上半部（tophalf）和下半部(bottom half)。上半部的功能是"登记中断"，当一个中断发生时，它进行相应地硬件读写后就把中断例程的下半部挂到该设备的下半部执行队列中去。因此，上半部执行的速度就会很快，可以服务更多的中断请求。但是，仅有"登记中断"是远远不够的，因为中断的事件可能很复杂。因此，Linux引入了一个下半部，来完成中断事件的绝大多数使命。下半部和上半部最大的不同是下半部是可中断的，而上半部是不可中断的，下半部几乎做了中断处理程序所有的事情，而且可以被新的中断打断！下半部则相对来说并不是非常紧急的，通常还是比较耗时的，因此由系统自行安排运行时机，不在中断服务上下文中执行。

#### 在Linux2.6的内核中存在三种不同形式的下半部实现机制：软中断，tasklet和工作队列。

Tasklet基于Linux softirq，其使用相当简单，我们只需要定义tasklet及其处理函数并将二者关联：

```
	void my_tasklet_func(unsigned long); //定义一个处理函数：
	DECLARE_TASKLET(my_tasklet,my_tasklet_func,data); //定义一个tasklet结构my_tasklet，与my_tasklet_func(data)函数相关联
```

然后，在需要调度tasklet的时候引用一个简单的API就能使系统在适当的时候进行调度运行：
```
	tasklet_schedule(&my_tasklet);
```

此外，Linux还提供了另外一些其它的控制tasklet调度与运行的API：
```
	DECLARE_TASKLET_DISABLED(name,function,data); //与DECLARE_TASKLET类似，但等待tasklet被使能
	tasklet_enable(struct tasklet_struct *); //使能tasklet
	tasklet_disble(struct tasklet_struct *); //禁用tasklet
	tasklet_init(struct tasklet_struct *,void (*func)(unsigned long),unsigned long); //类似DECLARE_TASKLET()
	tasklet_kill(struct tasklet_struct *); // 清除指定tasklet的可调度位，即不允许调度该tasklet
```

我们先来看一个tasklet的运行实例，这个实例没有任何实际意义，仅仅为了演示。它的功能是：在globalvar被写入一次后，就调度一个tasklet，函数中输出"tasklet is executing"：

```
	//定义与绑定tasklet函数
	void test_tasklet_action(unsigned long t);
	DECLARE_TASKLET(test_tasklet, test_tasklet_action, 0);

	void test_tasklet_action(unsigned long t)
	{
		printk("tasklet is executing\n");
	}

	...

	ssize_t globalvar_write(struct file *filp, const char *buf, size_t len, loff_t *off)
	{
		...
		if (copy_from_user(&global_var, buf, sizeof(int)))
		{
			return - EFAULT;
		}

		//调度tasklet执行
		tasklet_schedule(&test_tasklet);
		return sizeof(int);
	}
```

下半部分的任务就是执行与中断处理密切相关但中断处理程序本身不执行的工作。

#### 在Linux2.6的内核中存在三种不同形式的下半部实现机制：软中断，tasklet和工作队列。

下面将比较三种机制的差别与联系。
```
	软中断:    1、软中断是在编译期间静态分配的。
	           2、最多可以有32个软中断。
	           3、软中断不会抢占另外一个软中断，唯一可以抢占软中断的是中断处理程序。
	           4、可以并发运行在多个CPU上（即使同一类型的也可以）。所以软中断必须设计为可重入的函数（允许多个CPU同时操作），
	              因此也需要使用自旋锁来保护其数据结构。
	           5、目前只有两个子系直接使用软中断：网络和SCSI。
	           6、执行时间有：从硬件中断代码返回时、在ksoftirqd内核线程中和某些显示检查并执行软中断的代码中。

	tasklet:   1、tasklet是使用两类软中断实现的：HI_SOFTIRQ和TASKLET_SOFTIRQ。
	           2、可以动态增加减少，没有数量限制。
	           3、同一类tasklet不能并发执行。
	           4、不同类型可以并发执行。
	           5、大部分情况使用tasklet。

	工作队列:  1、由内核线程去执行，换句话说总在进程上下文执行。
	           2、可以睡眠，阻塞。
```

