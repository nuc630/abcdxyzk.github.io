---
layout: post
title: "mod_timer会切换cpu"
date: 2015-01-14 23:59:01 +0800
comments: false
categories:
- 2015
- 2015~01
- debug
- debug~mark
tags:
---
https://lkml.org/lkml/2009/4/16/45

> Ingo, Thomas, all,

> In an SMP system, tasks are scheduled on different CPUs by the
scheduler, interrupts are managed by irqbalancer daemon, but timers
are still stuck to the CPUs that they have been initialised.  Timers
queued by tasks gets re-queued on the CPU where the task gets to run
next, but timers from IRQ context like the ones in device drivers are
still stuck on the CPU they were initialised.  This framework will
help move all 'movable timers' using a sysctl interface.

kernel/timer.c 中 __mod_timer函数的部分patch：
```
+	cpu = smp_processor_id();
+	if (get_sysctl_timer_migration() && idle_cpu(cpu) && !pinned) {
+#if defined(CONFIG_NO_HZ) && (CONFIG_SMP)
+		preferred_cpu = get_nohz_load_balancer();
+#endif
+		if (preferred_cpu >= 0)
+			cpu = preferred_cpu;
+	}
+
+	new_base = per_cpu(tvec_bases, cpu);
+
```

---------------

也就是说：如果当前进程是idle（函数idle_cpu(cpu)判定），那么在mod_timer时会根据cpu的struct rq runqueues;中的 struct sched_domain *sd; 来选一个不是idle的cpu，然后把timer移到他上去。如果都是idle，就还在本cpu。  
禁用该功能可以 echo 0 > /proc/sys/kernel/timer_magration，默认的启用是1。

也就是说：系统默认状态下mod_timer有可能会mod_timer到其他cpu上。

---------------

但是基本只有softirq时（如 [/blog/2015/01/14/debug-softirq-time-count/](/blog/2015/01/14/debug-softirq-time-count/)），这时会的当前进程就是idle，但cpu实际并不空闲。这样的话softirq的timer在mod_timer时，会被加到其他cpu的定时器队列。如果这些timer是不允许切换cpu的（如对per_cpu变量的操作），那么就会产生bug。

