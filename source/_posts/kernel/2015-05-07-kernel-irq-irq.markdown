---
layout: post
title: "对Linux x86-64架构上硬中断的重新认识"
date: 2015-05-07 15:48:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~irq
tags:
---
http://www.lenky.info/archives/2013/03/2245

对于x86硬中断的概念，一直都落在理论的认识之上，直到这两天才（因某个问题）发现Linux的实现却并非如此，这里纠正一下（注意：Linux内核源码更新太快，一个说法的时效性太短，所以需注意我提到的香草内核版本，并且以x86-64架构为基准）。

以前的认识：Linux对硬中断（本文如无特殊说明，都是指普通意义上的可屏蔽硬件中断）的处理有优先级概念，高优先级硬中断可以打断低优先级硬中断。

#### 重新认识：
1，对于x86硬件而言，在文档325462.pdf卷3章节6.9 PRIORITY AMONG SIMULTANEOUS EXCEPTIONS AND INTERRUPTS 提到一个表格，是指如果在同一时刻有多个异常或中断到达，那么CPU会按照一个指定的优先级顺序对它们进行响应和服务，而并不是我之前所想的判断是否可相互打断执行的高低级别。

2，对于Linux系统而言，硬中断之间并没有优先级的概念（虽然Intel CPU提供支持，请参考文档325462.pdf卷3章节10.8.3 Interrupt, Task, and Processor Priority），或者说优先级只有两个，全部关闭或全部开启，如下：

>> Regardless of what the hardware might support, typical UNIX-type systems only make use of two levels: the minimum (all interrupts enabled) and the maximum (all interrupts disabled).

这意味着，如果一个硬中断处理函数正在执行，只要当前是处于开启中断的情况，那么此时发生的任何另外一个中断都可以打断当前处理函数，从而出现中断嵌套的情况。
值得注意的是，Linux提供对单个中断开启/禁止的接口（以软件实现为主，比如给对应中断描述符desc的status打上IRQ_DISABLED旗标）：
```
	void disable_irq(unsigned int irq)
	void enable_irq(unsigned int irq)
```
下面来看看Linux的实际处理，其硬中断的一般处理流程（具体可见参考1、2、3以及源代码，以2.6.30.8为例）：
```
硬件中断 -> common_interrupt -> do_IRQ -> handle_irq -> generic_handle_irq_desc -> desc->handle_irq或__do_IRQ。
```

其中desc->handle_irq是一个回调函数，会根据不同中断类型（I/O APIC、MSI）有不同的指向，比如：handle_fasteoi_irq()、handle_edge_irq()，这可以参考设置函数ioapic_register_intr()和setup_msi_irq()。通过/proc/interrupts可以看到各个中断的具体类型：
```
	[root@localhost ~]# cat /proc/interrupts
		       CPU0       CPU1      
	  0:        888          0   IO-APIC-edge      timer
	  1:         96        112   IO-APIC-edge      i8042
	  3:          1          0   IO-APIC-edge   
	  4:          1          0   IO-APIC-edge   
	  7:          0          0   IO-APIC-edge      parport0
	  8:          1          0   IO-APIC-edge      rtc0
	  9:          0          0   IO-APIC-fasteoi   acpi
	 12:        204          0   IO-APIC-edge      i8042
	 14:          0          0   IO-APIC-edge      ata_piix
	 15:     460641        900   IO-APIC-edge      ata_piix
	 16:          0          0   IO-APIC-fasteoi   Ensoniq AudioPCI
	 17:     118347          0   IO-APIC-fasteoi   ehci_hcd:usb1, ioc0
	 18:         70          0   IO-APIC-fasteoi   uhci_hcd:usb2
	 19:     115143          0   IO-APIC-fasteoi   eth0
	 24:          0          0   PCI-MSI-edge      pciehp
	 25:          0          0   PCI-MSI-edge      pciehp
	 26:          0          0   PCI-MSI-edge      pciehp
	 27:          0          0   PCI-MSI-edge      pciehp
	 28:          0          0   PCI-MSI-edge      pciehp
	...
```
不管是desc->handle_irq还是__do_IRQ，它们都会调入到另外一个函数handle_IRQ_event()。重点：从CPU接收到中断信号并开始处理，到这个函数为止，都是处于中断禁止状态。为什么？很简单，因为Intel开发者手册上是这么说的，在文档325462.pdf卷3章节6.8.1 Masking Maskable Hardware Interrupts提到：
```
	When an interrupt is handled through an interrupt gate, the IF flag is automati-
	cally cleared, which disables maskable hardware interrupts. (If an interrupt is
	handled through a trap gate, the IF flag is not cleared.)
```
在CPU开始处理一个硬中断到进入函数handle_IRQ_event()为止的这段时间里，因为处于中断禁止状态，所以不会出现被其它中断打断的情况。但是，在进入到函数handle_IRQ_event()后，立马有了这么两句：
```
	irqreturn_t handle_IRQ_event(unsigned int irq, struct irqaction *action)
	{
		irqreturn_t ret, retval = IRQ_NONE;
		unsigned int status = 0;
	 
		if (!(action->flags & IRQF_DISABLED))
		    local_irq_enable_in_hardirq();
	...
```
函数local_irq_enable_in_hardirq()的定义如下：
```
	#ifdef CONFIG_LOCKDEP
	# define local_irq_enable_in_hardirq()  do { } while (0)
	#else
	# define local_irq_enable_in_hardirq()  local_irq_enable()
	#endif
```
宏CONFIG_LOCKDEP用于表示当前是否开启内核Lockdep功能，这是一个调试功能，用于检测潜在的死锁类风险，如果开启，那么函数local_irq_enable_in_hardirq()为空，即继续保持中断禁止状态，为什么Lockdep功能需要保持中断禁止待后文再述，这里考虑一般情况，即不开启Lockdep功能，那么执行函数local_irq_enable_in_hardirq()就会开启中断。
看函数handle_IRQ_event()里的代码，如果没有带上IRQF_DISABLED旗标，那么就会执行函数local_irq_enable_in_hardirq()，从而启用中断。旗标IRQF_DISABLED可在利用函数request_irq()注册中断处理回调时设置，比如：
```
	if (request_irq(uart->port.irq, bfin_serial_rx_int, IRQF_DISABLED,
		 "BFIN_UART_RX", uart)) {
```
如果没有设置，那么到函数handle_IRQ_event()这里的代码后，因为中断已经开启，当前中断的后续处理就可能被其它中断打断，从而出现中断嵌套的情况。

3，如果新来的中断类型与当前正在执行的中断类型相同，那么会暂时挂起。主要实现代码在函数__do_IRQ()（handle_fasteoi_irq()、handle_edge_irq()类似）内：
```
	/*
	 * If the IRQ is disabled for whatever reason, we cannot
	 * use the action we have.
	 */
	action = NULL;
	if (likely(!(status & (IRQ_DISABLED | IRQ_INPROGRESS)))) {
		action = desc->action;
		status &= ~IRQ_PENDING; /* we commit to handling */
		status |= IRQ_INPROGRESS; /* we are handling it */
	}
	desc->status = status;
	 
	/*
	 * If there is no IRQ handler or it was disabled, exit early.
	 * Since we set PENDING, if another processor is handling
	 * a different instance of this same irq, the other processor
	 * will take care of it.
	 */
	if (unlikely(!action))
		goto out;
```
逻辑很简单，如果当前中断被禁止（IRQ_DISABLED）或正在执行（IRQ_INPROGRESS），那么goto cot，所以同种类型中断不会相互嵌套。

4，从这个补丁开始，Linux内核已经全面禁止硬中断嵌套了，即从2.6.35开始，默认就是：
```
	run the irq handlers with interrupts disabled.
```
因为这个补丁，所以旗标IRQF_DISABLED没用了，mainline内核在逐步删除它。

我仔细检查了一下，对于2.6.34以及以前的内核，如果要合入这个补丁，那么有略微影响的主要是两个慢速驱动，分别为rtc-twl4030和twl4030-usb，需要按照类似开启Lockdep功能一样：
```
	#ifdef CONFIG_LOCKDEP
	/* WORKAROUND for lockdep forcing IRQF_DISABLED on us, which
	 * we don't want and can't tolerate.  Although it might be
	 * friendlier not to borrow this thread context...
	 */
	local_irq_enable();
	#endif
```
进行主动启用中断。还有另个一个慢速驱动IDE，其驱动中调用的是函数local_irq_enable_in_hardirq()，即它在开启Lockdep功能的情况下并没有明确要求启用中断，所以它应该不受补丁合入影响。嘛，我只是理论分析研究一下，仅供参考，如有风险，请实际操作者自行承担，:)。其它请看参考4，5，6。

#### 参考：
1，Linux下386中断处理  
2，Linux中断基础构架  
3，linux源码entry_32.S中interrupt数组的分析  
4，http://lwn.net/Articles/321663/  
5，http://lwn.net/Articles/380931/  
6，http://thread.gmane.org/gmane.linux.kernel/801267  

转载请保留地址：http://www.lenky.info/archives/2013/03/2245 或 http://lenky.info/?p=2245

