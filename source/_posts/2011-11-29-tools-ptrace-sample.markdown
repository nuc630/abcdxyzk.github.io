---
layout: post
title: "一个简单的 ptrace 例子"
date: 2011-11-29 20:16:00 +0800
comments: false
categories:
- 2011
- 2011~11
- language
- language~c
tags:
- koj
- judge
---
```
	// test.cpp

	#include <stdio.h>

	int main()
	{
		printf("---------- test 1 ----------\n");
		printf("---------- test 2 ----------\n");
		printf("---------- test 3 ----------\n");
		return 0;
	}
```
编译 g++ test.cpp -o test --static
```
	// ptrace.cpp

	#include <stdio.h>
	#include <stdlib.h>
	#include <sys/ptrace.h>
	#include <sys/types.h>
	#include <sys/wait.h>
	#include <sys/reg.h>
	#include <unistd.h>

	int main()
	{
		pid_t pid;
		int orig_eax, eax, ebx, ecx, edx;
	   
		pid = fork();
		if(pid == 0)
		{
			ptrace(PTRACE_TRACEME, 0, NULL, NULL);
			printf("execve = %d\n", execve("./test", NULL, NULL));
			exit(0);
		}
		while(1)
		{
			int status;
			wait(&status);
			if(WIFEXITED(status)) break;

			orig_eax = ptrace(PTRACE_PEEKUSER, pid, ORIG_EAX<<2, NULL);
			eax = ptrace(PTRACE_PEEKUSER, pid, EAX<<2, NULL);
			ebx = ptrace(PTRACE_PEEKUSER, pid, EBX<<2, NULL);
	       
			printf("ORIG_EAX = %d,        EAX = %d,        EBX = %d\n", orig_eax, eax, ebx);

			ptrace(PTRACE_SYSCALL, pid, NULL, NULL);
		}
		return 0;
	}
```
编译 `g++ ptrace.cpp -o ptrace --static`  
测试 `./ptrace` 输出
```
ORIG_EAX = 11,        EAX = 0,        EBX = 0
ORIG_EAX = 122,        EAX = -38,        EBX = -1074643290
ORIG_EAX = 122,        EAX = 0,        EBX = -1074643290
ORIG_EAX = 45,        EAX = -38,        EBX = 0
ORIG_EAX = 45,        EAX = 161513472,        EBX = 0
ORIG_EAX = 45,        EAX = -38,        EBX = 161516752
ORIG_EAX = 45,        EAX = 161516752,        EBX = 161516752
ORIG_EAX = 243,        EAX = -38,        EBX = -1074642896
ORIG_EAX = 243,        EAX = 0,        EBX = -1074642896
ORIG_EAX = 45,        EAX = -38,        EBX = 161651920
ORIG_EAX = 45,        EAX = 161651920,        EBX = 161651920
ORIG_EAX = 45,        EAX = -38,        EBX = 161652736
ORIG_EAX = 45,        EAX = 161652736,        EBX = 161652736
ORIG_EAX = 197,        EAX = -38,        EBX = 1
ORIG_EAX = 197,        EAX = 0,        EBX = 1
ORIG_EAX = 192,        EAX = -38,        EBX = 0
ORIG_EAX = 192,        EAX = -1217093632,        EBX = 0
ORIG_EAX = 4,        EAX = -38,        EBX = 1
---------- test 1 ----------
ORIG_EAX = 4,        EAX = 29,        EBX = 1
ORIG_EAX = 4,        EAX = -38,        EBX = 1
---------- test 2 ----------
ORIG_EAX = 4,        EAX = 29,        EBX = 1
ORIG_EAX = 4,        EAX = -38,        EBX = 1
---------- test 3 ----------
ORIG_EAX = 4,        EAX = 29,        EBX = 1
ORIG_EAX = 252,        EAX = -38,        EBX = 0
```
内核 Linux 2.6.32-35-generic

ubuntu 10.04
linux 系统调用号 /usr/include/asm/unistd_32.h  
linux 系统EAX等值 /usr/include/sys/reg.h  

