---
layout: post
title: "中断栈溢出后的结果"
date: 2015-05-07 15:54:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~irq
tags:
---
http://www.lenky.info/archives/2013/03/2247

说一下上文中最开始提到的“某个问题”：如果一台主机网卡比较多，然后每个网卡分队列又比较多，总之结果就是系统里的网卡设备的中断号比较多（关于超过256个中断数的情况，请见参考1，2，3），一旦所有这些中断都绑定到同一个CPU，那么如果网卡收到数据包进而触发中断，而众多硬中断一嵌套就非常容易出现中断栈溢出。一旦中断栈溢出，那么将会导致怎样的结果，这曾在之前的文章里隐含的提到过，这里再重新整理一遍。

在继续下面的描述之前，先看两个知识点：
##### 1，Linux 2.4.x的中断栈：
a)，由硬中断/软中断共同使用同一个中断栈  
b)，中断栈与内核栈共享一个栈  
c)，中断执行的时候使用的栈就是当前进程的内核栈  

##### 2，Linux 2.6.x的中断栈：
a)，硬中断与软中断分离使用不同的中断栈  
b)，中断栈与内核栈分离  
c)，X86_64 double fault、NMI还可以有额外的栈（64bit特性：IST(Interrupt Stack Table)）  

可以看到，对于Linux 2.4.x内核而言，因为中断处理函数使用内核栈作为中断栈，所以导致更加容易发生内核栈溢出（因内核函数本身用栈过多导致溢出，或内核函数本身还未导致内核栈溢出，但此时来了一个中断，因中断函数使用栈而导致溢出，即中断函数成了压死骆驼的最后一根稻草），而内核栈溢出的直接结果就是踩坏task结构体，从而无法正常执行对应的task进程而出现oops宕机。

由于“中断执行的时候使用的栈就是当前进程的内核栈”，所以如果是执行到中断函数后才溢出，那么导致oops里提示的进程信息可能每次都不一样，因此如果出现这种情况，需要考虑是中断函数导致内核栈溢出，否则需怀疑普通的内核函数导致栈溢出即可。

对于Linux 2.6.x内核而言，因为其中断/内核栈分离、软/硬中断栈分离，即每个CPU私有两个栈（见下面注释）分别处理软中断和硬中断，因此出现内核栈溢出，特别是中断栈溢出的概率大大降低。

注释：这个说法来之书本《Understanding.the.Linux.Kernel.3rd.Edition》4.6.1.4. Multiple Kernel Mode stacks，而这本书针对的内核版本是2.6.11，且主要是指32位架构，所以与现在的新版内核源码有些许出入（比如现在情况的栈大小可能是占用2页），但这些细微改变与本文的具体问题相关不大（无非是溢出的难易程度问题），这里不再深入研究，具体情况请参考源代码自行斟酌。
```
	The hard IRQ stack is used when handling interrupts. There is one hard IRQ stack for each CPU in the system, and each stack is contained in a single page frame.

	The soft IRQ stack is used when handling deferrable functions (softirqs or tasklets; see the later section “Softirqs and Tasklets”). There is one soft IRQ stack for each CPU in the system, and each stack is contained in a single page frame. 
```
回到本文的主题，在之前的文章里提到过，即如果中断/异常处理函数本身在处理的过程中出现异常，那么就有可能发生double fault，比如中断栈溢出。中断栈溢出导致的最终结果有两种情况，这由所使用的具体Linux内核版本来决定，更具体点说是由double fault异常的栈是否单独来决定（见参考1）。

1，double fault的栈被单独出来  
这意味着double fault的处理函数还能正常执行，因此打印oops，宕机。

2，double fault的栈没有被单独出来  
这意味着double fault的处理函数也无法正常执行，进而触发triple fault，机器直接重启。

对于86-64架构下的Linux 2.6.x内核，因为IST(Interrupt Stack Table)的帮助，所以中断栈溢出导致的最终结果就是打印oops，宕机。

下面来看内核源码文档kernel-stacks，  
1，每一个活动线程都有一个内核栈，大小为2页。  
2，每一个cpu有一些专门的栈，只有当cpu执行在内核态时，这些栈才有用；一旦cpu回退到用户态，这些特定栈就不再包含任何有用数据。  
3，主要的特定栈有：  
a，中断栈：外部硬件中断的处理函数使用，单独的栈可以提供给中断处理函数更多的栈空间。  
这里还提到，在2.6.x-i386下，如果设置内核栈只有4K，即CONFIG_4KSTACKS，那么中断栈也是单独开的。备注：这个已有修改，2010-06-29 x86: Always use irq stacks，即不管设置的内核栈是否只有4K，中断栈都是独立的了。  

另外，这里有个说法与前面的引用有点出入：
```
	The interrupt stack is also used when processing a softirq. 
```
即软中断和硬中断一样，也是使用这个中断栈。

b，x86_64所特有的（也就是i386没有，即同时2.6.30.8内核，32位的Linux就不具备下面所说的这个特性），为double fault或NMI单独准备的栈，这个特性被称为Interrupt Stack Table(IST)。每个cpu最多支持7个IST。关于IST的具体原理与实现暂且不说，直接来看当前已经分配的IST独立栈：

* STACKFAULT_STACK. EXCEPTION_STKSZ (PAGE_SIZE)  
12号中断Stack Fault Exception (#SS)使用  

* DOUBLEFAULT_STACK. EXCEPTION_STKSZ (PAGE_SIZE)  
8号中断Double Fault Exception (#DF)使用  

* NMI_STACK. EXCEPTION_STKSZ (PAGE_SIZE)  
2号中断non-maskable interrupts (NMI)使用  

* DEBUG_STACK. DEBUG_STKSZ  
1号中断硬件调试和3号中断软件调试使用  

* MCE_STACK. EXCEPTION_STKSZ (PAGE_SIZE)  
18号中断Machine Check Exception (#MC)使用  

正因为double fault异常处理函数所使用的栈被单独了出来，所以在出现中断栈溢出时，double fault异常的处理函数还能正常执行，顺利打印出oops信息。

最后的最后，有补丁移除IST功能（貌似是因为如果没有IST功能，那么kvm可以得到更好的优化，具体请见参考5），但通过对比补丁修改与实际源码（2.6.30.8以及3.6.11）来看，这个补丁并没有合入mainline主线。

#### 参考资料：
1，where is hardware timer interrupt?  
http://stackoverflow.com/questions/14481032/where-is-hardware-timer-interrupt

2，The MSI Driver Guide HOWTO  
https://git.kernel.org/cgit/linux/kernel/git/stable/linux-stable.git/tree/Documentation/PCI/MSI-HOWTO.txt?id=v2.6.30.8  
对应的翻译版：http://blog.csdn.net/reviver/article/details/6802347  

3，[PATCH] x86: 64bit support more than 256 irq v2  
http://linux-kernel.2935.n7.nabble.com/PATCH-x86-64bit-support-more-than-256-irq-v2-td323261.html  

4，How is an Interrupt handled in Linux?  
http://unix.stackexchange.com/questions/5788/how-is-an-interrupt-handled-in-linux  

5，Remove interrupt stack table usage from x86_64 kernel (v2)  
http://lwn.net/Articles/313029/  
http://thread.gmane.org/gmane.comp.emulators.kvm.devel/26741  

6，Interrupt Descriptor Table  
http://wiki.osdev.org/IDT  

转载请保留地址：http://www.lenky.info/archives/2013/03/2247 或 http://lenky.info/?p=2247

