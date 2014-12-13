---
layout: post
title: "c/c++函数扩展名"
date: 2013-03-26 17:03:00 +0800
comments: false
categories:
- 2013
- 2013~03
- language
- language~c
tags:
---
* 后缀为.c的，gcc把它当作是C程序，而g++当作是c++程序；
* 后缀为.cpp的，两者都会认为是c++程序
```
	int printf(char*, ...);
	int main()
	{
		printf("test\n");
		return 0;
	}
```
##### 一、
保存为.c 文件， 用gcc编译能通过，g++编译不能通过。  
g++会判定是不是你自己声明的函数，如果是，它会按照一种规则去重命名该函数。c++为了支持重载才这么做，而c没有重载。

##### 二、
保存为.cpp文件，用gcc、g++都编译不能通过
