---
layout: post
title: "内核源码分析之linux内核栈"
date: 2015-05-07 15:54:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~irq
tags:
---
http://www.cnblogs.com/liangning/p/3879177.html

基于3.16-rc4


在3.16-rc4内核源码中，内核给每个进程分配的内核栈大小为8KB。这个内核栈被称为异常栈，在进程的内核空间运行时或者执行异常处理程序时，使用的都是异常栈，看下异常栈的代码（include/linux/sched.h）：
```
	union thread_union {
		struct thread_info thread_info;
		unsigned long stack[THREAD_SIZE/sizeof(long)];
	};
```
THREAD_SIZE值为8KB，因此内核为进程的异常栈（内核栈）分配了两个页框大小（页框大小4KB）。另外，进程的thread_info结构体保存在栈顶部。

此外，内核为每个cpu分配一个硬中断栈和一个软中断栈（这两个栈也是内核栈），用来执行中断服务例程和下半部（软中断），看看代码（arch/x86/kernel/irq_32.c）。这两个栈属于cpu，不属于进程，这和异常栈是有区别的。
```
	DEFINE_PER_CPU(struct irq_stack *, hardirq_stack);
	DEFINE_PER_CPU(struct irq_stack *, softirq_stack);
```
定义了两个数组hardirq_stack和softirq_stack，每个数组元素对应一个cpu，指向了该cpu的硬中断栈或者软中断栈。再来看下struct irq_stack结构体（arch/x86/include/asm/processor.h）：
```
	struct irq_stack {
		u32                     stack[THREAD_SIZE/sizeof(u32)];
	} __aligned(THREAD_SIZE);
```
可见，硬中断栈和软中断栈的大小均为8KB。

内核在执行中断处理程序时，在do_IRQ函数中会调用handle_irq函数，在handle_irq函数中要进行堆栈切换，代码如下（arch/x86/kernel/irq_32.c）：
```
	bool handle_irq(unsigned irq, struct pt_regs *regs)
	{
		struct irq_desc *desc;
		int overflow;

		overflow = check_stack_overflow();

		desc = irq_to_desc(irq);
		if (unlikely(!desc))
		return false;

		if (user_mode_vm(regs) || !execute_on_irq_stack(overflow, desc, irq)) {
			if (unlikely(overflow))
				print_stack_overflow();
			desc->handle_irq(irq, desc);
		}

		return true;
	}
```

第12行中执行execute_on_irq_stack函数来判断是否需要堆栈切换，如果不需要，则执行if体的中断服务例程，即在当前堆栈中执行中断服务例程，如果需要切换堆栈，则在execute_on_irq_stack函数中切换堆栈并在该函数中（新堆栈中）执行中断服务例程。下面看下execute_on_irq_stack代码（arch/x86/kernel/irq_32.c）：
```
	static inline int
	execute_on_irq_stack(int overflow, struct irq_desc *desc, int irq)
	{
		struct irq_stack *curstk, *irqstk;
		u32 *isp, *prev_esp, arg1, arg2;

		curstk = (struct irq_stack *) current_stack();
		irqstk = __this_cpu_read(hardirq_stack);

		/*
		 * this is where we switch to the IRQ stack. However, if we are
		 * already using the IRQ stack (because we interrupted a hardirq
		 * handler) we can't do that and just have to keep using the
		 * current stack (which is the irq stack already after all)
		 */
		if (unlikely(curstk == irqstk))
		    return 0;

		isp = (u32 *) ((char *)irqstk + sizeof(*irqstk));

		/* Save the next esp at the bottom of the stack */
		prev_esp = (u32 *)irqstk;
		*prev_esp = current_stack_pointer;

		if (unlikely(overflow))
		    call_on_stack(print_stack_overflow, isp);

		asm volatile("xchgl    %%ebx,%%esp    \n"
		         "call    *%%edi        \n"
		         "movl    %%ebx,%%esp    \n"
		         : "=a" (arg1), "=d" (arg2), "=b" (isp)
		         :  "0" (irq),   "1" (desc),  "2" (isp),
		        "D" (desc->handle_irq)
		         : "memory", "cc", "ecx");
		return 1;
	}
```

第7行获取当前堆栈的指针，第8行获取本地cpu的硬中断栈指针，第16行对二者进行比较，如果相等，则不需要切换堆栈（说明当前堆栈就是硬中断栈，也说明是在中断处理程序中时又发生了中断）。如果不相等，就要进行堆栈切换，第22-23行将当前堆栈指针保存在将要切换到的堆栈中（用于返回）。第28行，交换ebx和esp寄存器的值（实现了堆栈切换，将中断栈指针给了esp），第29行跳转到相应的中断服务例程，第30行从中断服务例程返回后，又将原来的堆栈指针赋给esp，切换到原先堆栈。第33行将中断服务例程函数名存放在%edi中。

