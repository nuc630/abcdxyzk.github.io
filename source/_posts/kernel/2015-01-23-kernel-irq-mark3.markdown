---
layout: post
title: "linux软中断机制分析"
date: 2015-01-23 14:29:00 +0800
comments: false
categories:
- 2015
- 2015~01
- kernel
- kernel~irq
tags:
---

### 软中断分析

#### 1. 为什么要软中断

编写驱动的时候，一个中断产生之后，内核在中断处理函数中可能需要完成很多工作。但是中断处理函数的处理是关闭了中断的。也就是说在响应中断时，系统不能再次响应外部的其它中断。这样的后果会造成有可能丢失外部中断。于是，linux内核设计出了一种架构，中断函数需要处理的任务分为两部分，一部分在中断处理函数中执行，这时系统关闭中断。另外一部分在软件中断中执行，这个时候开启中断，系统可以响应外部中断。

关于软件中断的理论各种书籍都有介绍，不多叙述。而要真正体会软件中断的作用就必须从代码的角度来分析。我们做工作时候讲求的是professional，当一个人在某个领域一无所知的时候，我们称他为小白，偶，非苹果电脑。小白的脑子里充满了各种问题。慢慢的当这些疑惑解释完之后，小白就脱白了。此时，我们对这个领域的基本框架有了解，但这和professional还有一定的差距。再加以时日，逐渐融会贯通该领域才能达到专业的境界。

#### 2. 什么时候触发处理软件中断

说了这么多废话，赶快步入正题。初识软中断，脑子里肯定有不少的疑问，首先就是软件中断在什么地方被触发处理？这个问题的答案就是：一个硬件中断处理完成之后。下面的函数在处理完硬件中断之后推出中断处理函数，在irq_exit中会触发软件中断的处理。
```
	asmlinkage void __exception asm_do_IRQ(unsigned int irq, struct pt_regs *regs)
	{
		struct pt_regs *old_regs = set_irq_regs(regs);
	 
		irq_enter();
	 
		/*
		 * Some hardware gives randomly wrong interrupts.  Rather
		 * than crashing, do something sensible.
		 */ 
		if (irq >= NR_IRQS)
		    handle_bad_irq(irq, &bad_irq_desc);
		else 
		    generic_handle_irq(irq);
	 
		/* AT91 specific workaround */ 
		irq_finish(irq);
	 
		irq_exit();
		set_irq_regs(old_regs);
	}
```
这里要注意，invoke_softirq必须满足两个条件才能被调用到，一个就是不是在硬件中断处理过程中或者在软件中断处理中，第二个就是必须有软件中断处于pending状态。第二个好理解，有软件中断产生才去处理，没有就不处理。第一个就不好理解了。
```
	/*
	* Exit an interrupt context. Process softirqs if needed and possible:
	*/ 
	void irq_exit(void)
	{
		account_system_vtime(current);
		trace_hardirq_exit();
		sub_preempt_count(IRQ_EXIT_OFFSET);
		if (!in_interrupt() && local_softirq_pending())
		    invoke_softirq();
	 
	#ifdef CONFIG_NO_HZ
		/* Make sure that timer wheel updates are propagated */ 
		rcu_irq_exit();
		if (idle_cpu(smp_processor_id()) && !in_interrupt() && !need_resched())
		    tick_nohz_stop_sched_tick(0);
	#endif 
		preempt_enable_no_resched();
	}
```
在linux系统的进程数据结构里，有这么一个数据结构
```
	#define preempt_count() (current_thread_info()->preempt_count)，
```
利用preempt_count可以表示是否处于中断处理或者软件中断处理过程中。
```
	#define PREEMPT_MASK    (__IRQ_MASK(PREEMPT_BITS) << PREEMPT_SHIFT)
	#define SOFTIRQ_MASK    (__IRQ_MASK(SOFTIRQ_BITS) << SOFTIRQ_SHIFT)
	#define HARDIRQ_MASK    (__IRQ_MASK(HARDIRQ_BITS) << HARDIRQ_SHIFT)
	 
	#define PREEMPT_OFFSET    (1UL << PREEMPT_SHIFT)
	#define SOFTIRQ_OFFSET    (1UL << SOFTIRQ_SHIFT)
	#define HARDIRQ_OFFSET    (1UL << HARDIRQ_SHIFT)

	sub_preempt_count(IRQ_EXIT_OFFSET);

	#define in_interrupt() (irq_count())

	#define irq_count() (preempt_count() & (HARDIRQ_MASK | SOFTIRQ_MASK))
```

![](/images/kernel/2015-01-23-1.png)

preempt_count的8～23位记录中断处理和软件中断处理过程的计数。如果有计数，表示系统在硬件中断或者软件中断处理过程中。系统这么设计是为了避免软件中断在中断嵌套中被调用，并且达到在单个CPU上软件中断不能被重入的目的。对于ARM架构的CPU不存在中断嵌套中调用软件中断的问题，因为ARM架构的CPU在处理硬件中断的过程中是关闭掉中断的。只有在进入了软中断处理过程中之后才会开启硬件中断，如果在软件中断处理过程中有硬件中断嵌套，也不会再次调用软中断，because硬件中断是软件中断处理过程中再次进入的，此时preempt_count已经记录了软件中断！对于其它架构的CPU，有可能在触发调用软件中断前，也就是还在处理硬件中断的时候，就已经开启了硬件中断，可能会发生中断嵌套，在中断嵌套中是不允许调用软件中断处理的。Why？我的理解是，在发生中断嵌套的时候，表明这个时候是系统突发繁忙的时候，内核第一要务就是赶紧把中断中的事情处理完成，退出中断嵌套。避免多次嵌套，哪里有时间处理软件中断，所以把软件中断推迟到了所有中断处理完成的时候才能触发软件中断。

#### 3. 软件中断的处理过程

之前我已经说到，软中断的一个很大的目的就是避免中断处理中，处理的操作过多而丢失中断。同时中断还需要考虑到一件事情就是中断处理过程过长就会影响系统响应时间。如果一个中断处理一秒钟，那你一定能感受到串口卡住的现象。从另外一方面说呢，我们又必须考虑中断处理的操作一定的优先度，毕竟是硬件触发的事务，关系到网络、块设备的效率问题。Linux内核就中断方面就必须考虑平衡这三个方面的问题。而下面我要分析的__do_softirq函数就恰似在这三者之间打太极，游刃有余，面面俱到！

```
	/*
	* We restart softirq processing MAX_SOFTIRQ_RESTART times,
	* and we fall back to softirqd after that.
	*
	* This number has been established via experimentation.
	* The two things to balance is latency against fairness -
	* we want to handle softirqs as soon as possible, but they
	* should not be able to lock up the box.
	*/ 
	#define MAX_SOFTIRQ_RESTART 10 
	 
	asmlinkage void __do_softirq(void)
	{
		struct softirq_action *h;
		__u32 pending;
		int max_restart = MAX_SOFTIRQ_RESTART;
		int cpu;
	 
		pending = local_softirq_pending();
		account_system_vtime(current);
	 
		__local_bh_disable((unsigned long)__builtin_return_address(0));
		trace_softirq_enter();
	 
		cpu = smp_processor_id();
	restart:
		/* Reset the pending bitmask before enabling irqs */ 
		set_softirq_pending(0);
	 
		local_irq_enable();
	 
		h = softirq_vec;
	 
		do 
		{
		    if (pending & 1)
		    {
		        int prev_count = preempt_count();
	 
		        h->action(h);
	 
		        if (unlikely(prev_count != preempt_count()))
		        {
		            printk(KERN_ERR "huh, entered softirq %td %p" 
		                   "with preempt_count %08x," 
		                   " exited with %08x?\n", h - softirq_vec,
		                   h->action, prev_count, preempt_count());
		            preempt_count() = prev_count;
		        }
	 
		        rcu_bh_qsctr_inc(cpu);
		    }
		    h++;
		    pending >>= 1;
		}
		while (pending);
	 
		local_irq_disable();
	 
		pending = local_softirq_pending();
		if (pending && --max_restart)
		    goto restart;
	 
		if (pending)
		    wakeup_softirqd();
	 
		trace_softirq_exit();
	 
		account_system_vtime(current);
		_local_bh_enable();
	}
```

__do_softirq函数处理软件中断过程如下图流程分析

4. 首先调用local_softirq_pending函数取得目前有哪些位存在软件中断

5. 调用__local_bh_disable关闭软中断，其实就是设置正在处理软件中断标记，在同一个CPU上使得不能重入__do_softirq函数

6. 重新设置软中断标记为0，set_softirq_pending重新设置软中断标记为0，这样在之后重新开启中断之后硬件中断中又可以设置软件中断位。

7. 开启硬件中断

8. 之后在一个循环中，遍历pending标志的每一位，如果这一位设置就会调用软件中断的处理函数。在这个过程中硬件中断是开启的，随时可以打断软件中断。这样保证硬件中断不会丢失。

9. 之后关闭硬件中断，查看是否又有软件中断处于pending状态，如果是，并且在本次调用__do_softirq函数过程中没有累计重复进入软件中断处理的次数超过10次，就可以重新调用软件中断处理。如果超过了10次，就调用wakeup_softirqd();唤醒内核的一个进程来处理软件中断。设立10次的限制，也是为了避免影响系统响应时间。

![](/images/kernel/2015-01-23-2.png)

#### 4. 处理软中断内核线程

之前我说到不能让CPU长时间来处理中断事务，这样会影响系统的响应时间，严重影响用户和系统之间的交互式体验。所以在之前的__do_softirq中最多将循环执行10次，那么当执行了10次仍然有软中断在pending状态，这个时候应该怎么处理呢？系统将唤醒一个软件中断处理的内核进程，在内核进程中处理pending中的软件中断。这里要注意，之前我们分析的触发软件中断的位置其实是中断上下文中，而在软中断的内核线程中实际已经是进程的上下文。

这里说的软中断上下文指的就是系统为每个CPU建立的ksoftirqd进程。

看完这个函数，我不得不佩服这个函数设计的精巧！而我更多的从中体会到其中蕴藏的一种做人的道理。那就是做人要霸道一点，太谦和太恭维不行，但是又不能横行霸道，原则的问题要公平讲理，一定的时候顾及别人的利益，好处不能一个人独吞。这就跟下面ksoftirqd处理过程一样，该狠的时候禁止抢占，其它进程别想调度到哦，但是自己占用CPU时间过长的话，也自觉的问一问是不是该释放CPU给其它进程了。

下面我们就来分析一下这个处理过程怎么就体现了上面的这种说法呢？软中断的内核进程中主要有两个大循环，外层的循环处理有软件中断就处理，没有软件中断就休眠。内层的循环处理软件中断，并每循环一次都试探一次是否过长时间占据了CPU，需要调度释放CPU给其它进程。具体的操作在注释中做了解释。
```
	static int ksoftirqd(void *__bind_cpu)
	{
		set_current_state(TASK_INTERRUPTIBLE);
	 
		while (!kthread_should_stop())
		{
		    /*不管三七二十一首先禁止抢占，我掌握CPU，并全凭我自己掌握调度*/ 
		    preempt_disable();
		    if (!local_softirq_pending())
		    {
		        preempt_enable_no_resched();
		        /*如果没有软中断在pending，那就让出CPU来吧*/ 
		        schedule();
		       /*我被唤醒了，首先掌握CPU，不让自己被抢占，自己决定自己的是否要调度*/ 
		        preempt_disable();
		    }
	 
		    __set_current_state(TASK_RUNNING);
	 
		    while (local_softirq_pending())
		    {
		        /* Preempt disable stops cpu going offline.
		           If already offline, we'll be on wrong CPU:
		           don't process */ 
		        if (cpu_is_offline((long)__bind_cpu))
		            goto wait_to_die;
		        /*处理软中断*/ 
		        do_softirq();
		        /*虽然我自己掌握是否要调度，虽然我可以一直不调度，但是我是
		        个正直的人，运行一段时间后我会看看是否需要调度，还其它进程运行*/ 
		        preempt_enable_no_resched();
		        cond_resched();
		        preempt_disable();
		        rcu_qsctr_inc((long)__bind_cpu);
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
		while (!kthread_should_stop())
		{
		    schedule();
		    set_current_state(TASK_INTERRUPTIBLE);
		}
		__set_current_state(TASK_RUNNING);
		return 0;
	}
```

