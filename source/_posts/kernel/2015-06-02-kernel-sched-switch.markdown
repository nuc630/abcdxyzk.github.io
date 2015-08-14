---
layout: post
title: "进程切换过程分析"
date: 2015-06-02 14:10:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~sched
tags:
---
http://blog.csdn.net/nkguohao/article/details/9187381


参考《深入理解Linux内核（第三版）》

#### 进程切换

为了控制进程的执行，内核必须有能力挂起正在CPU上运行的进程，并恢复以前挂起的某个进程的执行。这种行为被称为进程切换，任务切换或上下文切换。下面几节描述在Linux中进行进程切换的主要内容。


#### 硬件上下文

尽管每个进程可以拥有属于自己的地址空间，但所有进程必须共享CPU寄存器。因此要恢复一个进程的执行之前，内核必须确保每个寄存器装入了挂起进程时的值。

进程恢复执行前必须装入寄存器的一组数据称为硬件上下文。硬件上下文是进程可执行上下文的一个子集，因为可执行上下文包含进程执行时需要的所有信息。在Linux中，进程硬件上下文的一部分存在TSS段，而剩余部分存放在内核态的堆栈中。


在下面的描述中，我们假定用prev局部变量表示切换出的进程的描述符，next表示切换进的进程的描述符。因此，我们把进程切换定义为这样的行为：保存prev硬件上下文，用next硬件上下文代替prev。因为进程切换经常发生，因此减少和装入硬件上下文所花费的时间是非常重要的。


早期的Linux版本利用80x86体系结构所提供的硬件支持，并通过far jmp指令跳到进程TSS描述符的选择符来执行进程切换。当执行这条指令时，CPU通过自动保存原来的硬件上下文，装入新的硬件上下文来执行硬件上下文切换。但是基于以下原因，Linux2.6使用软件执行进程切换：

  通过一组mov指令逐步执行切换，这样能较好地控制所装入数据的合法性，尤其是，这使检查ds和es段寄存器的值成为可能，这些值有可能被恶意用户伪造。当用单独的farjmp指令时，不可能进行这类检查。

  旧方法和新方法所需时间大致相同。然而，尽管当前的切换代码还有改进的余地，却不能对硬件上下文切换进行优化。

进程切换只发生在内核态。在执行进程切换之前，用户态进程所使用的所有寄存器内容已保存在内核态堆栈上，这也包括ss和esp这对寄存器的内容。


#### 任务状态段

80x86体系结构包括一个特殊的段类型，叫任务状态段（Task State Segment, TSS）来存放硬件上下文。尽管Linux并不使用硬件上下文切换，但是强制它为系统中每个不同的CPU创建一个TSS。这样做的两个主要理由为：  
  当80x86的一个CPU从用户态切换到内核态时，它就从TSS中获取内核态堆栈的地址。  
  当用户态进程试图通过in或out指令访问一个I/O端口时，CPU需要访问存放在TSS中的I/O许可图以检查该进程是否有访问端口的权力。  

更确切地说，当进程在用户态下执行in或out指令时，控制单元执行下列操作：  
  它检查eflags寄存器中的2位IOPL字段。如果该字段值为3，控制单元就执行I/O指令。否则，执行下一个检查。  
  访问tr寄存器以确定当前的TSS和相应的I/O许可权位图。  
  检查I/O指令中指定的I/O端口在I/O许可权位图中对应的位。如果该位清0，这条I/O指令就执行，否则控制单元产生一个”Generalprotetion”异常。  

tss_struct结构描述TSS的格式。正如第二章(《深入理解Linux内核（第三版）》)所提到的，init_tss数组为系统上每个不同的CPU存放一个TSS。在每次进程切换时，内核都更新TSS的某些字段以便相应的CPU控制单元可以安全地检索到它需要的信息。因此，TSS反映了CPU上的当前进程的特权级，但不必为没有在运行的进程保留TSS。

每个TSS有它自己8字节的任务状态段描述符。这个描述符包括指向TSS起始地址的32位Base字段，20位Limit字段。TSSD的S标志被清0，以表示相应的TSS是系统段的事实。

Type字段置为11或9以表示这个段实际上是TSS。在Intel的原始设计中，系统中的每个进程都应当指向自己的TSS；Type字段的第二个有效位叫做Busy位；如果进程正由CPU执行，则该位置为1，否则置为0。在Linux的设计中，每个CPU只有一个TSS，因此，Busy位总置为1。

由linux创建的TSSD存放在全局描述符表中。GDT的基地址存放在每个CPU的gdtr寄存器中。每个CPU的tr寄存器包含相应TSS的TSSD选择符，也包括了两个隐藏了非编程字段；TSSD的Base字段和Limit字段。这样，处理器就能直接对TSS寻址而不用从GDT中检索TSS的地址。


#### Thread字段

在每次进程切换时，被替换进程的硬件上下文必须保存在别处。不能像Intel原始设计那样把它保存在TSS中，因为Linux为每个处理器而不是为每个进程使用TSS。

因此，每个进程描述符包含一个类型为thread_struct的thread字段，只要进程被切换出去，内核就把其硬件上下文保存在这个结构中。随后我们会看到，这个数据结构包含的字段涉及大部分CPU寄存器，但不包括诸如exa、ebx等等这些通用寄存器，它们的值保留在内核堆栈中。

#### 执行进程切换

进程切换可能只发生在精心定义的点：schedule()函数（《深入理解Linux内核（第三版）》第七章有详细讨论）。这里，我们仅关注内核如何执行一个进程切换。

从本质上说，每个进程切换由两步组成：  
  切换页全局目录以安装一个新的地址空间；将在第九章（《深入理解Linux内核（第三版）》）描述这一步。  
  切换内核态堆栈和硬件上下文，因为硬件上下文提供了内核执行新进程所需要的所有信息，包含CPU寄存器。  

我们又一次假定prev指向被替换进程的描述符，而next指向被激活进程的描述符。prev和next是schedule()函数的局部变量。

#### switch_to宏

进程切换的第二步由switch_to宏执行。它是内核中与硬件关系最密切的例程之一，要理解它到低做了些什么我们必须下些功夫。

首先，该宏有三个参数，它们是prev,next和last。你可能很容易猜到prev和next的作用：它们仅是局部变量prev和next的占位符，即它们是输入参数，分别表示被替换进程和新进程描述符的地址在内存中的位置。

那第三个参数last呢？在任何进程切换中，涉及到三个进程而不是两个。假设内核决定暂停进程A而激活里程B。在schedule()函数中，prev指向A的描述符而next指向B的描述符。switch_to宏一但使A暂停，A的执行流就冻结。

随后，当内核想再次此激活A，就必须暂停另一个进程C，于是就要用prev指向C而next指向A来执行另一个swithch_to宏。当A恢复它的执行流时，就会找到它原来的内核栈，于是prev局部变量还是指向A的描述符而next指向B的描述符。此时，代表进程A执行的内核就失去了对C的任何引用。但是，事实表明这个引用对于完成进程切换是很有用的。

switch_to宏的最后一个参数是输出参数，它表示宏把进程C的描述符地址写在内存的什么位置了。在进程切换之前，宏把第一个输入参数prev表示的变量的内容存入CPU的eax寄存器。在完成进程切换，A已经恢复执行时，宏把CPU的eax寄存器的内容写入由第三个输出参数-------last所指示的A在内存中的位置。因为CPU寄存器不会在切换点发生变化，所以C的描述符地址也存在内存的这个位置。在schedule()执行过程中，参数last指向A的局部变量prev，所以prev被C的地址覆盖。

图3-7显示了进程A，B，C内核堆栈的内容以及eax寄存器的内容。必须注意的是：图中显示的是在被eax寄存器的内容覆盖以前的prev局部变量的值。

```
	#define switch_to(prev, next, last)                 \
	32do {                                  \
	33  /*                              \
	34   * Context-switching clobbers all registers, so we clobber  \
	35   * them explicitly, via unused output variables.        \
	36   * (EAX and EBP is not listed because EBP is saved/restored \
	37   * explicitly for wchan access and EAX is the return value of   \
	38   * __switch_to())                       \
	39   */                             \
	40  unsigned long ebx, ecx, edx, esi, edi;              \
	41                                  \
	42  asm volatile("pushfl\n\t"       /* save    flags */ \
	43           "pushl %%ebp\n\t"      /* save    EBP   */ \
	44           "movl %%esp,%[prev_sp]\n\t"    /* save    ESP   */ \
	45           "movl %[next_sp],%%esp\n\t"    /* restore ESP   */ \
	46           "movl $1f,%[prev_ip]\n\t"  /* save    EIP   */ \
	47           "pushl %[next_ip]\n\t" /* restore EIP   */ \
	48           __switch_canary                    \
	49           "jmp __switch_to\n"    /* regparm call  */ \
	50           "1:\t"                     \
	51           "popl %%ebp\n\t"       /* restore EBP   */ \
	52           "popfl\n"          /* restore flags */ \
	53                                  \
	54           /* output parameters */                \
	55           : [prev_sp] "=m" (prev->thread.sp),     \
	56             [prev_ip] "=m" (prev->thread.ip),     \
	57             "=a" (last),                 \
	58                                  \
	59             /* clobbered output registers: */        \
	60             "=b" (ebx), "=c" (ecx), "=d" (edx),      \
	61             "=S" (esi), "=D" (edi)               \
	62                                      \
	63             __switch_canary_oparam               \
	64                                  \
	65             /* input parameters: */              \
	66           : [next_sp]  "m" (next->thread.sp),     \
	67             [next_ip]  "m" (next->thread.ip),     \
	68                                      \
	69             /* regparm parameters for __switch_to(): */  \
	70             [prev]     "a" (prev),               \
	71             [next]     "d" (next)                \
	72                                  \
	73             __switch_canary_iparam               \
	74                                  \
	75           : /* reloaded segment registers */         \
	76          "memory");                  \
	77} while (0)
	78
```
由于switch_to宏采用扩展的内联汇编语言编码，所以可读性比较差：实际上这段代码通过特殊位置记数法使用寄存器，而实际使用的通用寄存器由编译器自由选择。我们将采用标准汇编语言而不是麻烦的内联汇编语言来描述switch_to宏在80x86微处理器上所完成的典型工作。

  在eax和edx寄存器中分别保存prev和next的值。
```
	movl prev ,%eax
	movl next ,%edx
```
  把eflags和ebp寄存器的内容保存在prev内核栈中。必須保存它们的原因是编译器认为在switch_to结束之前它们的值应当保持不变。
```
	pushf1
	push %ebp
```
  把esp的内容保存到prev->thread.esp中以使该字段指向prev内核栈的栈顶：
```
	movl %esp, 484(%eax)
```
  把next->thread.esp装入esp.此时，内核开始在next的内核栈上操作，因此这条指令实际上完成了从prev到next的切换。由于进程描述符的地址和内核栈的地址紧挨着，所以改变内核栈意味着改变进程。
```
	movl 484(%edx),%esp
```
  把标记为1的地址存入prev->thread.eip。当被替换的进程重新恢复执行时，进程执行被标记为1的那条指令：
```
	movl $lf, 480(%eax)
```
  宏把next->thread.eip的值压入next的内核栈。
```
	push1 480(%edx)
```
  跳到`__switch_to()` 函数
```
	jmp __switch_to
```
  这里被进程B替换的进程A再次获得CPU；它执行一些保存eflags和ebp寄存器内容的指令，这两条指令的第一条指令被标记为1。

  拷贝eax寄存器的内容到switch_to宏的第三个参数lash标识的内存区域中：
```
	movl  %eax, last
```
正如以前讨论的，eax寄存器指向刚被替换的进程描述符。


#### `__switch_to()`函数

`__switch_to()`函数执行大多数开始于switch_to()宏的进程切换。这个函数作用于prev_p和next_p参数，这两个参数表示前一个进程和新进程。这个函数的调用不同于一般函数的调用，因为`__switch_to()`从eax和edx取参数prev_p和next_p，而不像大多数函数一样从栈中取参数。为了强迫函数从寄存器取它的参数，内核利用`__attribute__`和regparm关键字，这两个关键字是C语言非标准的扩展名，由gcc编译程序实现。在include/asm-i386/system.h头文件中，`__switch_to()`函数的声明如下：
```
	__switch_to(structtask_struct *prev_p,struct tast_struct *next_p)__attribute_(regparm(2));
```
函数执行的步骤如下：  
  1、执行由`__unlazy_fpu()`宏产生的代码，以有选择地保存prev_p进程的FPU、MMX及XMM寄存器的内容。
```
	__unlazy_fpu(prev_p);
```
  2、执行smp_processor_id()宏获得本地(local)CPU的下标，即执行代码的CPU。该宏从当前进程的thread_info结构的cpu字段获得下标将它保存到cpu局部变量。  

  3、把next_p->thread.esp0装入对应于本地CPU的TSS的esp0字段；将在通过sysenter指令发生系统调用一节看到，以后任何由sysenter汇编指令产生的从用户态到内核态的特权级转换将把这个地址拷贝到esp寄存器中：
```
	init_tss[cpu].esp0= next_p->thread.esp0;
```

  4、把next_p进程使用的线程局部存储段装入本地CPU的全局描述符表；三个段选择符保存在进程描述符内的tls_array数组中
```
	cpu_gdt_table[cpu][6]= next_p->thread.tls_array[0];
	cpu_gdt_table[cpu][7]= next_p->thread.tls_array[1];
	cpu_gdt_table[cpu][8]= next_p->thread.tls_array[2];
```

  5、把fs和gs段寄存器的内容分别存放在prev_p->thread.fs和prev_p->thread.gs中，对应的汇编语言指令是：
```
	movl%fs,40(%esi)
	movl%gs,44(%esi)
```

  6、如果fs或gs段寄存器已经被prev_p或next_p进程中的任意一个使用，则将next_p进程的thread_struct描述符中保存的值装入这些寄存器中。这一步在逻辑上补充了前一步中执行的操作。主要的汇编语言指令如下：
```
	movl40(%ebx),%fs
	movl44(%edb),%gs
```

  7、ebx寄存器指向next_p->thread结构。代码实际上更复杂，因为当它检测到一个无效的段寄存器值时，CPU可能产生一个异常。

  8、用next_p->thread.debugreg数组的内容装载dr0,...,dr7中的6个调试寄存器。只有在next_p被挂起时正在使用调试寄存器，这种操作才能进行。这些寄存器不需要被保存，因为只有当一个调试器想要监控prev时prev_p->thread.debugreg才会修改。
```
	if(next_p->thread.debugreg[7]){
	loaddebug(&next_p->thread,0);
	loaddebug(&next_p->thread,1);
	loaddebug(&next_p->thread,2);
	loaddebug(&next_p->thread,3);
	loaddebug(&next_p->thread,6);
	loaddebug(&next_p->thread,7);
```

  8、如果必要，更新TSS中的I/O位图。当next_p或prev_p有其自己的定制I/O权限位图时必须这么做：
```
	if(prev_p->thread.io_bitmap_ptr|| next_p->thread.io_bitmap_ptr )
	handle_io_bitmap(&next_p->thread,&init_tss[cpu]);
```

因为进程很修改I/O权限位图，所以该位图在“懒”模式中被处理；当且仅当一个进程在当前时间片内实际访问I/O端口时，真实位图才被拷贝到本地CPU的TSS中。进程的定制I/O权限位图被保存在thread_info结构的io_bitmap_ptr字段指向的缓冲区中。handle_io_bitmap()函数为next_p进程设置本地CPU使用的TSS的in_bitmap字段如下：  
  (a)如果next_p进程不拥有自己的I/O权限位图，则TSS的io_bitmap字段被设为0x8000.  
  (b) 如果next_p进程拥有自己的I/O权限位图，则TSS的io_bitmap字段被设为0x9000。  

TSS的io_bitmap字段应当包含一个在TSS中的偏移量，其中存放实际位图。无论何时用户态进程试图访问一个I/O端口，0x8000和0x9000指向TSS界限之外并将因此引起”Generalprotection”异常。do_general_protection()异常处理程序将检查保存在io_bitmap字段的值：如果是0x8000，函数发送一个SIGSEGV信号给用户态进程；如果是0x9000，函数把进程位图拷贝拷贝到本地CPU的TSS中，把io_bitmap字段为实际位图的偏移(104)，并强制再一次执行有缺陷的汇编指令。

  9、终止。
`__switch_to()`函数通过使用下列声明结束：
```
	return prev_p;
```
  由编译器产生的相应汇编语言指令是：
```
	movl %edl,%eax
	ret
```
  prev_p参数被拷贝到eax，因为缺省情况下任何C函数的返回值被传递给eax寄存器。注意eax的值因此在调用`__switch_to()`的过程中被保护起来；这非常重要，因为调用switch_to宏时会假定eax总是用来存放被替换的进程描述符的地址。

  汇编语言指令ret把栈顶保存的返回地址装入eip程序计数器。不过，通过简单地跳转到`__switch_to()`函数来调用该函数。因此，ret汇编指令在栈中找到标号为1的指令的地址，其中标号为1的地址是由switch_to()宏推入栈中的。如果因为next_p第一次执行而以前从未被挂起，`__switch_to()`就找到ret_from_fork()函数的起始地址。


