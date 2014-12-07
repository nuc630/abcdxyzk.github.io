---
layout: post
title: "jmp指令对应的机器码"
date: 2013-06-18 15:53:00 +0800
comments: false
categories:
- 2013
- 2013~06
- assembly
- assembly~base
tags:
---
  短跳转和近跳转指令中包含的操作数都是相对于(E)IP的偏移，而远跳转指令中包含的是目标的绝对地址，所以短/近跳转会出现跳至同一目标的指令机器码不同，不仅会不同，而且应该不同。而远跳转中包含的是绝对地址，因此转移到同一地址的指令机器码相同

  绝对跳转/调用指令中的内存操作数必须以’*’为前缀，否则gas总是认为是相对跳转/调用指令,而且gas汇编程序自动对跳转指令进行优化，总是使用尽可能小的跳转偏移量。如果8比特的偏移量无法满足要求的话，as会使用一个32位的偏移量，as汇编程序暂时还不支持16位的跳转偏移量，所以对跳转指令使用’addr16’前缀是无效的。还有一些跳转指令只支持8位的跳转偏移量，这些指令是：’jcxz’,’jecxz’,’loop’,’loopz’,’loope’,’loopnz’’loopne’如果你在汇编中使用了这些指令，用gas的汇编可能会出错，因为gcc在编译过程中不产生这些指令，所以在c语言中不必担心这些问题。
```
ffffffff88873036      e8 ff ff 5f c6   =>  call XX        // e8 = call
ffffffff8887303a      ......
```
相当于：目标地址 - ffffffff8887303a(RIP, 指向下一条指令) = ffffffffffff5fc6 (这个是负数，以补码形式展示）  
所以：   目标地址 = ffffffff88869000  

* 即：  ffffffff88869000 - ffffffff8887303a + ffffffffffffffff + 1 = ffffffffffff5fc6  
* 可以用 unsigned long 类型来计算，让它自然溢出就好了，(unsigned long)func1 - ((unsigned long)func2 + 0x偏移)

先计算好偏移，再替换call地址，就偷偷的改了调用。

附：若为e8 00 00 00 00 则可以同过模块读取 00 00 00 00 的实际值

