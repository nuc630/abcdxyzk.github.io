---
layout: post
title: "try_to_wake_up函数"
date: 2015-02-11 11:32:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~sched
tags:
---
  try_to_wake_up函数通过把进程状态设置为TASK_RUNNING，并把该进程插入本地CPU运行队列rq来达到唤醒睡眠和停止的进程的目的。  
例如：调用该函数唤醒等待队列中的进程，或恢复执行等待信号的进程。该函数接受的参数有：  
- 被唤醒进程的描述符指针（p）  
- 可以被唤醒的进程状态掩码（state）  
- 一个标志（sync），用来禁止被唤醒的进程抢占本地CPU上正在运行的进程  
```
	static int try_to_wake_up(struct task_struct *p, unsigned int state, int sync)
	{
		int cpu, this_cpu, success = 0;
		unsigned long flags;
		long old_state;
		struct rq *rq;
	#ifdef CONFIG_SMP
		struct sched_domain *sd, *this_sd = NULL;
		unsigned long load, this_load;
		int new_cpu;
	#endif
		rq = task_rq_lock(p, &flags);
		old_state = p->state;
		if (!(old_state & state))
		    goto out;
		if (p->array)
		    goto out_running;
		cpu = task_cpu(p);
		this_cpu = smp_processor_id();
	#ifdef CONFIG_SMP
	... // [多处理器负载平衡工作](/blog/2015/02/11/kernel-sched-balance/)
	#endif /* CONFIG_SMP */
		if (old_state == TASK_UNINTERRUPTIBLE) {
		    rq->nr_uninterruptible--;
		    /*
		     * Tasks on involuntary sleep don't earn
		     * sleep_avg beyond just interactive state.
		     */
		    p->sleep_type = SLEEP_NONINTERACTIVE; //简单判断出非交互进程
		} else
		    if (old_state & TASK_NONINTERACTIVE)
		        p->sleep_type = SLEEP_NONINTERACTIVE;//同上
		activate_task(p, rq, cpu == this_cpu);
		if (!sync || cpu != this_cpu) {
		    if (TASK_PREEMPTS_CURR(p, rq))
		        resched_task(rq->curr);
		}
		success = 1;
	out_running:
		trace_sched_wakeup(rq, p, success);
		p->state = TASK_RUNNING;
	out:
		task_rq_unlock(rq, &flags);
		return success;
	}
```
代码解释如下：  
1.首先调用task_rq_lock( )禁止本地中断，并获得最后执行进程的CPU（他可能不同于本地CPU）所拥有的运行队列rq的锁。CPU的逻辑号存储在p->thread_info->cpu字段。

2.检查进程的状态p->state是否属于被当作参数传递给函数的状态掩码state，如果不是，就跳到第9步终止函数。

3.如果p->array字段不等于NULL，那么进程已经属于某个运行队列，因此跳转到第8步。

4.在多处理器系统中，该函数检查要被唤醒的进程是否应该从最近运行的CPU的运行队列迁移到另外一个CPU的运行队列。实际上，函数就是根据一些启发式规则选择一个目标运行队列。

5.如果进程处于TASK_UNINTERRUPTIBLE状态，函数递减目标运行队列的nr_uninterruptible字段，并把进程描述符的p->activated字段设置为-1。

6.调用activate_task( )函数：
```
	static void activate_task(struct task_struct *p, struct rq *rq, int local)
	{
		unsigned long long now;
		now = sched_clock();
	#ifdef CONFIG_SMP
	...
	#endif
		if (!rt_task(p))
		    p->prio = recalc_task_prio(p, now); //计算平均睡眠时间并返回之后的优先级。
		if (p->sleep_type == SLEEP_NORMAL) {
		    if (in_interrupt())
		        p->sleep_type = SLEEP_INTERRUPTED;
		    else {
		        p->sleep_type = SLEEP_INTERACTIVE;
		    }
		}
		p->timestamp = now;
		__activate_task(p, rq);
	}
	static void __activate_task(struct task_struct *p, struct rq *rq)
	{
		struct prio_array *target = rq->active;
		trace_activate_task(p, rq);
		if (batch_task(p))
		    target = rq->expired;
		enqueue_task(p, target);
		inc_nr_running(p, rq);
	}
```
它依次执行下面的子步骤：  
  a) 调用sched_clock( )获取以纳秒为单位的当前时间戳。如果目标CPU不是本地CPU，就要补偿本地时钟中断的偏差，这是通过使用本地CPU和目标CPU上最近一次发生时钟中断的相对时间戳来达到的：now = (sched_clock( ) - this_rq( )->timestamp_last_tick)  +  rq->timestamp_last_tick;  
  b) 调用recalc_task_prio()，把进程描述的指针和上一步计算出的时间戳传递给它。recalc_task_prio()主要更新进程的平均睡眠时间和动态优先级，下一篇博文将详细说明这个函数。  
  c) 根据下表设置p->activated字段的值，该字段的意义为：  
		值				说明  
		0	进程处于TASK_RUNNING 状态。  
		1	进程处于TASK_INTERRUPTIBLE 或TASK_STOPPED 状态，而且正在被系统调用服务例程或内核线程唤醒。  
		2	进程处于TASK_INTERRUPTIBLE 或TASK_STOPPED 状态，而且正在被中断处理程序或可延迟函数唤醒。  
		-1	进程处于TASK_UNINTERRUPTIBLE 状态而且正在被唤醒。
  d) 使用在第6a步中计算的时间戳设置p->timestamp字段。  
  e) 把进程描述符插入活动进程集合：
```
    enqueue_task(p, rq->active);
    rq->nr_running++;
```

7.如果目标CPU不是本地CPU，或者没有设置sync标志，就检查可运行的新进程的动态优先级是否比rq运行对了中当前进程的动态优先级高（p->prio < rq->curr->prio）；如果是，就调用resched_task()抢占rq->curr。在单处理器系统中，后面的函数只是执行set_tsk_need_resched()来设置rq->curr进程的TIF_NEED_RESCHED标志。在多处理器系统中，resched_task()也检查TIF_NEED_RESCHED的旧值是否为0、目标CPU与本地CPU是否不同、rq->curr进程的TIF_POLLING_NRFLAG标志是否清0（目标CPU没有轮询进程TIF_NEED_RESCHED标志的值）。如果是，resched_task()调用smp_send_reschedule()产生IPI，并强制目标CPU重新调度。

8.把进程的p->state字段设置为TASK_RUNNING状态。

9.调用task_rq_unlock()来打开rq运行队列的锁并打开本地中断。

10.返回1（若成功唤醒进程）或0（如果进程没有被唤醒）

