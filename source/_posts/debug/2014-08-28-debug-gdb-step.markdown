---
layout: post
title: "gdb 没有debug信息step单步调试"
date: 2014-08-28 16:21:00 +0800
comments: false
categories:
- 2014
- 2014~08
- debug
- debug~gdb
tags:
- gdb
---
```
step <count>
```
单步跟踪，如果有函数调用，他会进入该函数。进入函数的前提是，此函数被编译有 debug信息。很像 VC等工具中的 step in。后面可以加 count也可以不加，不加表示一条条地执行，加表示执行后面的 count条指令，然后再停住。
```
next <count>
```
同样单步跟踪，如果有函数调用，他不会进入该函数。很像 VC等工具中的 step over。后面可以加 count也可以不加，不加表示一条条地执行，加表示执行后面的 count条指令，然后再停住。
```
	set step-mode [on/off]
	set step-mode on
	打开 step-mode模式，于是，在进行单步跟踪时，程序不会因为没有 debug信息而不停住。这个参数有很利于查看机器码。

	set step-mod off
	关闭 step-mode模式。
```
