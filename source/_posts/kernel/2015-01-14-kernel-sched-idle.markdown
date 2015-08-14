---
layout: post
title: "Idle进程的切换过程"
date: 2015-01-14 23:39:00 +0800
comments: false
categories:
- 2015
- 2015~01
- kernel
- kernel~sched
tags:
---
http://blog.chinaunix.net/uid-27767798-id-3577069.html

  每个cpu都有自己的运行队列，如果当前cpu上运行的任务都已经dequeue出运行队列，而且idle_balance也没有移动到当前运行队列的任务，那么schedule函数中，按照rt ，cfs，idle这三种调度方式顺序，寻找各自的运行任务，那么如果rt和cfs都未找到运行任务，那么最后会调用idle schedule的idle进程，作为schedule函数调度的下一个任务。

kernel/sched.c 中的schedule()函数中的片段
```
	if (prev->state && !(preempt_count() & PREEMPT_ACTIVE)) {   
		//state大于0代表prev也就是当前运行的任务不是running状态，并且没有标记 PREEMPT_ACTIVE，就表示当前的运行的任务没有必要停留在运行队列中了
		if (unlikely(signal_pending_state(prev->state, prev)))  //如果当前进程标记了状态是TASK_INTERRUPTIBLE，并且还有信号未处理，那么没有必要从运行队列中移除这个进程
			prev->state = TASK_RUNNING;
		else
			deactivate_task(rq, prev, DEQUEUE_SLEEP);        //从运行队列中移除这个进程
		switch_count = &prev->nvcsw;
	}

	pre_schedule(rq, prev);

	if (unlikely(!rq->nr_running)) //如果当前运行队列没有进程可以运行了，就balance其他运行队列的任务到当前运行队列，这里balance的具体过程暂时不说
		idle_balance(cpu, rq);

	put_prev_task(rq, prev);
	next = pick_next_task(rq);     //按照rt，cfs，idle优先级的顺序挑选进程，如果在rt和cfs中都没有找到能够运行的任务，那么当前cpu会切换到idle进程。
```
  这里 PREEMPT_ACTIVE是个标志位，由于进程由于系统调用或者中断异常返回到用户态之前，都要判断是否可以被抢占，会首先判断preempt_count,等于0的时候表示没有禁止抢占，然后再去判断是否标记了need_resched,如果标记了，在去调用schedule函数，如果在某些时候禁止了抢占，禁止了一次就要preempt_count加1。可以肯定的一点是进程的state和是否在运行队列的因果关系并不是十分同步的，修改了进程的状态后，可能还需要做一些其他的工作才去调用schedule函数。引用一下其他人的例子。

```
	for (;;) {
	   prepare_to_wait(&wq, &__wait,TASK_UNINTERRUPTIBLE);
	   if (condition)
		 break;
	   schedule();
	}
```

  可以看出在修改了进程的state之后，并不会立刻调用schedule函数，即使立刻调用了schedule函数，也不能保证在schedule函数之前的禁止抢占开启之前有其他的抢占动作。毕竟修改进程的state和从运行队列中移除任务不是一行代码（机器码）就能搞定的事情。所以如果在修改了进程的状态之后和schedule函数禁止抢占之前有抢占动作（可能是中断异常返回），如果这个时候进程被其他进程抢占，这个时候把当前进程移除运行队列，那么这个进程将永远没有机会运行后面的代码。所以这个时候在抢占的过程之前将preempt_count标记PREEMPT_ACTIVE，这样抢占中调用schedule函数将不会从当前运行队列中移除当前进程，这样才有前面分析schedule函数代码，有判断进程state同时判断preempt_count未标记PREEMPT_ACTIVE的情况。

  在当前进程被移除出运行队列之前还需要判断是否有挂起的信号需要处理，如果当前进程的状态是TASK_INTERRUPTIBLE或者TASK_WAKEKILL的时候，如果还有信号未处理，那么当前进程就不需要被移除运行队列，并且将state置为running。

```
	static inline int signal_pending_state(long state, struct task_struct *p)
	{
		if (!(state & (TASK_INTERRUPTIBLE | TASK_WAKEKILL))) //首先判断状态不是这两个可以处理信号的状态就直接返回0，后面的逻辑不考虑了
			return 0;
		if (!signal_pending(p))             //如果没有信号挂起就不继续了
			return 0;

		return (state & TASK_INTERRUPTIBLE) || __fatal_signal_pending(p); //如果有信号
	}
```

	说下 put_prev_task的逻辑，按照道理说应该是rt，cfs，idle的顺序寻找待运行态的任务。

```
	pick_next_task(struct rq *rq)
	{
		const struct sched_class *class;
		struct task_struct *p;

		/*
		 * Optimization: we know that if all tasks are in
		 * the fair class we can call that function directly:
		 */
		//这里注释的意思都能看懂，如果rq中的cfs队列的运行个数和rq中的运行个数相同，直接调用cfs中 的pick函数，因为默认的调度策略是cfs。
		if (likely(rq->nr_running == rq->cfs.nr_running)) {
			p = fair_sched_class.pick_next_task(rq);
			if (likely(p))
			return p;
		}

		//这里 sched_class_highest就是rt_sched_class，所以前面没有选择出任务，那么从rt开始挑选任务，直到idle
		class = sched_class_highest;
 		for ( ; ; ) {
			p = class->pick_next_task(rq);
			if (p)
				return p;
			/*
			 * Will never be NULL as the idle class always
			 * returns a non-NULL p:
			 */
			class = class->next;
		}
	}
```

  从每个调度类的代码的最后可以看出这个next关系

sched_rt.c中：

```
	static const struct sched_class rt_sched_class = {
	.next = &fair_sched_class,
```

sched_fair.c中：

```
	static const struct sched_class fair_sched_class = {
	.next = &idle_sched_class,
```

  那么可以试想如果rt和cfs都没有可以运行的任务，那么最后就是调用idle的pick_next_task函数

sched_idletask.c:
```
	static struct task_struct *pick_next_task_idle(struct rq *rq)
	{
		schedstat_inc(rq, sched_goidle);
		calc_load_account_idle(rq);
		return rq->idle;    //可以看到就是返回rq中idle进程。
	}
```
  这idle进程在启动start_kernel函数的时候调用init_idle函数的时候，把当前进程（0号进程）置为每个rq的idle上。

kernel/sched.c:5415
```
	rq->curr = rq->idle = idle;
```
  这里idle就是调用start_kernel函数的进程，就是0号进程。

  0号进程在fork完init进程等之后，进入cpu_idle函数，大概的逻辑是for循环调用hlt指令，每次hlt返回后，调用schedule函数，具体的流程现在还没太看懂，可以看到的是在具体的逻辑在default_idle函数中，调用了safe_halt函数
```
	static inline void native_safe_halt(void)
	{
		asm volatile("sti; hlt": : :"memory");
	}
```
  关于hlt指令的作用是：引用wiki百科
>   In the x86 computer architecture, HLT (halt) is an assembly language instruction which halts the CPU until the next external interrupt is fired.[1] Interrupts are signals sent by hardware devices to the CPU alerting it that an event occurred to which it should react. For example, hardware timers send interrupts to the CPU at regular intervals.

>   The HLT instruction is executed by the operating system when there is no immediate work to be done, and the system enters its idle state. In Windows NT, for example, this instruction is run in the "System Idle Process".

  可以看到注释的意思是，hlt指令使得cpu挂起，直到有中断产生这个时候cpu重新开始运行。所以时钟中断会唤醒正在hlt中的cpu，让它调用schedule函数，检测是否有新的任务在rq中，如果有的话切换到新的任务，否则继续执行hlt，cpu继续挂起。

参考文章  
1.http://blog.csdn.net/dog250/article/details/5303547

2.http://en.wikipedia.org/wiki/HLT 

