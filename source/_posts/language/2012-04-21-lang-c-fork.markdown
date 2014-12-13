---
layout: post
title: "避免僵死进程"
date: 2012-04-21 19:45:00 +0800
comments: false
categories:
- 2012
- 2012~04
- language
- language~c
tags:
- koj
- judge
---
#### 一 两次fork避免僵死进程
如果在一个进程A中启动了一个子进程B，但是B的执行时间可能很长，也可能很短。因此，既不希望A调用wait或者waitpid来等待B的完成（如果B执行时间太长，A的时间就耗费在等待B的完成了，虽然waitpid有WNOHANG选项，但免不了多次调用waitpid来看B是否完成）；也不希望如果B执行时间太短了，然后A又不用wait或waitpid去获取B的退出状态，那么B就一直处于僵死状态直到A终止（这样造成了资源的浪费）。

此时，可以使用一个小trick。就是调用两次fork，让B的父进程变成init进程（pid=1的那个进程，所有孤儿进程的父进程）。这样，A进程可以想干嘛干嘛去，B进程也可以想执行多久就执行多久了。
```
	#include <unistd.h>
	#include <sys/wait.h>
	int main()
	{
		pid_t pid;
		if((pid=fork())<0)
		{
			printf("fork 1 error\n");
			exit(-1);
		}
		else if(pid==0）//第一个子进程
		{
			if((pid=fork())<0)
			{
				printf("fork 2 error\n");
				exit(-1);
			}
			else if(pid>0)//第二次fork产生的子进程（第二个子进程）的父进程，其实就是第一次fork产生的子进程（第一个子进程）
			{
				exit(0);//第一个子进程结束，那么它的子进程（第二个子进程）将由init进程领养，init进程成为第二个子进程的父进程
			}
			//第二个子进程（就是我们前面说的B进程）可以做他想做的事情了
			................
		}
		if(waitpid(pid,NULL,0)!=pid)//获取第一个子进程的终止状态，不让它变成僵死进程
		printf("waitpid error\n");
		//父进程（就是我们前面说的A进程）也可以做他想做的事情了
		.........
		return 0;
	}
```

#### 二
父进程可以忽略 SIGCLD 软中断而不必要 wait()。可以这样做到(在支持它的系统上,比如Linux):　
```
	main()　　
	{　　
		signal(SIGCLD, SIG_IGN); /* now I don't have to wait()! */　　
		.......　　
		fork();　　
		fork();　　
		fork(); /* Rabbits, rabbits, rabbits! */　　
	｝
```

