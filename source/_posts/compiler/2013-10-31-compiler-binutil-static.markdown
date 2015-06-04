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
binutils下载 http://ftp.gnu.org/gnu/binutils/

#### binutils静态编译：
```
	./configure
	make LDFLAGS=-all-static
```

##### 原因：
他们链接的时候是通过 ./libtool 完成的，在libtool里有一行提示（./libtool --help没有显示这个提示)：
```
	-all-static       do not do any dynamic linking at all
```
所以就是要libtool增加-all-static参数


#### 比较通用的静态编译方法
```
	./configure 后加   CFLAGS=-static --enable-static LDFLAGS=-static --disable-shared
	或
	./configure 后加   CFLAGS=-static LDFLAGS=-static
	或
	make CFLAGS=-static LDFLAGS=-static
```

