---
layout: post
title: "LD_PRELOAD环境变量"
date: 2013-10-22 16:08:00 +0800
comments: false
categories:
- 2013
- 2013~10
- system
- system~tools
tags:
- LD_PRELOAD
---
在Linux的动态链接库的世界中，LD_PRELOAD就是这样一个环境变量，它可以影响程序的运行时的链接（Runtime linker），它允许你定义在程序运行前优先加载的动态链接库。这个功能主要就是用来有选择性的载入不同动态链接库中的相同函数。通过这个环境变量，我们可以在主程序和其动态链接库的中间加载别的动态链接库，甚至覆盖正常的函数库。一方面，我们可以以此功能来使用自己的或是更好的函数（无需别人的源码），而另一方面，我们也可以以向别人的程序注入恶意程序，从而达到那不可告人的罪恶的目的。

我们知道，Linux的用的都是glibc，有一个叫libc.so.6的文件，这是几乎所有Linux下命令的动态链接中，其中有标准C的各种函数。对于GCC而言，默认情况下，所编译的程序中对标准C函数的链接，都是通过动态链接方式来链接libc.so.6这个函数库的。

OK。还是让我用一个例子来看一下用LD_PRELOAD来hack别人的程序。
##### 示例一
我们写下面一段例程：
```
	/* 文件名：verifypasswd.c */
	/* 这是一段判断用户口令的程序，其中使用到了标准C函数strcmp*/
	#include <stdio.h>
	#include <string.h>
	int main(int argc, char **argv)
	{
		char passwd[] = "password";
		if (argc < 2) {
			printf("usage: %s <password>/n", argv[0]);
			return 1;
		}
		if (!strcmp(passwd, argv[1])) {
			printf("Correct Password!/n");
			return 1;
		}
		printf("Invalid Password!/n");
		return 0;
	}
```
在上面这段程序中，我们使用了strcmp函数来判断两个字符串是否相等。下面，我们使用一个动态函数库来重载strcmp函数：
```
	/* 文件名：hack.c */
	#include <stdio.h>

	#include <string.h>
	int strcmp(const char *s1, const char *s2)
	{
		printf("hack function invoked. s1=<%s> s2=<%s>/n", s1, s2);
		/* 永远返回0，表示两个字符串相等 */
		return 0;
	}
```
编译程序：
```
$ gcc -o verifypasswd verifypasswd.c
$ gcc -shared -o hack.so hack.c
```
测试一下程序：（得到正确结果）
```
$ ./verifypasswd asdf
Invalid Password!
``` 
##### 设置LD_PRELOAD变量：
（使我们重写过的strcmp函数的hack.so成为优先载入链接库）
```
$ export LD_PRELOAD="./hack.so"
``` 
再次运行程序：
```
$ ./verifypasswd  asdf
hack function invoked. s1=<password> s2=<asdf>
Correct Password!
```
我们可以看到，  
1）我们的hack.so中的strcmp被调用了。  
2）主程序中运行结果被影响了。  
如果这是一个系统登录程序，那么这也就意味着我们用任意口令都可以进入系统了。

