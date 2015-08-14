---
layout: post
title: "共享内存"
date: 2015-02-09 15:23:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~mm
tags:
---
http://blog.csdn.net/wc7620awjh/article/details/7721331

  共享内存是被多个进程共享的一部分物理内存。共享内存是进程间共享数据的一种最快的方法，一个进程向共享内存区域写入了数据，共享这个内存区域的所有进程就可以立刻看到其中的内容。原理图如下：

![](/images/kernel/2015-02-09-1.jpg)

共享内存的实现分为两个步骤：  
一、 创建共享内存，使用shmget函数。
二、 映射共享内存，将这段创建的共享内存映射到具体的进程空间去，使用shmat函数。

#### 创建共享内存
```
	int shmget(key_t key ,int size,int shmflg)
```
key标识共享内存的键值：0/IPC_PRIVATE。当key的取值为IPC_PRIVATE,则函数shmget将创建一块新的共享内存；如果key的取值为0，而参数中又设置了IPC_PRIVATE这个标志，则同样会创建一块新的共享内存。

返回值：如果成功，返回共享内存表示符，如果失败，返回-1。

#### 映射共享内存
```
	int shmat(int shmid,char *shmaddr，int flag)
```
参数：  
shmid:shmget函数返回的共享存储标识符  
flag：决定以什么样的方式来确定映射的地址(通常为0)

返回值：  
如果成功，则返回共享内存映射到进程中的地址；如果失败，则返回-1。  
共享内存解除映射

当一个进程不再需要共享内存时，需要把它从进程地址空间中多里。
```
int shmdt(char *shmaddr)
```
贡献内存实例如下：  
实验要求：创建两个进程，在A进程中创建一个共享内存，并向其写入数据，通过B进程从共享内存中读取数据。

##### chm_com.h函数
```
	#define TEXT_SZ 2048  

	struct shared_use_st  
	{  
		int written_by_you;  
		char some_text[TEXT_SZ];  
	};  
```

##### 读取进程：
```
	#include <unistd.h>  
	#include <stdlib.h>  
	#include <stdio.h>  
	#include <string.h>  
	#include <sys/types.h>  
	#include <sys/ipc.h>  
	#include <sys/shm.h>  
	#include "shm_com.h"  
	  
	/* 
	 * 程序入口 
	 * */  
	int main(void)  
	{  
		int running=1;  
		void *shared_memory=(void *)0;  
		struct shared_use_st *shared_stuff;  
		int shmid;  
		/*创建共享内存*/  
		shmid=shmget((key_t)1234,sizeof(struct shared_use_st),0666|IPC_CREAT);  
		if(shmid==-1)  
		{  
			fprintf(stderr,"shmget failed\n");  
			exit(EXIT_FAILURE);  
		}  
	  
		/*映射共享内存*/  
		shared_memory=shmat(shmid,(void *)0,0);  
		if(shared_memory==(void *)-1)  
		{  
			fprintf(stderr,"shmat failed\n");  
			exit(EXIT_FAILURE);  
		}  
		printf("Memory attached at %X\n",(int)shared_memory);  
	  
		/*让结构体指针指向这块共享内存*/  
		shared_stuff=(struct shared_use_st *)shared_memory;  
	  
		/*控制读写顺序*/  
		shared_stuff->written_by_you=0;  
		/*循环的从共享内存中读数据，直到读到“end”为止*/  
		while(running)  
		{  
		   if(shared_stuff->written_by_you)  
		   {  
			   printf("You wrote:%s",shared_stuff->some_text);  
			   sleep(1);  //读进程睡一秒，同时会导致写进程睡一秒，这样做到读了之后再写  
			   shared_stuff->written_by_you=0;  
			   if(strncmp(shared_stuff->some_text,"end",3)==0)  
			   {  
				   running=0; //结束循环  
			   }  
		   }  
		}  
		/*删除共享内存*/  
		if(shmdt(shared_memory)==-1)  
		{  
			fprintf(stderr,"shmdt failed\n");  
			exit(EXIT_FAILURE);  
		}  
		   exit(EXIT_SUCCESS);  
	}  
```

##### 写入进程：
```
	#include <unistd.h>  
	#include <stdlib.h>  
	#include <stdio.h>  
	#include <string.h>  
	#include <sys/types.h>  
	#include <sys/ipc.h>  
	#include <sys/shm.h>  
	#include "shm_com.h"  
	  
	/* 
	 * 程序入口 
	 * */  
	int main(void)  
	{  
		int running=1;  
		void *shared_memory=(void *)0;  
		struct shared_use_st *shared_stuff;  
		char buffer[BUFSIZ];  
		int shmid;  
		/*创建共享内存*/  
		shmid=shmget((key_t)1234,sizeof(struct shared_use_st),0666|IPC_CREAT);  
		if(shmid==-1)  
		{  
			fprintf(stderr,"shmget failed\n");  
			exit(EXIT_FAILURE);  
		}  
	  
		/*映射共享内存*/  
		shared_memory=shmat(shmid,(void *)0,0);  
		if(shared_memory==(void *)-1)  
		{  
			fprintf(stderr,"shmat failed\n");  
			exit(EXIT_FAILURE);  
		}  
		printf("Memory attached at %X\n",(int)shared_memory);  
	  
		/*让结构体指针指向这块共享内存*/  
		shared_stuff=(struct shared_use_st *)shared_memory;  
		/*循环的向共享内存中写数据，直到写入的为“end”为止*/  
		while(running)  
		{  
			while(shared_stuff->written_by_you==1)  
			{  
				sleep(1);//等到读进程读完之后再写  
				printf("waiting for client...\n");  
			}  
			printf("Ener some text:");  
			fgets(buffer,BUFSIZ,stdin);  
			strncpy(shared_stuff->some_text,buffer,TEXT_SZ);  
			shared_stuff->written_by_you=1;  
			if(strncmp(buffer,"end",3)==0)  
			{  
				running=0;  //结束循环  
			}  
		}  
		/*删除共享内存*/  
		if(shmdt(shared_memory)==-1)  
		{  
			fprintf(stderr,"shmdt failed\n");  
			exit(EXIT_FAILURE);  
		}  
		exit(EXIT_SUCCESS);  
	}  
```

##### 运行
  在一个终端中运行shm1，在另一个终端中运行shm2.当shm1运行起来之后，由于共享内存中没有数据可读，会处于等待状态
```
	[root@localhost 2-4-4]# ./shm1
	Memory attached at B7F9A000

	/***阻塞***/
```

再向shm2运行的终端输入字符串
```
	[root@localhost 2-4-4]# ./shm2
	Memory attached at B7FD8000
	Enter some text：Impossible is nothing
	waiting for client。。。
	waiting for client。。。
	Enter some text：Anything is possible
	waiting for client。。。
	Ener some text：end
	[root@localhost 2-4-4]#
```

shm1能够逐个从共享内存中巴他们读出来，知道双方晕倒字符串"end"后，两个程序都退出。
```
	[root@localhost 2-4-4]# ./shm1
	Memory attached at B7F9A000
	You write：Impossible is nothing
	You write：Anything is possible
	You write：end
	[root@localhost 2-4-4]#
```
以上运行过程中，红色表示在终端1中运行的结果，蓝色表示在终端2里面运行的结果。

