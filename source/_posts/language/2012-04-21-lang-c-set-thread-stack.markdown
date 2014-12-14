---
layout: post
title: "设置线程的栈空间"
date: 2012-04-21 19:32:00 +0800
comments: false
categories:
- 2012
- 2012~04
- language
- language~c
tags:
- koj
---
#include <pthread.h>

```
	pthread_attr_t thread_attr;
	size_t stack_size;
	int status;

	status = pthread_attr_init (&thread_attr);
	if (status != 0)
		err_abort (status, "Create attr");

	status = pthread_attr_setdetachstate (&thread_attr, PTHREAD_CREATE_DETACHED);

	if (status != 0)
		err_abort (status, "Set detach");
	//通常出现的问题之一，下面的宏没有定义
	#ifdef _POSIX_THREAD_ATTR_STACKSIZE
		//得到当前的线程栈大小
		status = pthread_attr_getstacksize (&thread_attr, &stack_size);
		if (status != 0)
			err_abort (status, "Get stack size");
		printf ("Default stack size is %u; minimum is %u\n", stack_size, PTHREAD_STACK_MIN);

		//设置当前的线程的大小
		status = pthread_attr_setstacksize (&thread_attr, PTHREAD_STACK_MIN*1024);
		if (status != 0)
			err_abort (status, "Set stack size");

		//得到当前的线程栈的大小
		status = pthread_attr_getstacksize (&thread_attr, &stack_size);
		if (status != 0)
			err_abort (status, "Get stack size");
		printf ("Default stack size is %u; minimum is %u\n", stack_size, PTHREAD_STACK_MIN);
	#endif
```

