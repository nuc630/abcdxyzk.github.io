---
layout: post
title: "内核编译模块"
date: 2013-06-06 14:28:00 +0800
comments: false
categories:
- 2013
- 2013~06
- kernel
- kernel~base
tags:
- kernel
---
```
	/*filename: test.c*/
	#include <linux/init.h>
	#include <linux/kernel.h>
	#include <linux/module.h>

	staticintdummy_init(void)
	{
	    printk("hello,world.\n");
	    return0;
	}
	staticvoiddummy_exit(void)
	{
	    return;
	}

	module_init(dummy_init);
	module_exit(dummy_exit);

	MODULE_LICENSE("GPL")
```
执行如下命令：
```
	$ gcc -c -O2 -DMODULE -D__KERNEL__ -I/usr/src/linux test.c
	$ insmod test.o
```
No module found in object  
insmod: error inserting 'test.o': -1 Invalid module format  

正确的做法是写一个Makefile,由内核的Kbuild来帮你编译。  
```
	$ cat Makefile
	obj-m :=test.o
	KDIR :=/lib/modules/$(shell uname -r)/build
	PWD :=$(shell pwd)
	default:
	    $(MAKE)-C $(KDIR)SUBDIRS=$(PWD)modules
```
执行如下命令：
```
	$make
	make -C /lib/modules/2.6.5-1.358/build SUBDIRS=/test modules
	make[1]:Entering directory `/lib/modules/2.6.5-1.358/build'
	  CC [M]  /test/modinject/test.o
	  Building modules, stage 2.
	  MODPOST
	  CC      /test/modinject/test.mod.o
	  LD [M]  /test/modinject/test.ko
	make[1]: Leaving directory `/lib/modules/2.6.5-1.358/build'
	$ls -l
	-rw-r--r--1 root root   268 Jan  7 08:31 test.c
	-rw-r--r--1 root root  2483 Jan  8 09:19 test.ko
	-rw-r--r--1 root root   691 Jan  8 09:19 test.mod.c
	-rw-r--r--1 root root  1964 Jan  8 09:19 test.mod.o
	-rw-r--r--1 root root  1064 Jan  8 09:19 test.o
```
其实上边的test.o就是用gcc生成的test.o,而test.ko是使用下列命令来生成的。
```
	$ld -m elf_i386  -r -o test.ko test.o  test.mod.o
```

再来看看test.mod.c，它是由/usr/src/linux/scripts/modpost.c来生成的。
```
	$ cat test.mod.c
	#include <linux/module.h>
	#include <linux/vermagic.h>
	#include <linux/compiler.h>

	MODULE_INFO(vermagic,VERMAGIC_STRING);
	#undef unix

	struct module __this_module
	__attribute__((section(".gnu.linkonce.this_module")))={
	.name =__stringify(KBUILD_MODNAME),
	.init =init_module,
	#ifdef CONFIG_MODULE_UNLOAD

	.exit=cleanup_module,
	#endif

	};
	static const struct modversion_info ____versions[]
	__attribute_used__
	__attribute__((section("__versions")))={
		{0,"cleanup_module"},
		{0,"init_module"},
		{0,"struct_module"},
		{0,"printk"},
	};
	static const char __module_depends[]
	__attribute_used__
	__attribute__((section(".modinfo")))=
	"depends=";
```
可见，test.mod.o只是产生了几个ELF的节，分别是modinfo,  .gun.linkonce.this_module(用于重定位，引进了rel.gnu.linkonce.this_module),  __versions。而test.ko是test.o和test.mod.o合并的结果。

