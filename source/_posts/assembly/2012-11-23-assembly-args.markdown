---
layout: post
title: "64位汇编参数传递"
date: 2012-11-23 11:12:00 +0800
comments: false
categories:
- 2012
- 2012~11
- assembly
- assembly~base
tags:
---
#### 64位汇编
当参数少于7个时， 参数从左到右放入寄存器: rdi, rsi, rdx, rcx, r8, r9。  
当参数为7个以上时， 前 6 个与前面一样， 但后面的依次从 "右向左" 放入栈中，即和32位汇编一样。  

参数个数大于 7 个的时候  
H(a, b, c, d, e, f, g, h);  
a->%rdi,   b->%rsi,   c->%rdx,   d->%rcx,   e->%r8,   f->%r9  
h->8(%esp)  
g->(%esp)  
call H  

-------

Linux (and Windows) x86-64 calling conventionhas the first few arguments noton the stack, but in registers instead  
See http://www.x86-64.org/documentation/abi.pdf (page 20)  
Specifically:  
  If the class is MEMORY, pass the argument on the stack.  
  If the class is INTEGER, the next available register of the sequence %rdi, %rsi, %rdx, %rcx, %r8 and %r9 is used.   
  If the class is SSE, the next available vector register is used, the registers are taken in the order from %xmm0 to %xmm7.  
  If the class is SSEUP, the eightbyte is passed in the next available eightbyte chunk of the last used vector register.  
  If the class is X87, X87UP or COMPLEX_X87, it is passed in memory.  
The INTEGERclass is anything that will fit in a general purpose register  

-------
【x86_64 Assembler Calling Convention】

#### 1、x86_64 registers
![](/images/assembly/2013-06-04-1.png)  

#### 2、x86_64寄存器特性表
![](/images/assembly/2013-06-04-2.png)  

#### 3、特性要点：  
　　1）常用寄存器有16个，分为x86通用寄存器以及r8-r15寄存器。  
　　2）通用寄存器中，函数执行前后必须保持原始的寄存器有3个：是rbx、rbp、rsp。rx寄存器中，最后4个必须保持原值：r12、r13、r14、r15。  
	保持原值的意义是为了让当前函数有可信任的寄存器，减小在函数调用过程中的保存&恢复操作。除了rbp、rsp用于特定用途外，其余5个寄存器可随意使用。  
　　3）通用寄存器中，不必假设保存值可随意使用的寄存器有5个：是rax、rcx、rdx、rdi、rsi。其中rax用于第一个返回寄存器（当 然也可以用于其它用途），rdx用于第二个返回寄存器（在调用函数时也用于第三个参数寄存器）。rcx用于第四个参数。rdi用于第一个参数。rsi用于 第二个函数参数。  
　　4）r8、r9分配用于第5、第6个参数。  

