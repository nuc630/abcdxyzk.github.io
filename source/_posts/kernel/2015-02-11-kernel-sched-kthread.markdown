---
layout: post
title: "内核线程使用"
date: 2015-02-11 11:06:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~sched
tags:
---
http://blog.csdn.net/newnewman80/article/details/7050090
##### kthread_create：创建线程。
```
struct task_struct *kthread_create(int (*threadfn)(void *data),void *data,const char *namefmt, ...);
```
线程创建后，不会马上运行，而是需要将kthread_create() 返回的task_struct指针传给wake_up_process()，然后通过此函数运行线程。
##### kthread_run ：创建并启动线程的函数：
```
struct task_struct *kthread_run(int (*threadfn)(void *data),void *data,const char *namefmt, ...);
```
##### kthread_stop：通过发送信号给线程，使之退出。
```
int kthread_stop(struct task_struct *thread);
```
线程一旦启动起来后，会一直运行，除非该线程主动调用do_exit函数，或者其他的进程调用kthread_stop函数，结束线程的运行。  
但如果线程函数正在处理一个非常重要的任务，它不会被中断的。当然如果线程函数永远不返回并且不检查信号，它将永远都不会停止。  
#### 1. 头文件
```
	#include <linux/sched.h>		//wake_up_process()
	#include <linux/kthread.h>		//kthread_create()、kthread_run()   
	#include <err.h>				//IS_ERR()、PTR_ERR()  
```
#### 2. 实现
##### 2.1创建线程
kernel thread可以用kernel_thread创建，但是在执行函数里面必须用daemonize释放资源并挂到init下，还需要用completion等待这一过程的完成。为了简化操作kthread_create闪亮登场。
在模块初始化时，可以进行线程的创建。使用下面的函数和宏定义：
```
	struct task_struct *kthread_create(int (*threadfn)(void *data),     
						void *data,  
						const char namefmt[], ...);  
```
```
	#define kthread_run(threadfn, data, namefmt, ...)                      \
	({                                                                     \
		struct task_struct *__k                                            \
			   = kthread_create(threadfn, data, namefmt, ## __VA_ARGS__);  \
		if (!IS_ERR(__k))                                                  \
			   wake_up_process(__k);                                       \
		__k;                                                               \
	})  
```
例如：
```
	static struct task_struct *test_task;  
	static int test_init_module(void)  
	{  
		int err;  
		test_task = kthread_create(test_thread, NULL, "test_task");  
		if (IS_ERR(test_task)) {  
			printk("Unable to start kernel thread./n");  
			err = PTR_ERR(test_task);  
			test_task = NULL;  
			return err;  
		}  
		wake_up_process(test_task);  
		return 0;  
	}  
	module_init(test_init_module);  
```

##### 2.2线程函数
在线程函数里，完成所需的业务逻辑工作。主要框架如下所示：
```
	int threadfunc(void *data) {
		...        
		while(1) {
			set_current_state(TASK_UNINTERRUPTIBLE);
			if (kthread_should_stop()) break;
			if () { //条件为真
				//进行业务处理
			} else { //条件为假
				//让出CPU运行其他线程，并在指定的时间内重新被调度
				schedule_timeout(HZ);
			}
		}
		...
		return 0;
	}
```

##### 2.3结束线程
在模块卸载时，可以结束线程的运行。使用下面的函数：
```
	int kthread_stop(struct task_struct *k);
```
例如：
```
	static void test_cleanup_module(void)  
	{  
		if (test_task) {  
			kthread_stop(test_task);  
			test_task = NULL;  
		}  
	}  
	module_exit(test_cleanup_module);  
```

#### 设置普通线程优先级
```
	void set_user_nice(struct task_struct *p, long nice);
	// -20 <= nice < 20
```

#### 将线程设置为实时线程并设置优先级
```
	int sched_setscheduler(struct task_struct *p, int policy, struct sched_param *param);
	struct sched_param {
		int sched_priority; // 实时线程对应区间[1, 99]
	};
```
CFS 调度模块（在 kernel/sched_fair.c 中实现）用于以下调度策略：SCHED_NORMAL、SCHED_BATCH 和 SCHED_IDLE。  
对于 SCHED_RR 和 SCHED_FIFO 策略，将使用实时调度模块（该模块在 kernel/sched_rt.c 中实现）。


#### top中NI, PR
NI，nice，动态修正CPU调度。范围（-20~19）。越大，cpu调度越一般，越小，cpu调度越偏向它。一般用于后台进程，调整也是往大了调，用来给前台进程让出CPU资源。命令行下可以用renice设置。

##### PR：优先级，会有两种格式，一种是数字（默认20），一种是RT字符串。
PR默认是20，越小，优先级越高。修改nice可以同时修改PR，测试过程：先开一个窗口，运行wc，另开一个窗口运行top，按N按照PID倒序排，按r输入要renice的PID，然后输入-19~20之间的值，可以看到NI变成输入的值，PR=PR+NI。修改NI得到PR的范围是0~39。优先级由高到低

RT是real-time。只能用chrt -p (1~99) pid来修改。chrt -p 1 1234会将1234的PR改成-2，chrt -p 98 1234变成-99。chrt -p 99 1234会变成RT......只要chrt过，修改nice后PR不会再更改。修改chrt得到的PR范围是RT~-2。优先级由高到低

