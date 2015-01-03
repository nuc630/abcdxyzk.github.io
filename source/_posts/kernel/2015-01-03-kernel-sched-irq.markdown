---
layout: post
title: "硬中断和软中断"
date: 2015-01-03 15:15:00 +0800
comments: false
categories:
- 2015
- 2015~01
- kernel
- kernel~sched
tags:
---
http://blog.csdn.net/zhangskd/article/details/21992933

#### 概述
从本质上来讲，中断是一种电信号，当设备有某种事件发生时，它就会产生中断，通过总线把电信号发送给中断控制器。
如果中断的线是激活的，中断控制器就把电信号发送给处理器的某个特定引脚。处理器于是立即停止自己正在做的事，
跳到中断处理程序的入口点，进行中断处理。

##### (1) 硬中断
由与系统相连的外设(比如网卡、硬盘)自动产生的。主要是用来通知操作系统系统外设状态的变化。比如当网卡收到数据包的时候，就会发出一个中断。我们通常所说的中断指的是硬中断(hardirq)。

##### (2) 软中断
为了满足实时系统的要求，中断处理应该是越快越好。linux为了实现这个特点，当中断发生的时候，硬中断处理那些短时间就可以完成的工作，而将那些处理事件比较长的工作，放到中断之后来完成，也就是软中断(softirq)来完成。

##### (3) 中断嵌套
Linux下硬中断是可以嵌套的，但是没有优先级的概念，也就是说任何一个新的中断都可以打断正在执行的中断，但同种中断除外。软中断不能嵌套，但相同类型的软中断可以在不同CPU上并行执行。

##### (4) 软中断指令
int是软中断指令。  
中断向量表是中断号和中断处理函数地址的对应表。  
int n - 触发软中断n。相应的中断处理函数的地址为：中断向量表地址 + 4 * n。

##### (5)硬中断和软中断的区别
软中断是执行中断指令产生的，而硬中断是由外设引发的。  
硬中断的中断号是由中断控制器提供的，软中断的中断号由指令直接指出，无需使用中断控制器。  
硬中断是可屏蔽的，软中断不可屏蔽。  
硬中断处理程序要确保它能快速地完成任务，这样程序执行时才不会等待较长时间，称为上半部。  
软中断处理硬中断未完成的工作，是一种推后执行的机制，属于下半部。  

#### 开关
##### (1) 硬中断的开关
简单禁止和激活当前处理器上的本地中断：
```
local_irq_disable();
local_irq_enable();
```
保存本地中断系统状态下的禁止和激活：
```
unsigned long flags;
local_irq_save(flags);
local_irq_restore(flags);
```

##### (2) 软中断的开关
禁止下半部，如softirq、tasklet和workqueue等：
```
local_bh_disable();
local_bh_enable();
```
需要注意的是，禁止下半部时仍然可以被硬中断抢占。

##### (3) 判断中断状态
```
	#define in_interrupt() (irq_count()) // 是否处于中断状态(硬中断或软中断)
	#define in_irq() (hardirq_count()) // 是否处于硬中断
	#define in_softirq() (softirq_count()) // 是否处于软中断
```

#### 硬中断
##### (1) 注册中断处理函数

注册中断处理函数：
```
    /** 
     * irq: 要分配的中断号 
     * handler: 要注册的中断处理函数 
     * flags: 标志(一般为0) 
     * name: 设备名(dev->name) 
     * dev: 设备(struct net_device *dev)，作为中断处理函数的参数 
     * 成功返回0 
     */  
      
    int request_irq(unsigned int irq, irq_handler_t handler, unsigned long flags,   
        const char *name, void *dev);  
```

中断处理函数本身：
```
    typedef irqreturn_t (*irq_handler_t) (int, void *);  
      
    /** 
     * enum irqreturn 
     * @IRQ_NONE: interrupt was not from this device 
     * @IRQ_HANDLED: interrupt was handled by this device 
     * @IRQ_WAKE_THREAD: handler requests to wake the handler thread 
     */  
    enum irqreturn {  
        IRQ_NONE,  
        IRQ_HANDLED,  
        IRQ_WAKE_THREAD,  
    };  
    typedef enum irqreturn irqreturn_t;  
    #define IRQ_RETVAL(x) ((x) != IRQ_NONE)  
```

##### (2) 注销中断处理函数
```
    /** 
     * free_irq - free an interrupt allocated with request_irq 
     * @irq: Interrupt line to free 
     * @dev_id: Device identity to free 
     * 
     * Remove an interrupt handler. The handler is removed and if the 
     * interrupt line is no longer in use by any driver it is disabled. 
     * On a shared IRQ the caller must ensure the interrupt is disabled 
     * on the card it drives before calling this function. The function does 
     * not return until any executing interrupts for this IRQ have completed. 
     * This function must not be called from interrupt context. 
     */  
      
    void free_irq(unsigned int irq, void *dev_id);  
```

#### 软中断
##### (1) 定义
软中断是一组静态定义的下半部接口，可以在所有处理器上同时执行，即使两个类型相同也可以。  
但一个软中断不会抢占另一个软中断，唯一可以抢占软中断的是硬中断。

软中断由softirq_action结构体表示：
```
    struct softirq_action {  
        void (*action) (struct softirq_action *); /* 软中断的处理函数 */  
    };  
```

目前已注册的软中断有10种，定义为一个全局数组：
```
    static struct softirq_action softirq_vec[NR_SOFTIRQS];  
      
    enum {  
        HI_SOFTIRQ = 0, /* 优先级高的tasklets */  
        TIMER_SOFTIRQ, /* 定时器的下半部 */  
        NET_TX_SOFTIRQ, /* 发送网络数据包 */  
        NET_RX_SOFTIRQ, /* 接收网络数据包 */  
        BLOCK_SOFTIRQ, /* BLOCK装置 */  
        BLOCK_IOPOLL_SOFTIRQ,  
        TASKLET_SOFTIRQ, /* 正常优先级的tasklets */  
        SCHED_SOFTIRQ, /* 调度程序 */  
        HRTIMER_SOFTIRQ, /* 高分辨率定时器 */  
        RCU_SOFTIRQ, /* RCU锁定 */  
        NR_SOFTIRQS /* 10 */  
    };  
```

##### (2) 注册软中断处理函数
```
    /** 
     * @nr: 软中断的索引号 
     * @action: 软中断的处理函数 
     */  
      
    void open_softirq(int nr, void (*action) (struct softirq_action *))  
    {  
        softirq_vec[nr].action = action;  
    }  
```
例如：
```
open_softirq(NET_TX_SOFTIRQ, net_tx_action);
open_softirq(NET_RX_SOFTIRQ, net_rx_action);
```

##### (3) 触发软中断 
调用raise_softirq()来触发软中断。
```
    void raise_softirq(unsigned int nr)  
    {  
        unsigned long flags;  
        local_irq_save(flags);  
        raise_softirq_irqoff(nr);  
        local_irq_restore(flags);  
    }  
      
    /* This function must run with irqs disabled */  
    inline void rasie_softirq_irqsoff(unsigned int nr)  
    {  
        __raise_softirq_irqoff(nr);  
      
        /* If we're in an interrupt or softirq, we're done 
         * (this also catches softirq-disabled code). We will 
         * actually run the softirq once we return from the irq 
         * or softirq. 
         * Otherwise we wake up ksoftirqd to make sure we 
         * schedule the softirq soon. 
         */  
        if (! in_interrupt()) /* 如果不处于硬中断或软中断 */  
            wakeup_softirqd(void); /* 唤醒ksoftirqd/n进程 */  
    }  
```

Percpu变量irq_cpustat_t中的__softirq_pending是等待处理的软中断的位图，通过设置此变量

即可告诉内核该执行哪些软中断。
```
    static inline void __rasie_softirq_irqoff(unsigned int nr)  
    {  
        trace_softirq_raise(nr);  
        or_softirq_pending(1UL << nr);  
    }  
      
    typedef struct {  
        unsigned int __softirq_pending;  
        unsigned int __nmi_count; /* arch dependent */  
    } irq_cpustat_t;  
      
    irq_cpustat_t irq_stat[];  
    #define __IRQ_STAT(cpu, member) (irq_stat[cpu].member)  
    #define or_softirq_pending(x) percpu_or(irq_stat.__softirq_pending, (x))  
    #define local_softirq_pending() percpu_read(irq_stat.__softirq_pending)  
```

唤醒ksoftirqd内核线程处理软中断。
```
    static void wakeup_softirqd(void)  
    {  
        /* Interrupts are disabled: no need to stop preemption */  
        struct task_struct *tsk = __get_cpu_var(ksoftirqd);  
      
        if (tsk && tsk->state != TASK_RUNNING)  
            wake_up_process(tsk);  
    }  
```

在下列地方，待处理的软中断会被检查和执行：  
1. 从一个硬件中断代码处返回时  
2. 在ksoftirqd内核线程中  
3. 在那些显示检查和执行待处理的软中断的代码中，如网络子系统中

而不管是用什么方法唤起，软中断都要在do_softirq()中执行。如果有待处理的软中断，do_softirq()会循环遍历每一个，调用它们的相应的处理程序。在中断处理程序中触发软中断是最常见的形式。中断处理程序执行硬件设备的相关操作，然后触发相应的软中断，最后退出。内核在执行完中断处理程序以后，马上就会调用do_softirq()，于是软中断开始执行中断处理程序完成剩余的任务。

下面来看下do_softirq()的具体实现。
```
    asmlinkage void do_softirq(void)  
    {  
        __u32 pending;  
        unsigned long flags;  
      
        /* 如果当前已处于硬中断或软中断中，直接返回 */  
        if (in_interrupt())   
            return;  
      
        local_irq_save(flags);  
        pending = local_softirq_pending();  
        if (pending) /* 如果有激活的软中断 */  
            __do_softirq(); /* 处理函数 */  
        local_irq_restore(flags);  
    }  
```
```
    /* We restart softirq processing MAX_SOFTIRQ_RESTART times, 
     * and we fall back to softirqd after that. 
     * This number has been established via experimentation. 
     * The two things to balance is latency against fairness - we want 
     * to handle softirqs as soon as possible, but they should not be 
     * able to lock up the box. 
     */  
    asmlinkage void __do_softirq(void)  
    {  
        struct softirq_action *h;  
        __u32 pending;  
        /* 本函数能重复触发执行的次数，防止占用过多的cpu时间 */  
        int max_restart = MAX_SOFTIRQ_RESTART;  
        int cpu;  
      
        pending = local_softirq_pending(); /* 激活的软中断位图 */  
        account_system_vtime(current);  
        /* 本地禁止当前的软中断 */  
        __local_bh_disable((unsigned long)__builtin_return_address(0), SOFTIRQ_OFFSET);  
        lockdep_softirq_enter(); /* current->softirq_context++ */  
        cpu = smp_processor_id(); /* 当前cpu编号 */  
      
    restart:  
        /* Reset the pending bitmask before enabling irqs */  
        set_softirq_pending(0); /* 重置位图 */  
        local_irq_enable();  
        h = softirq_vec;  
        do {  
            if (pending & 1) {  
                unsigned int vec_nr = h - softirq_vec; /* 软中断索引 */  
                int prev_count = preempt_count();  
                kstat_incr_softirqs_this_cpu(vec_nr);  
      
                trace_softirq_entry(vec_nr);  
                h->action(h); /* 调用软中断的处理函数 */  
                trace_softirq_exit(vec_nr);  
      
                if (unlikely(prev_count != preempt_count())) {  
                    printk(KERN_ERR "huh, entered softirq %u %s %p" "with preempt_count %08x,"  
                        "exited with %08x?\n", vec_nr, softirq_to_name[vec_nr], h->action, prev_count,  
                        preempt_count());  
                }  
                rcu_bh_qs(cpu);  
            }  
            h++;  
            pending >>= 1;  
        } while(pending);  
      
        local_irq_disable();  
        pending = local_softirq_pending();  
        if (pending & --max_restart) /* 重复触发 */  
            goto restart;  
      
        /* 如果重复触发了10次了，接下来唤醒ksoftirqd/n内核线程来处理 */  
        if (pending)  
            wakeup_softirqd();   
      
        lockdep_softirq_exit();  
        account_system_vtime(current);  
        __local_bh_enable(SOFTIRQ_OFFSET);  
    }  
```

##### (4) ksoftirqd内核线程
内核不会立即处理重新触发的软中断。  
当大量软中断出现的时候，内核会唤醒一组内核线程来处理。  
这些线程的优先级最低(nice值为19)，这能避免它们跟其它重要的任务抢夺资源。  
但它们最终肯定会被执行，所以这个折中的方案能够保证在软中断很多时用户程序不会因为得不到处理时间而处于饥饿状态，同时也保证过量的软中断最终会得到处理。

每个处理器都有一个这样的线程，名字为ksoftirqd/n，n为处理器的编号。
```
    static int run_ksoftirqd(void *__bind_cpu)  
    {  
        set_current_state(TASK_INTERRUPTIBLE);  
        current->flags |= PF_KSOFTIRQD; /* I am ksoftirqd */  
      
        while(! kthread_should_stop()) {  
            preempt_disable();  
      
            if (! local_softirq_pending()) { /* 如果没有要处理的软中断 */  
                preempt_enable_no_resched();  
                schedule();  
                preempt_disable():  
            }  
      
            __set_current_state(TASK_RUNNING);  
      
            while(local_softirq_pending()) {  
                /* Preempt disable stops cpu going offline. 
                 * If already offline, we'll be on wrong CPU: don't process. 
                 */  
                 if (cpu_is_offline(long)__bind_cpu))/* 被要求释放cpu */  
                     goto wait_to_die;  
      
                do_softirq(); /* 软中断的统一处理函数 */  
      
                preempt_enable_no_resched();  
                cond_resched();  
                preempt_disable();  
                rcu_note_context_switch((long)__bind_cpu);  
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
        while(! kthread_should_stop()) {  
            schedule();  
            set_current_state(TASK_INTERRUPTIBLE);  
        }  
      
        __set_current_state(TASK_RUNNING);  
        return 0;  
    }
```

