---
layout: post
title: "tsc时钟初始化"
date: 2014-05-29 14:03:00 +0800
comments: false
categories:
- 2014
- 2014~05
- kernel
- kernel~sched
tags:
---

##### tsc时钟源初始化
```
//    调用路径：time_init->tsc_init
//    函数任务：
//        1.矫正tsc，获取tsc频率，设置cpu频率等于tsc频率
//        2.初始化基于tsc的延迟函数
//        3.检查tsc的特性
//            3.1 tsc之间是否同步
//                3.1.1 如果tsc之间不同步，标记tsc不稳定，设置rating=0
//            3.2 tsc是否稳定
//        4.注册tsc时钟源设备
```

```
void __init tsc_init(void)
{
    u64 lpj;
    int cpu;

    //矫正tsc，获取tsc频率
    tsc_khz = x86_platform.calibrate_tsc();
    //cpu频率等于tsc频率
    cpu_khz = tsc_khz;
    //计算辅助cycle到ns转换的辅助参数scale
    for_each_possible_cpu(cpu)
        set_cyc2ns_scale(cpu_khz, cpu);
    //初始化基于tsc的延迟函数，ndely，udelay，mdelay
    use_tsc_delay();
    //检查cpu之间tsc是否同步
    if (unsynchronized_tsc())
        mark_tsc_unstable("TSCs unsynchronized");
    //检查tsc是否可靠
    check_system_tsc_reliable();
    //注册tsc时钟源设备
    init_tsc_clocksource();
}
```

##### 延迟函数ndelay，udelay，mdelay
通过tsc实现短延迟
```
	void use_tsc_delay(void)
	{
		//通过tsc进行短延迟
		delay_fn = delay_tsc;
	}
```

##### tsc延迟函数
通过rep_nop实现轮询时的短延迟，查询tsc时禁止内核抢占，确保不受不同cpu间影响。
```
static void delay_tsc(unsigned long loops)
{
    unsigned long bclock, now;
    int cpu;
    //短延迟，禁止内核抢占
    preempt_disable();
    //delay_tsc当前运行的cpu
    cpu = smp_processor_id();
    rdtsc_barrier();
    rdtscl(bclock);
    for (;;) {
        rdtsc_barrier();
        rdtscl(now);
        if ((now - bclock) >= loops)
            break;
        //允许rt策略进程运行
        preempt_enable();
        //空操作
        rep_nop();
        preempt_disable();

        //delay_tsc在运行过程中，可能会迁移到不同的cpu
        //tsc
        if (unlikely(cpu != smp_processor_id())) {
            loops -= (now - bclock);
            cpu = smp_processor_id();
            rdtsc_barrier();
            rdtscl(bclock);
        }
    }
    preempt_enable();
}
```

##### 检查tsc是否同步
```
//    调用路径：tsc_init->unsynchronized_tsc
//    检查办法：
//        1.如果apic在多块板卡，则tsc不同步
//        2.如果cpuid显示具有稳定的tsc，则tsc同步
//        3.intel cpu的tsc都是同步的
//        4.默认其他品牌的多核的tsc不同步
```

```
	__cpuinit int unsynchronized_tsc(void)
	{
		//如果apic分布在多块板卡上，tsc可能不同步
		if (apic_is_clustered_box())
		    return 1;
		//cpu具有稳定的tsc
		if (boot_cpu_has(X86_FEATURE_CONSTANT_TSC))
		    return 0;
		//intel cpu的tsc都是同步的
		if (boot_cpu_data.x86_vendor != X86_VENDOR_INTEL) {
		    //非intel cpu，如果cpu个数>1,则认为不同步
		    if (num_possible_cpus() > 1)
		        tsc_unstable = 1;
		}
		return tsc_unstable;
	}
```

##### 标记tsc不稳定
```
//    调用路径：tsc_init->mark_tsc_unstable
//    函数任务：
//        1.如果tsc时钟已经注册，异步设置tsc的rating=0，标识其不稳定
//        2.如果tsc时钟还未注册，同步设置tsc的rating=0，标识其不稳定
```
```
	void mark_tsc_unstable(char *reason)
	{
		if (!tsc_unstable) {
		    tsc_unstable = 1;
		    sched_clock_stable = 0;
		    //tsc已经注册，
		    if (clocksource_tsc.mult)
		    {
		        clocksource_mark_unstable(&clocksource_tsc);
		    }
		    //如果tsc时钟源未注册，修改rating为最低，从而不会被当做最佳的时钟源
		    else {
		        clocksource_tsc.flags |= CLOCK_SOURCE_UNSTABLE;
		        clocksource_tsc.rating = 0;
		    }
		}
	}
```

##### 注册tsc时钟源
```
	//    函数任务：
	//        1.计算tsc的mult
	//        2.检查tsc是否稳定
	//            2.1 如果tsc不稳定，降低其rating，清除时钟源连续标志
	//        3.向系统注册tsc clocksource
	//    调用路径：tsc_init->init_tsc_clocksource
```
```
	static void __init init_tsc_clocksource(void)
	{
		// 计算tsc的mult
		clocksource_tsc.mult = clocksource_khz2mult(tsc_khz,
		        clocksource_tsc.shift);
		// 如果tsc的可靠性已经验证，则清除 必须验证 标记
		if (tsc_clocksource_reliable)
		    clocksource_tsc.flags &= ~CLOCK_SOURCE_MUST_VERIFY;
		
		// 检查tsc是否稳定
		// 在tsc_init前通过全局变量标记tsc是否稳定，可靠
		if (check_tsc_unstable()) {
		    // 如果tsc不稳定，则降低rating最低，清除连续标记
		    clocksource_tsc.rating = 0;
		    clocksource_tsc.flags &= ~CLOCK_SOURCE_IS_CONTINUOUS;
		}
		// 向系统注册tsc clocksource
		clocksource_register(&clocksource_tsc);
	}
```

