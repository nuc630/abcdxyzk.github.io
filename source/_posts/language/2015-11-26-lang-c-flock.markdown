---
layout: post
title: "c 文件锁flock"
date: 2015-11-26 11:35:00 +0800
comments: false
categories:
- 2015
- 2015~11
- lang
- lang~c
tags:
---
http://blog.csdn.net/lin_fs/article/details/7804494

头文件  #include<sys/file.h>

定义函数  int flock(int fd, int operation);

函数说明  flock()会依参数operation所指定的方式对参数fd所指的文件做各种锁定或解除锁定的动作。此函数只能锁定整个文件，无法锁定文件的某一区域。

参数  operation有下列四种情况:  
  LOCK_SH 建立共享锁定。多个进程可同时对同一个文件作共享锁定。  
  LOCK_EX 建立互斥锁定。一个文件同时只有一个互斥锁定。  
  LOCK_UN 解除文件锁定状态。  
  LOCK_NB 无法建立锁定时，此操作可不被阻断，马上返回进程。通常与LOCK_SH或LOCK_EX 做OR(|)组合。  
  单一文件无法同时建立共享锁定和互斥锁定，而当使用dup()或fork()时文件描述词不会继承此种锁定。  

返回值  返回0表示成功，若有错误则返回-1，错误代码存于errno。


flock只要在打开文件后，需要对文件读写之前flock一下就可以了，用完之后再flock一下，前面加锁，后面解锁。其实确实是这么简单，但是前段时间用的时候发现点问题，问题描述如下：

  一个进程去打开文件，输入一个整数，然后上一把写锁（LOCK＿EX），再输入一个整数将解锁（LOCK＿UN），另一个进程打开同样一个文件，直接向文件中写数据，发现锁不起作用，能正常写入（我此时用的是超级用户）。google了一大圈发现flock不提供锁检查，也就是说在用flock之前需要用户自己去检查一下是否已经上了锁，说明白点就是读写文件之前用一下flock检查一下文件有没有上锁，如果上锁了flock将会阻塞在那里(An attempt to lock the file using one of these file descriptors may be denied by a lock that the calling process has already placed via another descriptor )，除非用了LOCK_NB。一个完整的用于测试的事例代码如下所示：

```
	//lockfile.c

	#include <stdio.h>
	#include <unistd.h>
	#include <sys/types.h>
	#include <sys/stat.h>
	#include <fcntl.h>
	#include <errno.h>

	int main()
	{
		int fd,i;
		char path[] = "/home/taoyong/test.txt";
		extern int errno;
		fd = open(path,O_WRONLY|O_CREAT);
		if(fd != -1)
		{
			printf("open file %s ./n", path);
			printf("please input a number to lock the file./n");
			scanf("%d", &i);
			if (flock(fd, LOCK_EX) == 0)
			{
				printf("the file was locked./n");
			}
			else
			{
				printf("the file was not locked./n");
			}
			printf("please input a number to unlock the file./n");
			scanf("%d", &i);
			if (flock(fd, LOCK_UN)==0)
			{
				printf("the file was unlocked./n");
			}
			else
			{
				printf("the file was not unlocked./n");
			}
			close(fd);
		}
		else
		{
			printf("cannot open file %s/n", path);
			printf("errno:%d/n", errno);
			printf("errMsg:%s", strerror(errno));
		}
		return 0;
	}
```

```
	//testprocess.c

	#include <stdio.h>
	#include <unistd.h>
	#include <sys/types.h>
	#include <sys/stat.h>
	#include <fcntl.h>
	#include <errno.h>
	#include <sys/file.h>

	int main()
	{
		int fd,i;
		char path[] = "/home/taoyong/test.txt";
		char s[] = "writing.../nwriting....../n";
		extern int errno;
		fd = open(path, O_WRONLY|O_CREAT|O_APPEND);
		if(fd!=-1)
		{
			printf("open file %s ./n",path);

			if (flock(fd,LOCK_EX|LOCK_NB) == 0)
			{
			   	printf("the file was locked by the process./n");   
				if (-1 != write(fd,s,sizeof(s)))
				{
				   	printf("write %s to the file %s/n", s, path);
				}
				else
				{
				   	printf("cannot write the file %s/n", path);
				   	printf("errno:%d/n", errno);
				   	printf("errMsg:%s/n", strerror(errno));
				}       
				   
			}
			else
			{
			   	printf("the file was locked by other process.Can't write.../n");
				printf("errno:%d:", errno);
			}
			close(fd);
		}
		else
		{
		 	printf("cannot open file %s/n", path);
		   	printf("errno:%d/n", errno);
		   	printf("errMsg:%s", strerror(errno));
		}
		return 0;
	}
```

