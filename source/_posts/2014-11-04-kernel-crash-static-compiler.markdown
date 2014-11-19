---
layout: post
title: "静态编译crash + xbt + bt -H"
date: 2014-11-04 18:23:00 +0800
comments: true
categories:
- 2014
- 2014~11
- kernel
- kernel~kdump、crash
tags: 
- kernel
- crash
---
##### 要在centos6上编译，为了能在centos5用，用静态编译
##### 有两个显示函数参数的patch，但是不一定能起作用  
##### patch1:
[https://github.com/jhammond/xbt](https://github.com/jhammond/xbt)
[https://www.redhat.com/archives/crash-utility/2013-September/msg00010.html](https://www.redhat.com/archives/crash-utility/2013-September/msg00010.html)
##### patch2:
[https://github.com/hziSot/crash-stack-parser](https://github.com/hziSot/crash-stack-parser)
[https://github.com/hziSot/crash-stack-parser/blob/master/crash-parse-stack-7.0.1.patch](https://github.com/hziSot/crash-stack-parser/blob/master/crash-parse-stack-7.0.1.patch)

#### 一、依赖包：
yum install bison zlib zlib-static glibc-static elfutils-devel elfutils-devel-static elfutils-libelf-devel-static ncurses ncurses-static crash-devel

#### 二、patch1: xbt 显示参数
patch: https://github.com/hziSot/crash-stack-parser  
make CFLAGS+=--static LDFLAGS+=--static

#### 三、patch2: bt -H 显示参数
```
	依赖：有些没有静态包，要自己编译安装：
	liblzma.a: http://tukaani.org/xz/xz-5.0.7.tar.bz2
	libbz2.a:  http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
	下载代码：git clone https://github.com/jhammond/xbt.git xbt.git
	把xbt.git/xbt_crash.c中函数xbt_func前的static删了
	把xbt.git/xbt_crash.c中函数xmod_init的register_extension删了
	把 xbt 命令加到global_data.c        函数x86_64_exception_frame已经在其他库中定义了，所以要换个名字
	编译xbt代码：make   ==  rm -rf *.so
	把 xbt.git/xbt_crash.o  xbt.git/xbt_dwarf.o  xbt.git/xbt_dwfl.o  xbt.git/xbt_eval.o  xbt.git/xbt_frame_print.o 加到 Makefile 的 OBJECT_FILES= 中
	make CFLAGS+=--static LDFLAGS+="--static -lc  -lm -ldl -ldw -lebl -lelf -lbz2 -llzma"


	注意:-lelf -lebl要放在-ldw后面。
```
