---
layout: post
title: "Makefile与Shell的问题"
date: 2013-06-21 18:28:00 +0800
comments: false
categories:
- 2013
- 2013~06
- compiler
- compiler~make
tags:
---
  大概只要知 道Makefile的人，都知道Makefile可以调用Shell脚本。但是在实际使用时，并不那么简单，一些模棱两可的地方可能会让你抓狂。你若不信，可以先看几个例子，想象一下这些这些例子会打印什么内容，记下你想象的结果，然后在计算机上运行这些例子，对照看一下。

示例一：
```
	if [ "$(BUILD)" = "debug" ]; then
		echo "build debug"; 
	else
		echo "build release";
	fi
	all:
		echo "done"
```
示例二：  
```
	all:
		@CC=arm-linux-gcc
		@echo $(CC)
```
示例三：  
```
	CC=arm-linux-gcc
	all:
		@echo $(CC)
```
示例四：  
```
	SUBDIR=src example
	all:
		@for subdir in $(SUBDIR);
		do
			echo "building " $(subdir);
		done
```
#### 说明：
1.Shell脚本在target里才有效，其它地方都被忽略掉了。所以示例一中，”build debug”之类的字符串根本打印不出来。示例一的正确写法是：
示例一：
```
	all:
		if [ "$(BUILD)" = "debug" ]; then
			echo "build debug";
		else
			echo "build release";
		fi
		echo "done"
```
2.make把每一行Shell脚本当作一个独立的单元，它们在单独的进程中运行。示例二中，两行Shell脚本在两个莫不相干的进程里运行，第一个进程把 CC设置为arm-linux-gcc，第二个进程是不知道的，所以打印的结果自然不是arm-linux-gcc了。示例二的正确写法是：  
示例二：
```
	all:
		@CC=arm-linux-gcc; echo $(CC)
	或者：
	all:
		@CC=arm-linux-gcc;
		echo $(CC)
```
3.make在调用Shell之前先进行预处理，即展开所有Makefile的变量和函数。这些变量和函数都以$开头。示例三中，Shell拿的脚本实际上是echo arm-linux-gcc，所以打印结果正确。

4.make预处理时，所有以$开头的，它都不会放过。要想引用Shell自己的变量，应该以$$开头。另外要注意，Shell自己的变量是不需要括号的。示例四的正确写法是：  
示例四：
```
	SUBDIR=src example
	all:
		@for subdir in $(SUBDIR);
		do
			echo "building " $$subdir;
		done
```

