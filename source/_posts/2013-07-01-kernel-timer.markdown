---
layout: post
title: "内核定时器的使用"
date: 2013-07-01 09:46:00 +0800
comments: false
categories:
- 2013
- 2013~07
- kernel
- kernel~base
tags:
---
LINUX内核定时器是内核用来控制在未来某个时间点（基于jiffies）调度执行某个函数的一种机制，其实现位于 <linux/timer.h> 和 kernel/timer.c 文件中。

被调度的函数肯定是异步执行的，它类似于一种“软件中断”，而且是处于非进程的上下文中，所以调度函数必须遵守以下规则：  
1. 没有 current 指针、不允许访问用户空间。因为没有进程上下文，相关代码和被中断的进程没有任何联系。  
2. 不能执行休眠（或可能引起休眠的函数）和调度。  
3. 任何被访问的数据结构都应该针对并发访问进行保护，以防止竞争条件。  
 
内核定时器的调度函数运行过一次后就不会再被运行了（相当于自动注销），但可以通过在被调度的函数中重新调度自己来周期运行。
 
在SMP系统中，调度函数总是在注册它的同一CPU上运行，以尽可能获得缓存的局域性。
 
#### 定时器API
 
内核定时器的数据结构
```
struct timer_list {
	struct list_head entry;
 
	unsigned long expires;
	void (*function)(unsigned long);
	unsigned long data;
 
	struct tvec_base *base;
	/* ... */
};
```
其中 expires 字段表示期望定时器执行的 jiffies 值，到达该 jiffies 值时，将调用 function 函数，并传递  data 作为参数。当一个定时器被注册到内核之后，entry 字段用来连接该定时器到一个内核链表中。base 字段是内核内部实现所用的。
需要注意的是 expires 的值是32位的，因为内核定时器并不适用于长的未来时间点。
 
##### 初始化
在使用 struct timer_list 之前，需要初始化该数据结构，确保所有的字段都被正确地设置。初始化有两种方法。

##### 方法一：
```
DEFINE_TIMER(timer_name, function_name, expires_value, data);
```
该宏会静态创建一个名叫 timer_name 内核定时器，并初始化其 function, expires, name 和 base 字段。
 
##### 方法二：
```
struct timer_list mytimer;
setup_timer(&mytimer, (*function)(unsigned long), unsigned long data);
mytimer.expires = jiffies + 5*HZ;
```

##### 方法三：
```
struct timer_list mytimer;
init_timer(&mytimer);
  mytimer ->timer.expires = jiffies + 5*HZ;
  mytimer ->timer.data = (unsigned long) dev;
  mytimer ->timer.function = &corkscrew_timer; /* timer handler */
```
通过init_timer()动态地定义一个定时器，此后，将处理函数的地址和参数绑定给一个timer_list，  
注意，无论用哪种方法初始化，其本质都只是给字段赋值，所以只要在运行 add_timer() 之前，expires, function 和 data 字段都可以直接再修改。  
关于上面这些宏和函数的定义，参见 include/linux/timer.h。
 
##### 注册
定时器要生效，还必须被连接到内核专门的链表中，这可以通过 add_timer(struct timer_list *timer) 来实现。
 
##### 重新注册
要修改一个定时器的调度时间，可以通过调用 mod_timer(struct timer_list *timer, unsigned long expires)。mod_timer() 会重新注册定时器到内核，而不管定时器函数是否被运行过。
 
##### 注销
注销一个定时器，可以通过 del_timer(struct timer_list *timer) 或  del_timer_sync(struct timer_list *timer)。其中 del_timer_sync 是用在 SMP  系统上的（在非SMP系统上，它等于del_timer），当要被注销的定时器函数正在另一个 cpu 上运行时，del_timer_sync()  会等待其运行完，所以这个函数会休眠。另外还应避免它和被调度的函数争用同一个锁。对于一个已经被运行过且没有重新注册自己的定时器而言，注销函数其实也 没什么事可做。
 
```
	int timer_pending(const struct timer_list *timer)
```
这个函数用来判断一个定时器是否被添加到了内核链表中以等待被调度运行。注意，当一个定时器函数即将要被运行前，内核会把相应的定时器从内核链表中删除（相当于注销）
 
##### 例子1：
```
	#include <linux/module.h>
	#include <linux/timer.h>
	#include <linux/jiffies.h>
	 
	struct timer_list mytimer;
	static void myfunc(unsigned long data)
	{
		printk("%s/n", (char *)data);
		mod_timer(&mytimer, jiffies + 2*HZ);
	}
	 
	static int __init mytimer_init(void)
	{
		setup_timer(&mytimer, myfunc, (unsigned long)"Hello, world!");
		mytimer.expires = jiffies + HZ;
		add_timer(&mytimer);
		return 0;
	}
	 
	static void __exit mytimer_exit(void)
	{
		del_timer(&mytimer);
	}
	module_init(mytimer_init);
	module_exit(mytimer_exit);
```

##### 例子2：
```
	static struct timer_list power_button_poll_timer;
	static void power_button_poll(unsigned long dummy)
	{
		if (gpio_line_get(N2100_POWER_BUTTON) == 0) {
			ctrl_alt_del();
			return;
		}
		power_button_poll_timer.expires = jiffies + (HZ / 10);
		add_timer(&power_button_poll_timer);
	}
	static void __init n2100_init_machine(void)
	{
	...
		init_timer(&power_button_poll_timer);
		power_button_poll_timer.function = power_button_poll;
		power_button_poll_timer.expires = jiffies + (HZ / 10);
		add_timer(&power_button_poll_timer);
	}
```

##### 例子3：
设备open时初始化和注册定时器
```
	static int corkscrew_open(struct net_device *dev)
	{
	...
		  init_timer(&vp->timer);    
		  vp->timer.expires = jiffies + media_tbl[dev->if_port].wait;
		  vp->timer.data = (unsigned long) dev;
		  vp->timer.function = &corkscrew_timer; /* timer handler */
		  add_timer(&vp->timer);
	...
	}
```
定时器超时处理函数，对定时器的超时时间重新赋值
```
	static void corkscrew_timer(unsigned long data)
	{
	...
		vp->timer.expires = jiffies + media_tbl[dev->if_port].wait;
		add_timer(&vp->timer);
	...
	}
	 
	设备close时删除定时器
	static int corkscrew_close(struct net_device *dev)
	{
	...
		del_timer(&vp->timer);
	...
	}
```

##### 例子4：
本例子用DEFINE_TIMER静态创建定时器
```
	#include <linux/module.h>
	#include <linux/jiffies.h>
	#include <linux/kernel.h>
	#include <linux/init.h>
	#include <linux/timer.h>
	#include <linux/leds.h>
	static void ledtrig_ide_timerfunc(unsigned long data);
	DEFINE_LED_TRIGGER(ledtrig_ide);
	static DEFINE_TIMER(ledtrig_ide_timer, ledtrig_ide_timerfunc, 0, 0);
	static int ide_activity;
	static int ide_lastactivity;
	void ledtrig_ide_activity(void)
	{
		ide_activity++;
		if (!timer_pending(&ledtrig_ide_timer))
			mod_timer(&ledtrig_ide_timer, jiffies + msecs_to_jiffies(10));
	}
	EXPORT_SYMBOL(ledtrig_ide_activity);
	static void ledtrig_ide_timerfunc(unsigned long data)
	{
		if (ide_lastactivity != ide_activity) {
			ide_lastactivity = ide_activity;
			led_trigger_event(ledtrig_ide, LED_FULL);
			mod_timer(&ledtrig_ide_timer, jiffies + msecs_to_jiffies(10));
		} else {
			led_trigger_event(ledtrig_ide, LED_OFF);
		}
	}
	static int __init ledtrig_ide_init(void)
	{
		led_trigger_register_simple("ide-disk", &ledtrig_ide);
		return 0;
	}
	static void __exit ledtrig_ide_exit(void)
	{
		led_trigger_unregister_simple(ledtrig_ide);
	}
	module_init(ledtrig_ide_init);
	module_exit(ledtrig_ide_exit);
```
--------------
```
	add_timer() -- 将定时器添加到定时器等待队列中
	用add_timer()函数来看timer_base的作用
	static inline void add_timer(struct timer_list *timer)
	{
		BUG_ON(timer_pending(timer));
		__mod_timer(timer, timer->expires);
	}

	int __mod_timer(struct timer_list *timer, unsigned long expires)
	{
		tvec_base_t *base, *new_base;
		unsigned long flags;
		int ret = 0;
		timer_stats_timer_set_start_info(timer);
		BUG_ON(!timer->function);
		base = lock_timer_base(timer, &flags);
	如果timer已经放到定时链表中,则释放开
	|--------------------------------|
	|   if (timer_pending(timer)) { -|
	|       detach_timer(timer, 0); -|
	|       ret = 1;                 |
	|   }                            |
	|--------------------------------|
	获取当前CPU的timer base
	|-----------------------------------------|
	|   new_base = __get_cpu_var(tvec_bases); |
	|-----------------------------------------|
	如果当前CPU的timer base不是当前timer中的base, 更新timer的base
	|----------------------------------------------------|
	|   if (base != new_base) {                          |
	|       if (likely(base->running_timer != timer)) { -|
	|           timer->base = NULL;                      |
	|           spin_unlock(&base->lock);                |
	|           base = new_base;                         |
	|           spin_lock(&base->lock);                  |
	|           timer->base = base;                      |
	|       }                                            |
	|   }                                                |
	|----------------------------------------------------|
	给定时器timer设置超时时间；并添加该时钟
	|-------------------------------------|
	|   timer->expires = expires;         |
	|   internal_add_timer(base, timer); -|
	|-------------------------------------|
		spin_unlock_irqrestore(&base->lock, flags);
		return ret;
	}
	MODULE_LICENSE("GPL");
```
