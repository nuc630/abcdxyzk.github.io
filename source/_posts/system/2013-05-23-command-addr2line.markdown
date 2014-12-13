---
layout: post
title: "addr2line命令"
date: 2013-05-23 18:14:00 +0800
comments: false
categories:
- 2013
- 2013~05
- system
- system~command
tags:
---
这是一个示例程序，func函数返回参数a除以参数b的结果。这里使用0作为除数，结果就是程序因为除以0导致错误，直接中断了。
```
	#include <stdio.h>
	int func(int a, int b)
	{
		return a / b;
	}

	int main()
	{
		int x = 10;
		int y = 0;
		printf("%d / %d = %d\n", x, y, func(x, y));
		return 0;
	}
```
```
$ gcc -o test1 -g test1.c  
```
编译程序，test1.c是程序文件名。执行程序，结果程序异常中断。查看系统dmesg信息，发现系统日志的错误信息：
```
[54106.016179] test1[8352] trap divide error ip:400506 sp:7fff2add87e0 error:0 in test1[400000+1000]
```
这条信息里的ip字段后面的数字就是test1程序出错时所程序执行的位置。使用addr2line就可以将400506转换成出错程序的位置：
```
$ addr2line -e test1 400506  
/home/hanfoo/code/test/addr2line/test1.c:5
```
这里的test1.c:5指的就是test1.c的第5行
```
	return a / b;  
```
也正是这里出现的错误。addr2line帮助我们解决了问题。

  addr2line如何找到的这一行呢。在可执行程序中都包含有调试信息， 其中很重要的一份数据就是程序源程序的行号和编译后的机器代码之间的对应关系Line Number Table。DWARF格式的Line  Number Table是一种高度压缩的数据，存储的是表格前后两行的差值，在解析调试信息时，需要按照规则在内存里重建Line Number  Table才能使用。

Line Number Table存储在可执行程序的.debug_line域，使用命令
```
$ readelf -w test1
```
可以输出DWARF的调试信息，其中有两行
```
Special opcode 146: advance Address by 10 to 0x4004fe and Line by 1 to 5  
Special opcode 160: advance Address by 11 to 0x400509 and Line by 1 to 6  
```
这里说明机器二进制编码的0x4004fe位置开始，对应于源码中的第5行，0x400509开始就对应与源码的第6行了，所以400506这个地址对应的是源码第5行位置。

addr2line通过分析调试信息中的Line Number Table自动就能把源码中的出错位置找出来.

