---
layout: post
title: "内核抢占与中断返回"
date: 2014-04-22 11:00:00 +0800
comments: false
categories:
- 2014
- 2014~04
- kernel
- kernel~sched
tags:
---
#### 1、上下文
一般来说，CPU在任何时刻都处于以下三种情况之一：  
(1)运行于用户空间，执行用户进程；  
(2)运行于内核空间，处于进程上下文；  
(3)运行于内核空间，处于中断上下文。  
应用程序通过系统调用陷入内核，此时处于进程上下文。现代几乎所有的CPU体系结构都支持中断。当外部设备产生中断，向CPU发送一个异步信号，CPU调用相应的中断处理程序来处理该中断，此时CPU处于中断上下文。

在进程上下文中，可以通过current关联相应的任务。进程以进程上下文的形式运行在内核空间，可以发生睡眠，所以在进程上下文中，可以使作信号量(semaphore)。实际上，内核经常在进程上下文中使用信号量来完成任务之间的同步，当然也可以使用锁。

中断上下文不属于任何进程，它与current没有任何关系(尽管此时current指向被中断的进程)。由于没有进程背景，在中断上下文中不能发生睡眠，否则又如何对它进行调度。所以在中断上下文中只能使用锁进行同步，正是因为这个原因，中断上下文也叫做原子上下文(atomic context)(关于同步以后再详细讨论)。在中断处理程序中，通常会禁止同一中断，甚至会禁止整个本地中断，所以中断处理程序应该尽可能迅速，所以又把中断处理分成上部和下部(关于中断以后再详细讨论)。

#### 2、上下文切换
上下文切换，也就是从一个可执行进程切换到另一个可执行进程。上下文切换由函数context_switch()函数完成，该函数位于kernel/sched.c中，它由进程调度函数schedule()调用。
```
	static inline
	task_t * context_switch(runqueue_t *rq, task_t *prev, task_t *next)
	{
		struct mm_struct *mm = next->mm;
		struct mm_struct *oldmm = prev->active_mm;

		if (unlikely(!mm)) {
			next->active_mm = oldmm;
			atomic_inc(&oldmm->mm_count);
			enter_lazy_tlb(oldmm, next);
		} else
			switch_mm(oldmm, mm, next);

		if (unlikely(!prev->mm)) {
			prev->active_mm = NULL;
			WARN_ON(rq->prev_mm);
			rq->prev_mm = oldmm;
		}

		/* Here we just switch the register state and the stack. */
		switch_to(prev, next, prev);

		return prev;
	}
```

其中，switch_mm()将虚拟内存映射到新的进程；switch_to完成最终的进程切换，它保存原进程的所有寄存器信息，恢复新进程的所有寄存器信息，并执行新的进程。无论何时，内核想要进行任务切换，都通过调用schedule()完成任务切换。

##### 2.2、用户抢占
当内核即将返回用户空间时，内核会检查need_resched是否设置，如果设置，则调用schedule()，此时，发生用户抢占。一般来说，用户抢占发生几下情况：  
(1)从系统调用返回用户空间；  
(2)从中断(异常)处理程序返回用户空间。  

##### 2.3、内核抢占
内核从2.6开始就支持内核抢占，对于非内核抢占系统，内核代码可以一直执行，直到完成，也就是说当进程处于内核态时，是不能被抢占的（当然，运行于内核态的进程可以主动放弃CPU，比如，在系统调用服务例程中，由于内核代码由于等待资源而放弃CPU，这种情况叫做计划性进程切换（planned process switch））。但是，对于由异步事件(比如中断)引起的进程切换，抢占式内核与非抢占式是有区别的，对于前者叫做强制性进程切换(forced process switch)。

为了支持内核抢占，内核引入了preempt_count字段，该计数初始值为0，每当使用锁时加1，释放锁时减1。当preempt_count为0时，表示内核可以被安全的抢占，大于0时，则禁止内核抢占。该字段对应三个不同的计数器(见软中断一节)，也就是说在以下三种任何一种情况，该字段的值都会大于0。

(1) 内核执行中断处理程序时，通过irq_enter增加中断计数器的值；  
	`#define irq_enter()        (preempt_count() += HARDIRQ_OFFSET)`  
(2) 可延迟函数被禁止(执行软中断和tasklet时经常如此，由local_bh_disable完成；  
(3) 通过把抢占计数器设置为正而显式禁止内核抢占，由preempt_disable完成。  

  当从中断返回内核空间时，内核会检preempt_count和need_resched的值(返回用户空间时只需要检查need_resched)，如查preempt_count为0且need_resched设置，则调用schedule()，完成任务抢占。一般来说，内核抢占发生以下情况：  
(1) 从中断(异常)返回时，preempt_count为0且need_resched置位(见从中断返回)；  
(2) 在异常处理程序中(特别是系统调用)调用preempt_enable()来允许内核抢占发生；  
```
	//incude/linux/preempt.h
	#define preempt_enable() \
	do { \
		//抢占计数器值减1
		preempt_enable_no_resched(); \
		//检查是否需要进行内核抢占调度,见(3)
		preempt_check_resched(); \
	} while (0)
```
(3) 启用可延迟函数时，即调用local_bh_enable()时发生；
```
	//kernel/softirq.c
	void local_bh_enable(void)
	{
		WARN_ON(irqs_disabled());
		/*
		 * Keep preemption disabled until we are done with
		 * softirq processing:
		 */
		//软中断计数器值减1
		preempt_count() -= SOFTIRQ_OFFSET - 1;

		if (unlikely(!in_interrupt() && local_softirq_pending()))
			do_softirq(); //软中断处理
		//抢占计数据器值减1
		dec_preempt_count();
		
		//检查是否需要进行内核抢占调度
		preempt_check_resched();
	}

	//include/linux/preempt.h
	#define preempt_check_resched() \
	do { \
		//检查need_resched
		if (unlikely(test_thread_flag(TIF_NEED_RESCHED))) \
			//抢占调度
			preempt_schedule(); \
	} while (0)

	//kernel/sched.c
	asmlinkage void __sched preempt_schedule(void)
	{
		struct thread_info *ti = current_thread_info();

		/*
		 * If there is a non-zero preempt_count or interrupts are disabled,
		 * we do not want to preempt the current task.  Just return..
		 */
		 //检查是否允许抢占,本地中断关闭,或者抢占计数器值不为0时不允许抢占
		if (unlikely(ti->preempt_count || irqs_disabled()))
			return;

	need_resched:
		ti->preempt_count = PREEMPT_ACTIVE;
		//发生调度
		schedule();
		ti->preempt_count = 0;

		/* we could miss a preemption opportunity between schedule and now */
		barrier();
		if (unlikely(test_thread_flag(TIF_NEED_RESCHED)))
			goto need_resched;
	}
```
(4) 内核任务显示调用schedule()，例如内核任务阻塞时，就会显示调用schedule()，该情况属于内核自动放弃CPU。

#### 5、从中断返回
当内核从中断返回时，应当考虑以下几种情况：  
(1) 内核控制路径并发执行的数量：如果为1，则CPU返回用户态。  
(2) 挂起进程的切换请求：如果有挂起请求，则进行进程调度；否则，返回被中断的进程。  
(3) 待处理信号：如果有信号发送给当前进程，则必须进行信号处理。  
(4) 单步调试模式：如果调试器正在跟踪当前进程，在返回用户态时必须恢复单步模式。  
(5) Virtual-8086模式：如果中断时CPU处于虚拟8086模式，则进行特殊的处理。  

##### 4.1从中断返回
中断返回点为ret_from-intr：
// 从中断返回
```
	ret_from_intr:
		GET_THREAD_INFO(%ebp)
		movl EFLAGS(%esp), %eax        # mix EFLAGS and CS
		movb CS(%esp), %al
		testl $(VM_MASK | 3), %eax #是否运行在VM86模式或者用户态
		/*中断或异常发生时,处于内核空间,则返回内核空间;否则返回用户空间*/
		jz resume_kernel        # returning to kernel or vm86-space
```

从中断返回时，有两种情况，一是返回内核态，二是返回用户态。
###### 5.1.1、返回内核态
```
	#ifdef CONFIG_PREEMPT 
	/*返回内核空间,先检查preempt_count,再检查need_resched*/
	ENTRY(resume_kernel)
		/*是否可以抢占,即preempt_count是否为0*/
		cmpl $0,TI_preempt_count(%ebp)    # non-zero preempt_count ?
		jnz restore_all #不能抢占,则恢复被中断时处理器状态
		
	need_resched:
		movl TI_flags(%ebp), %ecx    # need_resched set ?
		testb $_TIF_NEED_RESCHED, %cl #是否需要重新调度
		jz restore_all #不需要重新调度
		testl $IF_MASK,EFLAGS(%esp)     # 发生异常则不调度
		jz restore_all
		#将最大值赋值给preempt_count，表示不允许再次被抢占
		movl $PREEMPT_ACTIVE,TI_preempt_count(%ebp)
		sti
		call schedule #调度函数
		cli
		movl $0,TI_preempt_count(%ebp) #preempt_count还原为0
		#跳转到need_resched，判断是否又需要发生被调度
		jmp need_resched
	#endif
```

###### 5.1.2、返回用户态
```
	/*返回用户空间,只需要检查need_resched*/
	ENTRY(resume_userspace)  #返回用户空间,中断或异常发生时,任务处于用户空间
		 cli                # make sure we don't miss an interrupt
			            # setting need_resched or sigpending
			            # between sampling and the iret
		movl TI_flags(%ebp), %ecx
		andl $_TIF_WORK_MASK, %ecx    # is there any work to be done on
			            # int/exception return?
		jne work_pending #还有其它工作要做
		jmp restore_all #所有工作都做完,则恢复处理器状态

	#恢复处理器状态
	restore_all:
		RESTORE_ALL

		# perform work that needs to be done immediately before resumption
		ALIGN
		
		#完成其它工作
	work_pending:
		testb $_TIF_NEED_RESCHED, %cl #检查是否需要重新调度
		jz work_notifysig #不需要重新调度
	 #需要重新调度
	work_resched:
		call schedule #调度进程
		cli                # make sure we don't miss an interrupt
			            # setting need_resched or sigpending
			            # between sampling and the iret
		movl TI_flags(%ebp), %ecx
		/*检查是否还有其它的事要做*/
		andl $_TIF_WORK_MASK, %ecx    # is there any work to be done other
			            # than syscall tracing?
		jz restore_all #没有其它的事,则恢复处理器状态
		testb $_TIF_NEED_RESCHED, %cl
		jnz work_resched #如果need_resched再次置位,则继续调度
	#VM和信号检测
	work_notifysig:                # deal with pending signals and
			            # notify-resume requests
		testl $VM_MASK, EFLAGS(%esp) #检查是否是VM模式
		movl %esp, %eax
		jne work_notifysig_v86        # returning to kernel-space or
			            # vm86-space
		xorl %edx, %edx
		#进行信号处理
		call do_notify_resume
		jmp restore_all

		ALIGN
	work_notifysig_v86:
		pushl %ecx            # save ti_flags for do_notify_resume
		call save_v86_state        # %eax contains pt_regs pointer
		popl %ecx
		movl %eax, %esp
		xorl %edx, %edx
		call do_notify_resume #信号处理
		jmp restore_all
```

##### 5.2、从异常返回
异常返回点为ret_from_exception：
  #从异常返回  
  ALIGN  
ret_from_exception:  
  preempt_stop /*相当于cli,从中断返回时,在handle_IRQ_event已经关中断,不需要这步*/

#### 6、从系统调用返回
```
		#系统调用入口
	ENTRY(system_call)
		pushl %eax            # save orig_eax
		SAVE_ALL
		GET_THREAD_INFO(%ebp)
			            # system call tracing in operation
		testb $(_TIF_SYSCALL_TRACE|_TIF_SYSCALL_AUDIT),TI_flags(%ebp)
		jnz syscall_trace_entry
		cmpl $(nr_syscalls), %eax
		jae syscall_badsys
	syscall_call:
		#调用相应的函数
		call *sys_call_table(,%eax,4)
		movl %eax,EAX(%esp)        # store the return value,返回值保存到eax
	#系统调用返回
	syscall_exit:
		cli                # make sure we don't miss an interrupt
			            # setting need_resched or sigpending
			            # between sampling and the iret
		movl TI_flags(%ebp), %ecx
		testw $_TIF_ALLWORK_MASK, %cx    # current->work,检查是否还有其它工作要完成
		jne syscall_exit_work
	#恢复处理器状态
	restore_all:
		RESTORE_ALL

	#做其它工作
	syscall_exit_work:
		 #检查是否系统调用跟踪,审计,单步执行,不需要则跳到work_pending(进行调度,信号处理)
		testb $(_TIF_SYSCALL_TRACE|_TIF_SYSCALL_AUDIT|_TIF_SINGLESTEP), %cl
		jz work_pending
		sti                # could let do_syscall_trace() call
			            # schedule() instead
		movl %esp, %eax
		movl $1, %edx
		#系统调用跟踪
		call do_syscall_trace
		#返回用户空间
		jmp resume_userspace
```

整个中断、异常和系统调用返回流程如下：

![](/images/kernel/2014-04-22.jpg)

