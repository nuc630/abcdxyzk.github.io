---
layout: post
title: "gcc同时使用动态和静态链接"
date: 2014-11-06 14:51:00 +0800
comments: false
categories:
- 2014
- 2014~11
- compiler
- compiler~base
tags:
---
gcc --static a.c -Wl,-Bstatic -lm -Wl,-Bdynamic -lc  

其中用到的两个选项：-Wl,-Bstatic和-Wl,-Bdynamic。这两个选项是gcc的特殊选项，它会将选项的参数传递给链接器，作为 链接器的选项。比如-Wl,-Bstatic告诉链接器使用-Bstatic选项，该选项是告诉链接器，对接下来的-l选项使用静态链 接；-Wl,-Bdynamic就是告诉链接器对接下来的-l选项使用动态链接。下面是man gcc对-Wl,option的描述，  
```
	-Wl,option  
	   Pass option as an option to the linker.  If option contains commas, it is   
	   split into multiple options at the commas.  You can use this syntax to pass  
	   an argument to the option.  For example, -Wl,-Map,output.map passes -Map output.map  
	   to the linker.  When using the GNU linker, you can also get the same effect with   
	   -Wl,-Map=output.map.  
```
下面是man ld分别对-Bstatic和-Bdynamic的描述，  
```
	-Bdynamic  
	-dy  
	-call_shared  
	   Link against dynamic libraries. You may use this option multiple times on the  
	   command line: it affects library searching for -l options which follow it.  

	-Bstatic  
	-dn  
	-non_shared  
	-static  
	   Do not link against shared libraries. You may use this option multiple times on   
	   the command line: it affects library searching for -l options which follow it.   
	   This option also implies --unresolved-symbols=report-all.  This option can be   
	   used with -shared.  Doing so means that a shared library is being created but   
	   that all of the library's external references must be resolved by pulling in   
	   entries from static libraries.  
```
值得注意的是对-static的描述：-static和-shared可以同时存在，这样会创建共享库，但该共享库引用的其他库会静态地链接到该共享库中。
