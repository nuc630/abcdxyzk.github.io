---
layout: post
title: "gcc include"
date: 2012-12-24 13:56:00 +0800
comments: false
categories:
- 2012
- 2012~12
- compiler
- compiler~base
tags:
---
本文介绍在linux中头文件的搜索路径，也就是说你通过include指定的头文件，linux下的gcc编译器它是怎么找到它的呢。在此之前，先了解一个基本概念。

  头文件是一种文本文件，使用文本编辑器将代码编写好之后，以扩展名.h保存就行了。头文件中一般放一些重复使用的代码，例如函数声明、变量声明、常数定 义、宏的定义等等。当使用＃include语句将头文件引用时，相当于将头文件中所有内容，复制到＃include处。#include有两种写法形式， 分别是：
```
	#include <> ： 直接到系统指定的某些目录中去找某些头文件。
	#include “” ： 先到源文件所在文件夹去找，然后再到系统指定的某些目录中去找某些头文件。
```
`#include`文件可能会带来一个问题就是重复应用，如a.h引用的一个函数是某种实现，而b.h引用的这个函数却是另外一种实现，这样在编译的时候将会出现错误。所以，为了避免因为重复引用而导致的编译错误，头文件常具有：
```
	#ifndef    LABEL
	#define    LABEL
		//代码部分
	#endif
```
的格式。其中LABEL为一个唯一的标号，命名规则跟变量的命名规则一样。
 
#### gcc寻找头文件的路径(按照1->2->3的顺序)
##### 1.
  在gcc编译源文件的时候，通过参数-I指定头文件的搜索路径，如果指定路径有多个路径时，则按照指定路径的顺序搜索头文件。命令形式如：“gcc -I  /path/where/theheadfile/in sourcefile.c“，这里源文件的路径可以是绝对路径，也可以是相对路径。eg：  
设当前路径为/root/test，include_test.c如果要包含头文件“include/include_test.h“，有两种方法：  
1) include_test.c中#include “include/include_test.h”或者#include "/root/test/include/include_test.h"，然后gcc include_test.c即可  
2) include_test.c中#include <include_test.h>或者#include <include_test.h>，然后gcc –I include include_test.c也可  
 
##### 2. 
通过查找gcc的环境变量C_INCLUDE_PATH/CPLUS_INCLUDE_PATH/OBJC_INCLUDE_PATH来搜索头文件位置。
 
##### 3. 再找内定目录搜索，分别是
```
	/usr/include
	/usr/local/include
	/usr/lib/gcc-lib/i386-linux/2.95.2/include
```
最后一行是gcc程序的库文件地址，各个用户的系统上可能不一样。  
gcc在默认情况下，都会指定到/usr/include文件夹寻找头文件。

gcc还有一个参数：-nostdinc，它使编译器不再系统缺省的头文件目录里面找头文件，一般和-I联合使用，明确限定头文件的位置。在编译驱动模块时，由于非凡的需求必须强制GCC不搜索系统默认路径，也就是不搜索/usr/include要用参数-nostdinc，还要自己用-I参数来指定内核 头文件路径，这个时候必须在Makefile中指定。

##### 4. 
当#include使用相对路径的时候，gcc最终会根据上面这些路径，来最终构建出头文件的位置。如#include <sys/types.h>就是包含文件/usr/include/sys/types.h

