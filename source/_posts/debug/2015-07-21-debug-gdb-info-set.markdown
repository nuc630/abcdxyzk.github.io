---
layout: post
title: "gdb 修改寄存器/变量"
date: 2015-07-21 15:34:00 +0800
comments: false
categories:
- 2015
- 2015~07
- debug
- debug~gdb
tags:
---

```
	# 查看所有寄存器
	(gdb) info register  # 可以简写成 i r

	# 查看单个寄存器
	(gdb) i r rax

	# 修改寄存器
	(gdb) set $rax=3



	# 查看变量
	(gdb) i local

	# 修改变量
	(gdb) set var b=4
```
