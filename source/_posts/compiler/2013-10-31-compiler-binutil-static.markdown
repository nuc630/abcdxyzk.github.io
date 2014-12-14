---
layout: post
title: "binutils(含as、ld等)静态编译"
date: 2013-10-31 14:47:00 +0800
comments: false
categories:
- 2013
- 2013~10
- compiler
- compiler~make
tags:
---
#### 静态编译
```
./configure 后加   CFLAGS=-static --enable-static LDFLAGS=-static --disable-shared
./configure 后加   CFLAGS=-static LDFLAGS=-static
```
#### binutils-2.23.2 中gas、ld静态编译：
```
./configure
make
cd gas
make clean
make LDFLAGS=-all-static
```
或者
```
./configure
vim gas/Makefile
     搜 --mode=link，找到 LINK = $(LIBTOOL) --tag=CC ...
     在CC后面加个参数 -all-static
make
```
##### 原因：
他们链接的时候是通过 ./libtool 完成的，在libtool里有一行提示（./libtool --help没有显示这个提示)：
```
-all-static       do not do any dynamic linking at all
```
所以就是要libtool增加-all-static参数

