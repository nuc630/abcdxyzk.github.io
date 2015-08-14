---
layout: post
title: "Linux内核kretprobe机制"
date: 2013-05-24 10:22:00 +0800
comments: false
categories:
- 2013
- 2013~05
- debug
- debug~kprobe
tags:
---
http://www.ibm.com/developerworks/cn/linux/l-cn-systemtap1/index.html

  kretprobe也使用了kprobes来实现，当用户调用register_kretprobe()时，kprobe在被探测函数的入口建立 了一个探测点，当执行到探测点时，kprobe保存了被探测函数的返回地址并取代返回地址为一个trampoline的地址，kprobe在初始化时定义 了该trampoline并且为该trampoline注册了一个kprobe,当被探测函数执行它的返回指令时，控制传递到该trampoline，因 此kprobe已经注册的对应于trampoline的处理函数将被执行，而该处理函数会调用用户关联到该kretprobe上的处理函数，处理完毕后， 设置指令寄存器指向已经备份的函数返回地址，因而原来的函数返回被正常执行。

  被探测函数的返回地址保存在类型为 kretprobe_instance的变量中，结构kretprobe的maxactive字段指定了被探测函数可以被同时探测的实例数，函数 register_kretprobe()将预分配指定数量的kretprobe_instance。如果被探测函数是非递归的并且调用时已经保持了自旋 锁（spinlock），那么maxactive为1就足够了；  如果被探测函数是非递归的且运行时是抢占失效的，那么maxactive为NR_CPUS就可以了；如果maxactive被设置为小于等于0,  它被设置到缺省值（如果抢占使能， 即配置了  CONFIG_PREEMPT，缺省值为10和2*NR_CPUS中的最大值，否则缺省值为NR_CPUS）。

  如果 maxactive被设置的太小了，一些探测点的执行可能被丢失，但是不影响系统的正常运行，在结构kretprobe中nmissed字段将记录被丢失 的探测点执行数，它在返回探测点被注册时设置为0，每次当执行探测函数而没有kretprobe_instance可用时，它就加1。

http://hi.baidu.com/lixiang1988/item/8884bc286c9920ceddf69acd

#### kretprobe的实现
相关数据结构与函数分析
##### 1)　struct kretprobe结构
  该结构是kretprobe实现的基础数据结构，以下是该结构的成员：
```
	struct kprobe kp; //该成员是kretprobe内嵌的struct kprobe结构。
	kretprobe_handler_t handler;//该成员是调试者定义的回调函数。
	int maxactive;//该成员是最多支持的返回地址实例数。
	int nmissed;//该成员记录有多少次该函数返回没有被回调函数处理。
	struct hlist_head free_instances;
	用于链接未使用的返回地址实例，在注册时初始化。
	struct hlist_head used_instances;//该成员是正在被使用的返回地址实例链表。
```
##### 2)　struct kretprobe_instance结构
  该结构表示一个返回地址实例。因为函数每次被调用的地方不同，这造成了返回地址不同，因此需要为每一次发生的调用记录在这样一个结构里面。以下是该结构的成员：
```
	struct hlist_node uflist;
	该成员被链接入kretprobe的used_instances或是free_instances链表。
	struct kretprobe *rp;//该成员指向所属的kretprobe结构。
	kprobe_opcode_t *ret_addr;//该成员用于记录被探测函数正真的返回地址。
	struct task_struct *task;//该成员记录当时运行的进程。
```
##### 3)　pre_handler_kretprobe()函数
  该函数在kretprobe探测点被执行到后，用于修改被探测函数的返回地址。

##### 4)　trampoline_handler()函数
  该函数用于执行调试者定义的回调函数以及把被探测函数的返回地址修改回原来的返回地址。

#### kretprobe处理流程分析
  kretprobe探测方式是基于kprobe实现的又一种内核探测方式，该探测方式主要用于在函数返回时进行探测，获得内核函数的返回值，还可以用于计算函数执行时间等方面。
##### 1)　kretprobe的注册过程
  调试者要进行kretprobe调试首先要注册处理，这需要在调试模块中调用register_kretprobe()，下文中称该函数为 kretprobe  注册器。kretprobe注册器对传入的kretprobe结构的中kprobe.pre_handler赋值为 pre_handler_kretprobe()函数，用于在探测点被触发时被调用。接着，kretprobe注册器还会初始化kretprobe的一些 成员，比如分配返回地址实例的空间等操作。最后，kretprobe注册器会利用  kretprobe内嵌的structkprobe结构进行kropbe的注册。自此，kretprobe注册过程就完成了。

##### 2)　kretprobe探测点的触发过程
  kretprobe触发是在刚进入被探测函数的第一条汇编指令时发生的，因为 kretprobe注册时把该地址修改位int3指令。  
  此时发生了一次CPU异常处理，这与kprobe探测点被触发相同。但与kprobe处理不同的是，这里并不是运行用户定义的pre_handler函 数，而是执行pre_handler_kretprobe()函数，该函数又会调用arch_prepare_kretprobe()函数。 arch_prepare_kretprobe()函数的主要功能是把被探测函数的返回地址变换为&kretprobe_trampoline所 在的地址，这是一个汇编地址标签。这个标签的地址在kretprobe_trampoline_holder()中用汇编伪指令定义。替换函数返回地址是 kretprobe实现的关键。当被探测函数返回时，返回到&kretprobe_trampoline地址处开始运行。

  接着，在 一些保护现场的处理后，又去调用trampoline_handler()函数。该函数的主要有两个作用，一是根据当前的实例去运行用户定义的调试函数， 也就是kretprobe结构中的handler所指向的函数，二是把返回值设成被探测函数正真的返回地址。最后，在进行一些堆栈的处理后，被探测函数又 返回到了正常执行流程中去。

  以上讨论的就是kretprobe的执行过程，可以看出，该调试方式的关键点在于修改被探测函数的返回地址到kprobes的控制流程中，之后再把返回地址修改到原来的返回地址并使得该函数继续正常执行。

