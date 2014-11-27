---
layout: post
title: "Makefile预定义变量、自动变量"
date: 2013-06-03 15:22:00 +0800
comments: false
categories:
- 2013
- 2013~06
- compiler
- compiler~make
tags:
---
#### Makefile中常见自动变量
```
	命令格式		含     义
	$*		不包含扩展名的目标文件名称
	$+		所有的依赖文件，以空格分开，并以出现的先后为序，可能包含重复的依赖文件
	$<		第一个依赖文件的名称
	$?		所有时间戳比目标文件晚的依赖文件，并以空格分开 
	$@		目标文件的完整名称
	$^		所有不重复的依赖文件，以空格分开
	$%		如果目标是归档成员，则该变量表示目标的归档成员名称
```
#### Makefile中常见预定义变量
```
	命 令 格 式	含     义
	AR				库文件维护程序的名称，默认值为ar
	AS				汇编程序的名称，默认值为as
	CC				C编译器的名称，默认值为cc
	CPP				C预编译器的名称，默认值为$(CC) –E
	CXX				C++编译器的名称，默认值为g++
	FC				FORTRAN编译器的名称，默认值为f77
	RM				文件删除程序的名称，默认值为rm –f
	ARFLAGS			库文件维护程序的选项，无默认值
	ASFLAGS			汇编程序的选项，无默认值
	CFLAGS			C编译器的选项，无默认值
	CPPFLAGS		C预编译的选项，无默认值
	CXXFLAGS		C++编译器的选项，无默认值
	FFLAGS			FORTRAN编译器的选项，无默认值
```

##### 在Makefile中我们可以通过宏定义来控制源程序的编译。
只要在Makefile中的CFLAGS中通过选项-D来指定你于定义的宏即可。  
如:  
CFLAGS += -D __KK__  
或  
CFLAGS += -D __KK__=__XX__

