---
layout: post
title: "周期性调度器scheduler_tick"
date: 2014-05-22 16:57:00 +0800
comments: false
categories:
- 2014
- 2014~05
- kernel
- kernel~sched
tags:
---

周期性调度器由中断实现，系统定时产生一个中断，然后启动周期性调度器，周期性调度器执行过程中要关闭中断, 周期性调度器执行完毕后再打开中断(handle_IRQ_event,  IRQF_DISABLED)

周期性调度器主要做两个工作：  
a)更新相关统计量  
b) 检查进程执行的时间是否超过了它对应的ideal_runtime，如果超过了，则告诉系统，需要启动主调度器(schedule)进行进程切换。(注意 thread_info:preempt_count、thread_info:flags (TIF_NEED_RESCHED))

#### 周期性调度器
```
	|---->do_timer()   更新jiffies_64
	|---->update_process_times()
		|---->scheduler_tick()
		|---->update_rq_clock()  更新当前调度队列rq的clock
		|---->curr->sched_class->task_tick() 
		|         对于普通进程，即task_tick_fair()
		|         task_struct: struct sched_class *sched_class

update_rq_clock()----delta = sched_clock_cpu(cpu_of(rq)) - rq->clock
		|-----两次相邻两次周期性调度器运行的时间差
		|----rq->clock += delta; 更新运行队列上的时钟
			|---->update_rq_clock_task(rq, delta)
			|     即rq->clock_task += delta
```

#### 普通进程
```
task_tick_fair()---->entity_tick()   没有考虑组调度
	|---->update_curr() 更新相关统计量
	|---->check_preempt_tick()   
	|        检查进程本次获得CPU使用权的执行时间是否超过了
	|        它对应的ideal_runtime值，如果超过了，则将当前进
	|        程的TIF_NEED_RESCHED标志位置位

update_curr()
	|----delta_exec = (unsigned long)(now - curr->exec_start);  
	|            exec_start当前进程开始获得
	|            cpu使用权时的时间戳;
	|            进程本次所获得的CPU执行权的时间;
	|---->__update_curr(cfs_rq, curr, delta_exec);
		|---->curr->sum_exec_runtime += delta_exec; 
		|     更新该进程获得CPU执行权总时间
		|
		|---->curr->vruntime += delta_exec_weighted;
		|     更新该进程获得CPU执行权的虚拟时间
		|
		|---->update_min_vruntime()
		|     更新cfs_rq->min_vruntime
		|
	|---->curr->exec_start = now    
	|        更新进程下次运行起始时间
	|        (如果被抢占，下次被调度时将会更新)

check_preempt_tick()
	|----ideal_runtime = sched_slice(cfs_rq, curr);
	|----delta_exec = curr->sum_exec_runtime 
	|                 - curr->prev_sum_exec_runtime;
	|----if(delta_exec > ideal_runtime)  
	|          resched_task(rq_of(cfs_rq)->curr);
	|          把当前进程的TIF_NEED_RESCHED标志位置位
	|----else
	|    delta = curr->vruntime - se->vruntime;  //这是什么？
	|    if (delta > ideal_runtime)  
	|        resched_task(rq_of(cfs_rq)->curr);
	|        把当前进程的TIF_NEED_RESCHED标志位置位
```

#### 实时进程
```
task_tick_rt()
	|---->update_curr_rt();
	|---->if (p->policy != SCHED_RR) return;  SCHED_FIFO只有主动放弃CPU使用权
	|---->rt.timeslice值减一，若没有运行完时间则直接返回，
	|     否则再次分配时间片，加入队列尾部，设置TIF_NEED_RESCHED

update_curr_rt()
	|----delta_exec = rq->clock - curr->se.exec_start; //本次运行时间
	|----curr->se.sum_exec_runtime += delta_exec; //更新总得运行时间
	|----curr->se.exec_start = rq->clock; //更新下次进程运行的起始时间
	|----if (sched_rt_runtime(rt_rq) != RUNTIME_INF)
	|-------{
	|           rt_rq->rt_time += delta_exec;
	|                if (sched_rt_runtime_exceeded(rt_rq))
	|                   resched_task(curr);
	|       }
```

