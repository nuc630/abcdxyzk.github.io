---
layout: post
title: "test指令"
date: 2015-07-21 15:14:00 +0800
comments: false
categories:
- 2015
- 2015~07
- assembly
- assembly~base
tags:
---

TEST对两个参数(目标，源)执行AND逻辑操作,并根据结果设置标志寄存器,结果本身不会保存。TEST AX,BX 与 AND AX,BX 命令有相同效果

语法: TEST R/M, R/M/DATA

影响标志: C,O,P,Z,S(其中C与O两个标志会被设为0) 

结果: 执行AND逻辑操作结果为0则设置ZF零标志为1


TEST的一个非常普遍的用法是用来测试一方寄存器是否为空:
```
	TEST ECX, ECX
	JZ SOMEWHERE
```
如果ECX为零,设置ZF零标志为1,JZ跳转

