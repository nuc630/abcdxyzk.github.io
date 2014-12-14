---
layout: post
title: "grub"
date: 2014-10-24 15:53:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~base
tags:
---
在命令行状态，可以根据需要加载或移除相应模块，也可用来启动在菜单没有显现的的系统。
比如，在第一硬盘的第一分区上装有windows xp系统，但在菜单上没显示出来，我们可以命令行状态下输入命令启动：
```
	grub>set root=(hd0,1)
	grub>chainloader +1
	grub>boot
```
又比如启动第二硬盘第一逻辑分区上的ubuntu系统：
```
	grub>set root=(hd1,5)
	grub>linux /boot/vmlinuz-xxx-xxx root=/dev/sdb5
	grub>initrd /boot/initrd.img-xxx-xxx
	grub>boot
```
其中内核vmlinuz和initrd.img的版本号可用按Tab键自动查看。
