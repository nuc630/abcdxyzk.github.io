---
layout: post
title: "__builtin_return_address获得程序运行栈"
date: 2013-11-20 18:34:00 +0800
comments: false
categories:
- 2013
- 2013~11
- language
- language~c
tags:
---
  gcc的编译特性使用`__builtin_return_address(level)`打印出一个函数的堆栈地址。其中 level代表是堆栈中第几层调用地址，`__builtin_return_address(0)`表示第一层调用地址，即当前函数，`__builtin_return_address(1)`表示第二层。如代码
```
	#include <stdio.h>

	void f()
	{
		printf("%p,%p" , __builtin_return_address(0), __builtin_return_address(1));
		//printk("Caller is %pS\n", __builtin_return_address(0));
	}

	void g()
	{
		f();
	}
	int main()
	{
		g();
	}
```
分别打印出函数f()和g() 的函数地址，我们通过objdump 出来的文件去查找打印出来的函数地址，这样就能看到调用的函数名了。

