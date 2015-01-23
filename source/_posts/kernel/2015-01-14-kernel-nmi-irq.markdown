---
layout: post
title: "NMI 看门狗"
date: 2015-01-14 23:34:00 +0800
comments: false
categories:
- 2015
- 2015~01
- kernel
- kernel~irq
tags:
---
http://blog.csdn.net/arethe/article/details/6153143

#### [X86和X86-64体系结构均支持NMI看门狗]
  你的系统是不是会经常被锁住（Lock up）？直至解锁，系统不再响应键盘？你希望帮助我们解决类似的问题吗？如果你对所有的问题都回答“yes”，那么此文档正是为你而写。

  在很多X86/X86-64结构的硬件上，我们都可以使用一种被称为“看门狗NMI中断”的机制。（NMI：Non Maskable Interrupt. 这种中断即使在系统被锁住时，也能被响应）。这种机制可以被用来调试内核锁住现象。通过周期性地执行NMI中断，内核能够监测到是否有CPU被锁住。当有处理器被锁住时，打印调试信息。

  为了使用NMI看门狗，首先需要在内核中支持APIC。对于SMP内核，APIC的相关支持已自动地被编译进内核。对于UP内核，需要在内核配置中使能CONFIG_X86_UP_APIC (Processor type and features -> Local APIC support on uniprocessors) 或 CONFIG_X86_UP_IOAPIC (Processor type and features -> IO-APIC support on uniprocessors)。在没有IO-APIC的单处理器系统中，配置CONFIG_X86_UP_APIC。在有IO-APIC的单处理器系统中，则需配置CONFIG_X86_UP_IOAPIC。[注意：某些与内核调试相关选项可能会禁用NMI看门狗。如：Kernel Stack Meter或Kernel Tracer]。

  对于X86-64系统，APIC已被编进内核。

  使用本地APIC（nmi_watchdog=2）时，需要占用第一个性能寄存器，因而此寄存器不能再被另作它用（如高精度的性能分析）。Oprofile与perfctr的驱动已自动地禁用了本地APIC的NMI看门狗。

  可以通过启动参数“nmi_watchdog=N”使能NMI看门狗。即在lilo.conf的相关项中添加如下语句：
```
  append=”nmi_watchdog=1”
```
  对于具有IO-APIC的SMP与UP机器，设置nmi_watchdog=1。对于没有IO-APIC的UP机器，设置nmi_watchdog=2，但仅在某些处理器上可以起作用。如果有疑问，在用nmi_watchdog=1启动后，再查看/proc/interrupts文件中的NMI项，如果该项为0，那么便用nmi_watchdog=2重新启动，并再次检查NMI项。如果还是0，问题就比较严重了，你的处理器很可能不支持NMI。

  “锁住（Lockup）”是指如下的情况：如果系统中的任何一个CPU不能处理周期性的本地时钟中断，并持续5秒钟以上，那么NMI的处理函数将产生一个oops并杀死当前进程。这是一种“可控崩溃”（Controlled Crash，所谓可控，是指发生崩溃时，能够输出内核信息），可以用此机制来调试“锁住”现象。那么，无论什么时候发生“锁住”，5秒钟之后都会自动地输出oops。如果内核没有输出信息，说明此时发生的崩溃过于严重（如：hardware-wise），以至于NMI中断都无法被响应，或者此次崩溃使得内核无法打印信息。

  在使用本地APIC时要注意，NMI中断被触发的频率依赖于系统的当前负载。由于缺乏更好的时钟源，本地APIC中的NMI看门狗使用的是“有效周期（Cycle unhalted，这个词的翻译似乎不太确切，如果某位朋友有更佳的建议，请告知在下。）”事件。也许你已经猜到了，当CPU处于halted（空等）状态时，该时钟是不计数的。处理器处于空闲状态的时候，常出现这样的情况。如果你的系统在被锁住时，执行的不是hlt指令，看门狗中断很快就会被触发，因为每个时钟周期都会发生“有效周期”事件。如果不幸，处理器在被锁住时，执行的恰是“hlt”指令，那么“有效周期”事件永远都不会发生，看门狗自然也不会被触发。这是本地APIC看门狗的缺陷，在倒霉的时候，永远不会进行时钟计数。而I/O APIC中的看门狗由于采用外部时钟进行驱动，便不存在这个缺陷。但是，它的NMI频率非常高，会显著地影响系统的性能。

  X86的nmi_watchdog在默认情况下是禁用的，因此你需要在系统启动的时候使能它。

  在系统运行期间，可以禁用NMI看门狗，只要向文件“/proc/sys/kernel/nmi_watchdog”中写“0”即可。向该文件写“1”，将重新使能看门狗。即使如此，你仍然需要在启动时使用参数“nmi_watchdog=”。

  注意：在2.4.2-ac18之前的内核中，X86 SMP平台会无条件地使能NMI-oopser。

------------------

www.2cto.com/kf/201311/260704.html
```
	//  使能hard lockup探测
	//  调用路径：watchdog_enable->watchdog_nmi_enable
	//  函数任务：
	//      1.初始化hard lockup检测事件
	//          2.hard lockup阈值为10s
	//      2.向performance monitoring子系统注册hard lockup检测事件
	//      3.使能hard lockup检测事件
	//  注：
	//      performance monitoring，x86中的硬件设备，当cpu clock经过了指定个周期后发出一个NMI中断。
	1.1 static int watchdog_nmi_enable(unsigned int cpu)
	{
		//hard lockup事件
		struct perf_event_attr *wd_attr;
		struct perf_event *event = per_cpu(watchdog_ev, cpu);
		....
		wd_attr = &wd_hw_attr;
		//hard lockup检测周期，10s
		wd_attr->sample_period = hw_nmi_get_sample_period(watchdog_thresh);
		//向performance monitoring注册hard lockup检测事件
		event = perf_event_create_kernel_counter(wd_attr, cpu, NULL, watchdog_overflow_callback, NULL);
		....
		//使能hard lockup的检测
		per_cpu(watchdog_ev, cpu) = event;
		perf_event_enable(per_cpu(watchdog_ev, cpu));
		return 0;
	}
	 
	//  换算hard lockup检测周期到cpu频率
	1.2 u64 hw_nmi_get_sample_period(int watchdog_thresh)
	{
		return (u64)(cpu_khz) * 1000 * watchdog_thresh;
	}
	 
	//  hard lockup检测事件发生时的nmi回调函数
	//  函数任务：
	//      1.判断是否发生了hard lockup
	//          1.1 dump hard lockup信息
	1.3 static void watchdog_overflow_callback(struct perf_event *event,
         struct perf_sample_data *data,
         struct pt_regs *regs)
	{
		//判断是否发生hard lockup
		if (is_hardlockup()) {
		    int this_cpu = smp_processor_id();
	 
		    //打印hard lockup信息
		    if (hardlockup_panic)
		        panic("Watchdog detected hard LOCKUP on cpu %d", this_cpu);
		    else
		        WARN(1, "Watchdog detected hard LOCKUP on cpu %d", this_cpu);
	 
		    return;
		}
		return;
	}
	 
	//  判断是否发生hard lockup
	//  注：
	//      如果时钟中断在指定阈值范围内为运行，核心认为可屏蔽中断被屏蔽时间过长
	1.4 static int is_hardlockup(void)
	{
		//获取watchdog timer的运行次数
		unsigned long hrint = __this_cpu_read(hrtimer_interrupts);
		//在一个hard lockup检测时间阈值内，如果watchdog timer未运行，说明cpu中断被屏蔽时间超过阈值
		if (__this_cpu_read(hrtimer_interrupts_saved) == hrint)
		    return 1;
		//记录watchdog timer运行的次数
		__this_cpu_write(hrtimer_interrupts_saved, hrint);
		return 0;
	}
 
	//  关闭hard lockup检测机制
	//  函数任务：
	//      1.向performance monitoring子系统注销hard lockup检测控制块
	//      2.清空per-cpu hard lockup检测控制块
	//      3.释放hard lock检测控制块
	2.1 static void watchdog_nmi_disable(unsigned int cpu)
	{
		struct perf_event *event = per_cpu(watchdog_ev, cpu);
		if (event) {
		    //向performance monitoring子系统注销hard lockup检测控制块
		    perf_event_disable(event);
		    //清空per-cpu hard lockup检测控制块
		    per_cpu(watchdog_ev, cpu) = NULL;
		    //释放hard lock检测控制块
		    perf_event_release_kernel(event);
		}
		return;
	}
```

