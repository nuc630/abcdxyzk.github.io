---
layout: post
title: "HAProxy 研究笔记 -- 主循环处理流程"
date: 2015-07-29 16:05:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3807412.html

本文简单介绍 HAProxy 主循环的处理逻辑，版本为 1.5-dev17.


#### 0. 主循环 run_poll_loop

HAproxy 的主循环在 haproxy.c 中的 run_poll_loop() 函数，代码如下：

```
	/* Runs the polling loop */
	void run_poll_loop()
	{
		int next;

		tv_update_date(0,1);
		while (1) {
			/* check if we caught some signals and process them */
			signal_process_queue();

			/* Check if we can expire some tasks */
			wake_expired_tasks(&next);

			/* Process a few tasks */
			process_runnable_tasks(&next);

			/* stop when there's nothing left to do */
			if (jobs == 0)
				break;

			/* The poller will ensure it returns around  */
			cur_poller.poll(&cur_poller, next);
			fd_process_spec_events();
		}
	}
```

主循环的结构比较清晰，就是循环的调用几个函数，并在适当的时候结束循环并退出：

```
	1. 处理信号队列
	2. 超时任务
	3. 处理可运行的任务
	4. 检测是否可以结束循环
	5. 执行 poll 处理 fd 的 IO 事件
	6. 处理可能仍有 IO 事件的 fd
```

#### 1. signal_process_queue - 处理信号队对列

haproxy 实现了自己的信号处理机制。接受到信号之后，将该信号放到信号队列中。在程序 运行到 signal_process_queue() 时处理所有位于信号队列中的信号。

#### 2. wake_expired_tasks - 唤醒超时任务

haproxy 的顶层处理逻辑是 task，task 上存储着要处理的任务的全部信息。task 的管理 是采用队列方式，同时分为 wait queue 和 run queue。顾名思义，wait queue 是需要等 待一定时间的 task 的集合，而 run queue 则代表需要立即执行的 task 的集合。

该函数就是检查 wait queue 中那些超时的任务，并将其放到 run queue 中。haproxy 在 执行的过程中，会因为一些情况导致需要将当前的任务通过调用 task_queue 等接口放到 wait queue 中。

#### 3. process_runnable_tasks - 处理可运行的任务

处理位于 run queue 中的任务。

前面提到，wake_expired_tasks 可能将一些超时的任务放到 run queue 中。此外，haproxy 执行的过程中，还有可能通过调用 task_wakeup 直接讲某个 task 放到 run queue 中，这代表程序希望该任务下次尽可能快的被执行。

对于 TCP 或者 HTTP 业务流量的处理，该函数最终通过调用 process_session 来完成，包括解析已经接收到的数据， 并执行一系列 load balance 的特性，但不负责从 socket 收发数据。

#### 4. jobs == 0 - 无任务可执行，结束循环

haproxy 中用 jobs 记录当前要处理的任务总数，一个 listener 也会被计算在内。因此， 如果 jobs 为 0 的话，通常意味着 haproxy 要退出了，因为连 listener 都要释放了。 jobs 的数值通常在 process_session 时更新。因此，是否可以退出循环，就放在了所有 任务的 process_session 执行之后。

#### 5. cur_poller.poll() - 执行 poll 处理 fd 的 IO 事件

haproxy 启动阶段，会检测当前系统可以启用那种异步处理的机制，比如 select、poll、 epoll、kqueue 等，并注册对应 poller 的 poll 方法。epoll 的相关函数接口在 ev_epoll.c 中。

这里就是执行已经注册的 poller 的 poll 方法，主要功能就是获取所有活动的 fd，并 调用对应的 handler，完成接受新建连接、数据收发等功能。

#### 6. 处理可能仍有 IO 事件的 fd

poller 的 poll 方法执行时，程序会将某些符合条件以便再次执行 IO 处理的的 fd 放到 fd_spec list[] 中，fd_process_spec_events() 函数会再次执行这些 fd 的 io handler。 

