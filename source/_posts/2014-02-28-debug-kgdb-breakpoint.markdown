---
layout: post
title: "KGDB--Cannot insert breakpoint"
date: 2014-02-28 17:55:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~kgdb
tags:
---
#### 原因：
内核编译选项CONFIG_DEBUG_RODATA，会对kernel text做write protect。 那么kgdb就不能设置断点了。

#### 解决方法是：
编辑kernel source目录下生成的.config文件， 禁用CONFIG_DEBUG_RODATA=n (read only data)重新编译即可

------

http://www.mail-archive.com/kgdb-bugreport@lists.sourceforge.net/msg03464.html

> Hi Folks,  
> 
> I'm wondering if anyone has had issues with setting breakpoints. I'm  
> able to break into the kernel, access data, do a backtrace, etc, but  
> when I attempt to set a breakpoint, then continue, I get the following error:  
> 
> Cannot insert breakpoint 1.  
> Error accessing memory address 0xffffffff81310931: Unknown error 4294967295.  
> 
> I'm attaching a sample session, I had set remote debug to 1  
> 
> Thanks!  
> Pat Thomson  

Hi Thomson,  

It seems that your problem is the CONFIG_DEBUG_RODATA option was   
enabled, It is recommend to turn CONFIG_DEBUG_RODATA off when using kgdb.  

 From the kgdb document(DocBook/kgdb.tmpl):

	If the architecture that you are using supports the kernel option
	CONFIG_DEBUG_RODATA, you should consider turning it off.  This
	option will prevent the use of software breakpoints because it
	marks certain regions of the kernel's memory space as read-only.
	If kgdb supports it for the architecture you are using, you can
	use hardware breakpoints if you desire to run with the
	CONFIG_DEBUG_RODATA option turned on, else you need to turn off
	this option.

Thanks,
Dongdong


