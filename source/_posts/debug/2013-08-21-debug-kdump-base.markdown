---
layout: post
title: "linux内核调试转储工具kdump crash"
date: 2013-08-21 17:21:00 +0800
comments: false
categories:
- 2013
- 2013~08
- debug
- debug~kdump、crash
tags:
---
http://www.ibm.com/developerworks/cn/linux/l-cn-kdump4/index.html

```
$ crash vmlinux vmcore 
crash> bt
crash> dis -l ffffffff80081000
crash> gdb x/8ub ffffffff90091000
......
```
如果是未完成文件可以尝试以最小方式调试
```
$ crash --minimal vmlinux vmcore
crash> log
```
```
	crash_H_args_xbt> mod -S
	 MODULE   NAME		 SIZE  OBJECT FILE
	c8019000  soundcore	2788  /lib/modules/2.2.5-15/misc/soundcore.o
。。。
	crash_H_args_xbt> mod -s soundcore
	 MODULE   NAME		 SIZE  OBJECT FILE
	c8019000  soundcore	2788  /lib/modules/2.2.5-15/misc/soundcore.o
	crash_H_args_xbt> mod -d soundcore
	crash_H_args_xbt> mod -s soundcore /tmp/soundcore.o
	 MODULE   NAME		 SIZE  OBJECT FILE
	c8019000  soundcore	2788  /tmp/soundcore.o
```
-------------------

#### 1、kdump介绍与设置
##### 1）介绍：
Kdump 是一种基于 kexec 的内存转储工具，目前它已经被内核主线接收，成为了内核的一部分，它也由此获得了绝大多数 Linux 发行版的支持。与传统的内存转储机制不同不同，基于 Kdump 的系统工作的时候需要两个内核，一个称为系统内核，即系统正常工作时运行的内核；另外一个称为捕获内核，即正常内核崩溃时，用来进行内存转储的内核。

安装crash，kexec-tools

##### 2）设置
查看/boot/grub/grub.conf文件中kernel一行最后是否有crashkernel=128M@64M，如果没有，添加上去，重启  
如何设定 crashkernel 参数  
在 kdump 的配置中，往往困惑于 crashkernel 的设置。“crashkernel=X@Y”，X 应该多大？ Y 又应该设在哪里呢？实际我们 可以完全省略“@Y”这一部分，这样，kernel 会为我们自动选择一个起始地址。而对于 X 的大小，般对 i386/x86_64 的系统， 设为 128M 即可；对于 powerpc 的系统，则要设为 256M。rhel6 引入的“auto”已经要被放弃了，代之以原来就有的如下语法：
```
	crashkernel=<range1>:<size1>[,<range2>:<size2>,...][@offset] 
			  range=start-[end] 
			  'start' is inclusive and 'end' is exclusive. 

			  For example: 
			  crashkernel=512M-2G:64M,2G-:128M
```
如何判断捕获内核是否加载  
可通过查看 /sys/kernel/kexec_crash_loaded 的值。“1”为已经加载，“0”为还未加载。  
缩小 crashkernel  
可以通过向 /sys/kernel/kexec_crash_size 中输入一个比其原值小的数来缩小甚至完全释放 crashkernel。  

##### 3）测试kdump是否可用
执行
```
echo 1 > /proc/sys/kernel/sysrq
echo c > /proc/sysrq-trigger
```
经过两次自动重启后，查看/var/crash/目录下是否有vmcore文件生成,如果有表示kdump可用

#### 2、生成带调试信息的vmlinux文件
##### 1）
centos:	debuginfo.centos.org
##### 2）按顺序安装
kernel-debuginfo-common-2.6.18-194.3.1.el5.i686.rpm和kernel-debuginfo-2.6.18-194.3.1.el5.i686.rpm，
之后会在/usr/lib/debug/lib/modules/2.6.18-194.3.1.el5/下生产vmlinux文件  
或在源码里make binrpm-pkg -j8，然后该目录下会生成一个vmlinux  
在编译内核之前，需要确认.config中，以下编译选项是否打开：
>（1）CONFIG_DEBUG_INFO ，必须打开该选项，否则crash会出现以下错误：  
>	crash no debugging data available  
>（2）CONFIG_STRICT_DEVMEM,必须打开该选项，否则crash会出现以下错误：  
>	crash: read error: kernel virtual address: c0670680  type: "kernel_config_data"  
>	WARNING: cannot read kernel_config_data  
>	crash: read error: kernel virtual address: c066bb68  type: "cpu_possible_mask"  

#### 3、进入vmlinux所在目录，
执行crash /var/crash/2012-03-13-21\:05/vmcore vmlinux   
mod -S XXX  --导入XXX目录下所有符号  
log --查看日志文件，找到最后一条，如EIP: [<f8ee53f5>] bshtej_interrupt+0x103f/0x11cb [tej21] SS:ESP 0068:c0768f38  
l* bshtej_interrupt+0x103f 出现如下内容  
```
0xf8ee53f5 is in bshtej_interrupt (/opt/dahdi-linux-complete-2.2.1+2.2.1/linux/drivers/dahdi/tej21/tej21.c:2910).
2904			int c, x;
2905
2906
2907			for(c = 0; c < MAX_CARDS; c++)
2908			{
2909				if (!cards[c]) break;
2910				for (x=0;x<cards[c]->numspans;x++) {
2911					if (cards[c]->tspans[x]->sync)
2912					{
2913
```
到此可确定死机问题出现在2910行。

#### 4、设置过滤等级：
vmcore文件一般会收集内核崩溃时的各种信息，所以生成时间会较长，文件比较大，如果不需要某些信息的话，可对kdump.conf文件进行配置
```
vim  /etc/kdump.conf
```
将core_collector makedumpfile -c 这行打开，并加上-d 31，参数说明如下：
```
-c: Compress dump data by each page.
-d: Specify the type of unnecessary page for analysis.
	Dump  |	zero	cache	cache	user	free
	Level |	page	page	private	data	page
  -------+---------------------------------------
	0  |
	1  |	X
	2  |		X
	4  |		X	X
	8  |				X
	16  |					X
	31  |	X	X	X	X	X

##### 5、根据Oops值大致判断错误：
Oops的错误代码根据错误的原因会有不同的定义如果发现自己遇到的Oops和下面无法对应的话，最好去内核代码里查找：
```
* error_code:
 *	  bit 0 == 0 means no page found, 1 means protection fault
 *	  bit 1 == 0 means read, 1 means write
 *	  bit 2 == 0 means kernel, 1 means user-mode
 *	  bit 3 == 0 means data, 1 means instruction
```

