---
layout: post
title: "用户态到内核态切换"
date: 2015-06-02 14:16:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~sched
tags:
---
http://www.cnblogs.com/justcxtoworld/p/3155741.html

本文将主要研究在X86体系下Linux系统中用户态到内核态切换条件，及切换过程中内核栈和任务状态段TSS在中断机制/任务切换中的作用及相关寄存器的变化。

#### 一、用户态到内核态切换途径：

 1：系统调用        2：中断 　　3：异常

对应代码，在3.3内核中，可以在/arch/x86/kernel/entry_32.S文件中查看。

#### 二、内核栈

内核栈：Linux中每个进程有两个栈，分别用于用户态和内核态的进程执行，其中的内核栈就是用于内核态的堆栈，它和进程的task_struct结构，更具体的是thread_info结构一起放在两个连续的页框大小的空间内。

在内核源代码中使用C语言定义了一个联合结构方便地表示一个进程的thread_info和内核栈：

此结构在3.3内核版本中的定义在include/linux/sched.h文件的第2106行：
```
	2016  union thread_union {
	2017          struct thread_info thread_info;
	2018          unsigned long stack[THREAD_SIZE/sizeof(long)];
	2019     };        
```

其中thread_info结构的定义如下：

3.3内核 /arch/x86/include/asm/thread_info.h文件第26行：
```
	 26 　　struct thread_info {
	 27         struct task_struct      *task;          /* main task structure */
	 28         struct exec_domain      *exec_domain;   /* execution domain */
	 29         __u32                   flags;          /* low level flags */
	 30         __u32                   status;         /* thread synchronous flags */
	 31         __u32                   cpu;            /* current CPU */
	 32         int                     preempt_count;  /* 0 => preemptable,
	 33                                                    <0 => BUG */
	 34         mm_segment_t            addr_limit;
	 35         struct restart_block    restart_block;
	 36         void __user             *sysenter_return;
	 37 #ifdef CONFIG_X86_32
	 38         unsigned long           previous_esp;   /* ESP of the previous stack in
	 39                                                    case of nested (IRQ) stacks
	 40                                                 */
	 41         __u8                    supervisor_stack[0];
	 42 #endif
	 43         unsigned int            sig_on_uaccess_error:1;
	 44         unsigned int            uaccess_err:1;  /* uaccess failed */
	 45 };
```

它们的结构图大致如下：

![](/images/kernel/2015-06-02.png)  

  esp寄存器是CPU栈指针，存放内核栈栈顶地址。在X86体系中，栈开始于末端，并朝内存区开始的方向增长。从用户态刚切换到内核态时，进程的内核栈总是空的，此时esp指向这个栈的顶端。

  在X86中调用int指令型系统调用后会把用户栈的%esp的值及相关寄存器压入内核栈中，系统调用通过iret指令返回，在返回之前会从内核栈弹出用户栈的%esp和寄存器的状态，然后进行恢复。所以在进入内核态之前要保存进程的上下文，中断结束后恢复进程上下文，那靠的就是内核栈。

  这里有个细节问题，就是要想在内核栈保存用户态的esp,eip等寄存器的值，首先得知道内核栈的栈指针，那在进入内核态之前，通过什么才能获得内核栈的栈指针呢？答案是：TSS

#### 三、TSS

X86体系结构中包括了一个特殊的段类型：任务状态段（TSS），用它来存放硬件上下文。TSS反映了CPU上的当前进程的特权级。

linux为每一个cpu提供一个tss段，并且在tr寄存器中保存该段。

在从用户态切换到内核态时，可以通过获取TSS段中的esp0来获取当前进程的内核栈 栈顶指针，从而可以保存用户态的cs,esp,eip等上下文。

注：linux中之所以为每一个cpu提供一个tss段，而不是为每个进程提供一个tss段，主要原因是tr寄存器永远指向它，在任务切换的适合不必切换tr寄存器，从而减小开销。

下面我们看下在X86体系中Linux内核对TSS的具体实现：

内核代码中TSS结构的定义：

3.3内核中：/arch/x86/include/asm/processor.h文件的第248行处：
```
	248   struct tss_struct {
	249         /*
	250          * The hardware state:
	251          */
	252         struct x86_hw_tss       x86_tss;
	253 
	254         /*
	255          * The extra 1 is there because the CPU will access an
	256          * additional byte beyond the end of the IO permission
	257          * bitmap. The extra byte must be all 1 bits, and must
	258          * be within the limit.
	259          */
	260         unsigned long           io_bitmap[IO_BITMAP_LONGS + 1];
	261 
	262         /*
	263          * .. and then another 0x100 bytes for the emergency kernel stack:
	264          */
	265         unsigned long           stack[64];
	266 
	267 } ____cacheline_aligned;    
```

其中主要的内容是：  
  硬件状态结构:     x86_hw_tss  
  IO权位图: 　　　　io_bitmap  
  备用内核栈: 　　  stack  

其中硬件状态结构：其中在32位X86系统中x86_hw_tss的具体定义如下：

/arch/x86/include/asm/processor.h文件中第190行处：
```
	190#ifdef CONFIG_X86_32
	191 /* This is the TSS defined by the hardware. */
	192 struct x86_hw_tss {
	193         unsigned short          back_link, __blh;
	194         unsigned long           sp0;　　            //当前进程的内核栈顶指针
	195         unsigned short          ss0, __ss0h;       //当前进程的内核栈段描述符
	196         unsigned long           sp1;
	197         /* ss1 caches MSR_IA32_SYSENTER_CS: */
	198         unsigned short          ss1, __ss1h;
	199         unsigned long           sp2;
	200         unsigned short          ss2, __ss2h;
	201         unsigned long           __cr3;
	202         unsigned long           ip;
	203         unsigned long           flags;
	204         unsigned long           ax;
	205         unsigned long           cx;
	206         unsigned long           dx;
	207         unsigned long           bx;
	208         unsigned long           sp;      　　　　　　//当前进程用户态栈顶指针
	209         unsigned long           bp;
	210         unsigned long           si;
	211         unsigned long           di;
	212         unsigned short          es, __esh;
	213         unsigned short          cs, __csh;
	214         unsigned short          ss, __ssh;
	215         unsigned short          ds, __dsh;
	216         unsigned short          fs, __fsh;
	217         unsigned short          gs, __gsh;
	218         unsigned short          ldt, __ldth;
	219         unsigned short          trace;
	220         unsigned short          io_bitmap_base;
	221 
	222 } __attribute__((packed));
```

linux的tss段中只使用esp0和iomap等字段，并且不用它的其他字段来保存寄存器，在一个用户进程被中断进入内核态的时候，从tss中的硬件状态结构中取出esp0（即内核栈栈顶指针），然后切到esp0，其它的寄存器则保存在esp0指的内核栈上而不保存在tss中。

每个CPU定义一个TSS段的具体实现代码：

3.3内核中/arch/x86/kernel/init_task.c第35行：
```
	 35  * per-CPU TSS segments. Threads are completely 'soft' on Linux,
	 36  * no more per-task TSS's. The TSS size is kept cacheline-aligned
	 37  * so they are allowed to end up in the .data..cacheline_aligned
	 38  * section. Since TSS's are completely CPU-local, we want them
	 39  * on exact cacheline boundaries, to eliminate cacheline ping-pong.
	 40  */

	 41 DEFINE_PER_CPU_SHARED_ALIGNED(struct tss_struct, init_tss) = INIT_TSS;
```

INIT_TSS的定义如下:

3.3内核中 /arch/x86/include/asm/processor.h文件的第879行：
```
	879 #define INIT_TSS  {                                                       \
	880         .x86_tss = {                                                      \
	881                 .sp0            = sizeof(init_stack) + (long)&init_stack, \
	882                 .ss0            = __KERNEL_DS,                            \
	883                 .ss1            = __KERNEL_CS,                            \
	884                 .io_bitmap_base = INVALID_IO_BITMAP_OFFSET,               \
	885          },                                                               \
	886         .io_bitmap              = { [0 ... IO_BITMAP_LONGS] = ~0 },       \
	887 }
```

其中init_stack是宏定义，指向内核栈：
```
	61 #define init_stack              (init_thread_union.stack)
```
这里可以看到分别把内核栈栈顶指针、内核代码段、内核数据段赋值给TSS中的相应项。从而进程从用户态切换到内核态时，可以从TSS段中获取内核栈栈顶指针，进而保存进程上下文到内核栈中。


#### 总结、有了上面的一些准备，现总结在进程从用户态到内核态切换过程中，Linux主要做的事：
  1：读取tr寄存器，访问TSS段  
  2：从TSS段中的sp0获取进程内核栈的栈顶指针  
  3：由控制单元在内核栈中保存当前eflags,cs,ss,eip,esp寄存器的值。  
  4：由SAVE_ALL保存其寄存器的值到内核栈  
  5：把内核代码选择符写入CS寄存器，内核栈指针写入ESP寄存器，把内核入口点的线性地址写入EIP寄存器  

此时，CPU已经切换到内核态，根据EIP中的值开始执行内核入口点的第一条指令。


