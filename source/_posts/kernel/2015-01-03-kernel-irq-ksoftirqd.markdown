---
layout: post
title: "关于ksoftirqd进程"
date: 2015-01-03 15:01:00 +0800
comments: false
categories:
- 2015
- 2015~01
- kernel
- kernel~irq
tags:
---
blog.chinaunix.net/uid-20737871-id-1881243.html

每个处理器都有一组辅助处理器软中断(和tasklet)的内核线程。当内核中出现大量软中断的时候，这些内核进程就会辅助处理它们。

#### 引入ksoftirq内核线程的原因：
对于软中断，内核会选择在几个特殊时机进行处理。而在中断处理程序返回时处理是最常见的。软中断被触发的频率有时可能很高，更不利的是，处理函数有时还会 字形重复触发，那么就会导致用户空间进程无法获得足够的处理时间，因而处于饥饿状态。单纯的对重新触发的软中断采取不立即处理的策略，也无法让人接受。

#### 最初的解决方案：
1）只要还有被触发并等待处理的软中断，本次执行就要负责处理，重新触发的软中断也在本次执行返回前被处理。这样做可以保证对内核的软中断采取即时处理的 方式，关键在于，对重新触发的软中断也会立即处理。当负载很高的时候，此时若有大量被触发的软中断，而它们本身又会重复触发。系统可能会一直处理软中断根 本不能完成其他任务。

2）不处理重新触发的软中断。在从中断返回的时候，内核和平常一样，也会检查所有挂起的软中断并处理他们。但是，任何自行重新触发的软中断不会马上处理， 它们被放到下一个软中断执行时机去处理。而这个时机通常也就是下一次中断返回的时候。可是，在比较空闲的系统中，立即处理软中断才是比较好的做法。尽管它 能保证用户空间不处于饥饿状态，但它却让软中断忍受饥饿的痛苦，而根本没有好好利用闲置的系统资源。

#### 改进：
最终在内核中实现的方案是不会立即处理处理重新触发的软中断。而作为改进，当大量软中断出现的时候，内核会唤醒一组内核线程来处理这些负载。这些线程在最 低的优先级上运行（nice值是19），这能避免它们跟其他重要的任务抢夺资源。但它们最终肯定会被执行，所以这个折中方案能够保证在软中断负担很中的时 候用户程序不会因为得不到处理时间处于饥饿状态。相应的，也能保证”过量“的软中断终究会得到处理。

每个处理器都有一个这样的线程。所有线程的名字都叫做ksoftirq/n，区别在于n，它对应的是处理器的编号。在一个双CPU的机器上就有两个这样的 线程，分别叫做ksoftirqd/0和ksoftirqd/1。为了保证只要有空闲的处理器，它们就会处理软中断，所以给每个处理器都分配一个这样的线 程。一旦该线程被初始化，它就会执行类似下面这样的死循环：

在kernel/softirq.c中
```
	static int ksoftirqd(void * __bind_cpu)
	{
		set_user_nice(current, 19);
		current->flags |= PF_NOFREEZE;
		set_current_state(TASK_INTERRUPTIBLE);
		while (!kthread_should_stop()) {
			preempt_disable();
			if (!local_softirq_pending()) {
				preempt_enable_no_resched();
				schedule();
				preempt_disable();
			}
			__set_current_state(TASK_RUNNING);
			while (local_softirq_pending()) {
				/* Preempt disable stops cpu going offline.
					If already offline, we'll be on wrong CPU:
					don't process */
				if (cpu_is_offline((long)__bind_cpu))
					goto wait_to_die;
				do_softirq();
				preempt_enable_no_resched();
				cond_resched();
				preempt_disable();
			}
			preempt_enable();
			set_current_state(TASK_INTERRUPTIBLE);
		}
		__set_current_state(TASK_RUNNING);
		return 0;
	wait_to_die:
		preempt_enable();
		/* Wait for kthread_stop */
		set_current_state(TASK_INTERRUPTIBLE);
		while (!kthread_should_stop()) {
			schedule();
			set_current_state(TASK_INTERRUPTIBLE);
		}
		__set_current_state(TASK_RUNNING);
		return 0;
	}
```

只要有待处理的软中断(由softirq_pending()函数负责发现)，ksoftirq就会调用do_softirq去处理它们。通过重复执行这 样的操作，重新触发的软中断也会被执行。如果有必要，每次迭代后都会调用schedule()以便让更重要的进程得到处理机会。当所有需要执行的操作都完 成以后，该内核线程将自己设置为TASK_INTERRUPTIBLE状态，唤起调度程序选择其他可执行进程投入运行。

只要do_softirq()函数发现已经执行过的内核线程重新触发了它自己，软中断内核线程就会被唤醒. 

