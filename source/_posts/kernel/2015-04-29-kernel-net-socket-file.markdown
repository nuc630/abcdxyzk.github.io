---
layout: post
title: "文件socket"
date: 2015-04-29 17:32:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/y_23k_bug/article/details/9993555

#### 1. 建立socket
```
	#include<sys/socket.h>

	int socket(
		int domain,	   //地址族的类型AF_UNIX (绑定在本地) AF_INET（绑定在网卡）
		int type,      //支持的数据格式：流SOCK_STREAM/报文SOCK_DGRAM
		int protocol); //支持的协议,建议为0

	返回值：
		成功返回文件描述符号。
		失败返回-1;
```

#### 2.绑定在地址上(文件目录地址)URL(Universe ResourceLocation)
```
	协议://路径/文件名
	file:///usr/bin/ls      普通文件
	http://192.168.0.72/index.php
	struct sockaddr;  地址结构体
```
```
	#include<linux/un.h>

	struct sockaddr_un;   un=unix（绑定unix本地）

	struct sockaddr_un {
		sa_family_t   sun_family; /*AF_UNIX*/
		char sun_path[UNIX_PATH_MAX];
	};
```
```
	struct sockaddr_in;   in=internet（绑定网卡）
	int bind(int fd,           //socket描述符号
		struct sockaddr *addr, //绑定地址
		socklen_tsize);        //地址长度

	返回值：
		0成功
		-1失败
```


#### 样例
##### server.c
```
	#include<sys/socket.h>
	#include<stdio.h>
	#include<stdlib.h>
	#include<string.h>
	#include<unistd.h>
	#include<linux/un.h>
	 
	int main()
	{
		int fd; 
		int r;
		char buf[100];
		//1.建立socket
		fd = socket(AF_UNIX, SOCK_DGRAM, 0);  //AF_FILE 等同//AF_UNIX
		if (fd == -1) {
			printf("socket error:%m\n");
			exit(-1);
		}   
	 
		//2.构造本地文件地址
		struct sockaddr_un addr = {0};
		addr.sun_family = AF_UNIX; //必须跟socket的地址族一致
		memcpy(addr.sun_path, "my.sock", strlen("my.sock"));
		
		//3.把socket绑定在地址上
		r = bind(fd, (struct sockaddr *)&addr, sizeof(addr));
		if (r == -1) {
			printf("bind error:%m\n");
			exit(-1);
		}   
	 
		//4.接收数据
		bzero(buf , sizeof(buf));
		r = read(fd, buf, sizeof(buf));
		buf[r] = 0;
		printf("%s\n", buf);
	 
		//5.关闭
		close(fd);
	 
		//6.删除socket文件
		unlink("my.sock");
	 
		//socket文件不会自动删除，需要在程序结尾去删除该文件，否则，再次运行//A程序出错
		return 0;
	}
```

##### client.c
```
	#include<stdio.h>
	#include<stdlib.h>
	#include<sys/socket.h>
	#include<linux/un.h>
	#include<string.h>
	#include<unistd.h>
	 
	int main()
	{
		int fd; 
		int r;
		struct sockaddr_un addr = {0};
		//1.建立socket
		fd = socket(AF_UNIX, SOCK_DGRAM, 0); 
	 
		//2.连接到指定的地址
		addr.sun_family = AF_UNIX;
		memcpy(addr.sun_path, "my.sock", strlen("my.sock"));
		r = connect(fd, (struct sockaddr*)&addr, sizeof(addr));
	 
		//3.发送数据
		write(fd, "hello!", strlen("hello!"));
	 
		//4.关闭
		close(fd);
		return 0;
	}
```

