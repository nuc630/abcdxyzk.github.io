---
layout: post
title: "offsetof宏 container_of宏"
date: 2014-09-15 15:57:00 +0800
comments: false
categories:
- 2014
- 2014~09
- kernel
- kernel~base
tags:
---
Linux内核中，用两个非常巧妙地宏实现了，一个是offsetof宏，另一个是container_of宏，下面讲解一下这两个宏。
#### 1.  offsetof宏
#####【定义】：
```
#define offsetof(TYPE, MEMBER) ((size_t) & ((TYPE *)0)->MEMBER )
```
#####【功能】： 获得一个结构体变量成员在此结构体中的偏移量。
#####【例子】：
``` 
	struct A 
		{ 
		int x ; 
		int y; 
		int z; 
	}; 

	void main() 
	{ 
		printf("the offset of z is %d",offsetof( struct A, z )  ); 
	} 
```
// 输出结果为 8 
#####【分析】：
该宏，TYPE为结构体类型，MEMBER 为结构体内的变量名。  
(TYPE *)0) 是欺骗编译器说有一个指向结构TYPE 的指针，其地址值0   
(TYPE *)0)->MEMBER 是要取得结构体TYPE中成员变量MEMBER的地址. 因为基址为0，所以，这时MEMBER的地址当然就是MEMBER在TYPE中的偏移了。
#### 2. container_of宏（即实现了题目中的功能）
#####【定义】：
```
#define container_of(ptr, type, member)   ({const typeof( ((type *)0)->member ) *__mptr = (ptr); (type *)( (char *)__mptr - offsetof(type,member) );})
```
#####【功能】：
从结构体（type）某成员变量（member）指针（ptr）来求出该结构体（type）的首指针。
#####【例子】：
```
	struct A 
	{ 
		int x ; 
		int y; 
		int z; 
	}; 
	 
	struct A myTest; 
	 
	int *pz = &myTest.z; 
	 
	struct A* getHeaderPtr( int *pz ) 
	{ 
		return container_of( pz , struct A, z ); 
	} 
```
#####【分析】：
（1） typeof( ( (type *)0)->member )为取出member成员的变量类型。  
（2） 定义__mptr指针ptr为指向该成员变量的指针(即指向ptr所指向的变量处)  
（3） (char *)__mptr - offsetof(type,member)) 用该成员变量的实际地址减去该变量在结构体中的偏移，来求出结构体起始地址。  
（4） ({ })这个扩展返回程序块中最后一个表达式的值。

