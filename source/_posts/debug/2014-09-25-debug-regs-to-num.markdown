---
layout: post
title: "通用寄存器编码表"
date: 2014-09-25 18:14:00 +0800
comments: false
categories:
- 2014
- 2014~09
- debug
- debug~dwarf
tags:
---
* 来源：systemtap-2.4/runtime/loc2c-runtime.h
#### x86_64
```
	#define pt_dwarf_register_0(regs)       regs->rax
	#define pt_dwarf_register_1(regs)       regs->rdx
	#define pt_dwarf_register_2(regs)       regs->rcx
	#define pt_dwarf_register_3(regs)       regs->rbx
	#define pt_dwarf_register_4(regs)       regs->rsi
	#define pt_dwarf_register_5(regs)       regs->rdi
	#define pt_dwarf_register_6(regs)       regs->rbp
	#define pt_dwarf_register_7(regs)       regs->rsp
	#define pt_dwarf_register_8(regs)       regs->r8
	#define pt_dwarf_register_9(regs)       regs->r9
	#define pt_dwarf_register_10(regs)      regs->r10
	#define pt_dwarf_register_11(regs)      regs->r11
	#define pt_dwarf_register_12(regs)      regs->r12
	#define pt_dwarf_register_13(regs)      regs->r13
	#define pt_dwarf_register_14(regs)      regs->r14
	#define pt_dwarf_register_15(regs)      regs->r15
```

#### i386
```
	#define pt_dwarf_register_0(regs)       regs->eax
	#define pt_dwarf_register_1(regs)       regs->ecx
	#define pt_dwarf_register_2(regs)       regs->edx
	#define pt_dwarf_register_3(regs)       regs->ebx
	#define pt_dwarf_register_4(regs)       (user_mode(regs) ? regs->esp : (long)&regs->esp)
	#define pt_dwarf_register_5(regs)       regs->ebp
	#define pt_dwarf_register_6(regs)       regs->esi
	#define pt_dwarf_register_7(regs)       regs->edi
```

* http://www.mouseos.com/x64/extend64.html 这里的是错的，改正后如下
```
寄存器编码    8    16    32    64
000    al    ax    eax    rax
001    dl    dx    edx    rdx
010    cl    cx    ecx    rcx
011    bl    bx    ebx    rbx
100    ?    si    esi    rsi
101    ?    di    edi    rdi
110    ?    bp    ebp    rbp
111    ?    sp    esp    rsp
1000    r8b    r8w    r8d    r8
1001    r9b    r9w    r9d    r9
1010    r10b    r10w    r10d    r10
1011    r11b    r11w    r11d    r11
1100    r12b    r12w    r12d    r12
1101    r13b    r13w    r13d    r13
1110    r14b    r14w    r14d    r14
1111    r15b    r15w    r15d    r15
```

