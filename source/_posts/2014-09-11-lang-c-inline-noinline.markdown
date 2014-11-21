---
layout: post
title: "强制内联和强制不内联"
date: 2014-09-11 09:34:00 +0800
comments: true
categories:
- 2014
- 2014~09
- language
- language~c
tags:
- c
---
#### 1.强制不内联
一个函数，如果代码量比较少的话，用 -O3优化开关的话，gcc有可能将这个函数强制内联(inline)即使，你在函数前没有写inline助记符。  
如果是一个手写汇编的函数，那样的话很有可能破坏参数。gcc里有强制不内联的，用法如下
```
	void foo() __attribute__((noinline));
```
但是有的gcc可能会忽略 noinline。  
那么你可以将你实现的这个函数写到调用函数之后，就不会被inline了。这是因为编译器gcc只内联当前函数之前可见(实现代码在前)的函数。

#### 2.优化时无法识别inline函数中的ASM汇编
当GCC尝试内联一个函数时，如果该函数中存在内联汇编，则该汇编语句块可能被丢弃；
```
	__inline__ __attribute__((always_inline))int Increment(int volatile *add, int inc)
	{
	    int res;
	    __asm__
	    (
	    "lock \n\t"
	    "xaddl %0,(%1)\n\t"
	    :"=r"(res)
	    :"r"(add),"0"(inc)
	    :"memory"
	    );
	    return res;
	}
```
