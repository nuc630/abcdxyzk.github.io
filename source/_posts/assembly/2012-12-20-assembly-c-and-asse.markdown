---
layout: post
title: "c与汇编的关系"
date: 2012-12-20 15:25:00 +0800
comments: false
categories:
- 2012
- 2012~12
- assembly
- assembly~base
tags:
---
_start是汇编程序的入口，main是c程序的入口？  
gcc 只是一个  外壳而不是真正的编译器，这真的c编译器是/usr/lib/gcc/i486-gun/4.3.2/cc1,gcc调用c编译器、汇编器和链接器完成c 代码的编译链接工作。/usr/lib/gcc/i486-linux-gun/4.3.2/collect2是链接器ld的外壳，它调用ld完成链接。  

i main.c被cc1编译成汇编程序/tmp/ccRGDpua.s。  
ii 这个汇编程序被as汇编成目标文件/tmp/ccidnZ1d.o  
iii   这个目标文件连同另外几个目标文件（crt1.o,crti.o,crtbegin.o,crtend.o,crtn.o)一起链接成可执行文件 main。在链接过程中还用-l，选项指定一些库文件，有libc、libgcc、ligcc_s，其中有些库是共享库，需要动态链接，所以用 -dynamic-linker选项指定动态链接器是/lib/ld-linux.so.2  
```
	$ nm /usr/lib/crt1.o
	00000000 R  _IO_stdin_used
	00000000 D __data_start
	                 U __libc_csu_fini
	                 U __libc_csu_init
	                 U __libc_start_main
	00000000 R _fp_hw
	00000000 T _start
	00000000 W data_start
	                 U main
```
U main 这一行表示main这个符号在crt1.o已经被引用了，但是还没有定义（Undefined），因此需要别的目标文件提供一个定义并且和crt1.o链接在一起。T_start表示在crt1.o中已定义为（text）。

c 程序的入口点其实是crt1.o提供的_start，它先做一些初始化工作（启动例程，startup  routine），然后调用我们编写的main函数。所以，main函数是程序的入口，不够准确。_start才是真正的入口点，而main函数是被 _start调用的。

U  __libc_start_main，这个符号在其他几个目标文件中也没有定义，所以链接生成可执行文件之后仍然是个未定义符号。事实上这个符号在 libc中定义，libc是一个共享库，它并不像其他目标文件一样链接到可执行文件main中，而是在运行时做动态链接：  
i 操作系统在加载main这个程序时，首先看它有没有需要动态链接的未定义符号。  
ii如果需要做动态链接，就查看这个程序指定了哪些共享库，以及用什么动态链接器来做动态链接。我们在链接时用-lc选项指定了共享库libc，用-dynamic-linker /lib/ld-linux.so.2 指定动态链接器，这些信息都会写到可执行文件中。  
iii动态连接器加载共享库，在其中查找这些未定义符号的定义，完成链接过程。  

c内联汇编

完整的内联汇编格式：
```
	__asm__(asembler template
			:output operands
			: input operands
			: list of clobbered registers
			);

	e.g.

	#include <stdio.h>
	int main(void)
	{
		int a=10,b;
		__asm__("movl %1,%%eax\n\t"
				"movl %%eax,%0\n\t"
				:"=r"(b)	//把%0所代表的寄存器的值输出给变量b
				:"r"(a)		//告诉编译器分配一个寄存器保存变量a的值，作为汇编程序的输入，对应%1
				:"%eax"
		);
		printf("result:%d,%d\n",a,b);
		return 0;
	}
```
