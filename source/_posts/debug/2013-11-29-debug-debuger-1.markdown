---
layout: post
title: "调试器工作原理之一——基础篇"
date: 2013-11-29 09:33:00 +0800
comments: false
categories:
- 2013
- 2013~11
- debug
- debug~base
tags:
---
英文原文：[Eli Bendersky](http://eli.thegreenplace.net/2011/01/23/how-debuggers-work-part-1/)  编译：[陈舸](http://blog.jobbole.com/23463/)  
调试器工作原理之一——基础篇  
[调试器工作原理之二——实现断点](/blog/2013/11/29/debug-debuger-2/)  
[调试器工作原理之三——调试信息](/blog/2013/11/29/debug-debuger-3/)  

  本文是一系列探究调试器工作原理的文章的第一篇。我还不确定这个系列需要包括多少篇文章以及它们所涵盖的主题，但我打算从基础知识开始说起。
#### 关于本文
  我打算在这篇文章中介绍关于Linux下的调试器实现的主要组成部分——ptrace系统调用。本文中出现的代码都在32位的Ubuntu系统上开发。请注意，这里出现的代码是同平台紧密相关的，但移植到别的平台上应该不会太难。

#### 动机
 要想理解我们究竟要做什么，试着想象一下调试器是如何工作的。调试器可以启动某些进程，然后对其进行调试，或者 将自己本身关联到一个已存在的进程之上。它可以单步运行代码，设置断点然后运行程序，检查变量的值以及跟踪调用栈。许多调试器已经拥有了一些高级特性，比 如执行表达式并在被调试进程的地址空间中调用函数，甚至可以直接修改进程的代码并观察修改后的程序行为。

  尽管现代的调试器都是复杂的大型程序，但令人惊讶的是构建调试器的基础确是如此的简单。调试器只用到了几个由操作系统以及编译器/链接器提供的基础服务，剩下的仅仅就是简单的编程问题了。（可查阅维基百科中关于这个词条的解释，作者是在反讽）

#### Linux下的调试——ptrace
  Linux下调试器拥有一个瑞士军刀般的工具，这就是ptrace系统调用。这是一个功能众多且相当复杂的工 具，能允许一个进程控制另一个进程的运行，而且可以监视和渗入到进程内部。ptrace本身需要一本中等篇幅的书才能对其进行完整的解释，这就是为什么我 只打算通过例子把重点放在它的实际用途上。让我们继续深入探寻。
 
#### 遍历进程的代码
  我现在要写一个在“跟踪”模式下运行的进程的例子，这里我们要单步遍历这个进程的代码——由CPU所执行的机器 码（汇编指令）。我会在这里给出例子代码，解释每个部分，本文结尾处你可以通过链接下载一份完整的C程序文件，可以自行编译执行并研究。从高层设计来说， 我们要写一个程序，它产生一个子进程用来执行一个用户指定的命令，而父进程跟踪这个子进程。首先，main函数是这样的：
```
	int main(int argc, char** argv)
	{
		pid_t child_pid;
	 
		if (argc < 2) {
			fprintf(stderr, "Expected a program name as argument\n");
			return -1;
		}
	 
		child_pid = fork();
		if (child_pid == 0)
			run_target(argv[1]);
		else if (child_pid > 0)
			run_debugger(child_pid);
		else {
			perror("fork");
			return -1;
		}
	 
		return 0;
	}
```
  代码相当简单，我们通过fork产生一个新的子进程。随后的if语句块处理子进程（这里称为“目标进程”），而else if语句块处理父进程（这里称为“调试器”）。下面是目标进程：
```
	void run_target(const char* programname)
	{
		procmsg("target started. will run '%s'\n", programname);
	 
		/* Allow tracing of this process */
		if (ptrace(PTRACE_TRACEME, 0, 0, 0) < 0) {
			perror("ptrace");
			return;
		}
	 
		/* Replace this process's image with the given program */
		execl(programname, programname, 0);
	}
```
这部分最有意思的地方在ptrace调用。ptrace的原型是（在sys/ptrace.h）：
```
	long ptrace(enum __ptrace_request request,  pid_t pid, void *addr,  void *data);
```
  第一个参数是request，可以是预定义的以PTRACE_打头的常量值。第二个参数指定了进程id，第三以及第四个参数是地址和指向数据的指 针，用来对内存做操作。上面代码段中的ptrace调用使用了PTRACE_TRACEME请求，这表示这个子进程要求操作系统内核允许它的父进程对其跟 踪。这个请求在man手册中解释的非常清楚：  
  “表明这个进程由它的父进程来跟踪。任何发给这个进程的信号（除了SIGKILL）将导致该进程停止运行，而它的父进程会通过wait()获得通知。另外，该进程之后所有对exec()的调用都将使操作系统产生一个SIGTRAP信号发送给它，这让父进程有机会在新程序开始执行之前获得对子进程的控制权。如果不希望由父进程来跟踪的话，那就不应该使用这个请求。（pid、addr、data被忽略）”

  我已经把这个例子中我们感兴趣的地方高亮显示了。注意，run_target在ptrace调用之后紧接着做的是通过execl来调用我们指定的程 序。这里就会像我们高亮显示的部分所解释的那样，操作系统内核会在子进程开始执行execl中指定的程序之前停止该进程，并发送一个信号给父进程。
因此，是时候看看父进程需要做些什么了：
```
	void run_debugger(pid_t child_pid)
	{
		int wait_status;
		unsigned icounter = 0;
		procmsg("debugger started\n");
	 
		/* Wait for child to stop on its first instruction */
		wait(&wait_status);
	 
		while (WIFSTOPPED(wait_status)) {
			icounter++;
			/* Make the child execute another instruction */
			if (ptrace(PTRACE_SINGLESTEP, child_pid, 0, 0) < 0) {
				perror("ptrace");
				return;
			}
	 
			/* Wait for child to stop on its next instruction */
			wait(&wait_status);
		}
	 
		procmsg("the child executed %u instructions\n", icounter);
	}
```
  通过上面的代码我们可以回顾一下，一旦子进程开始执行exec调用，它就会停止然后接收到一个SIGTRAP信号。父进程通过第一个wait调用正 在等待这个事件发生。一旦子进程停止（如果子进程由于发送的信号而停止运行，WIFSTOPPED就返回true），父进程就去检查这个事件。

  父进程接下来要做的是本文中最有意思的地方。父进程通过PTRACE_SINGLESTEP以及子进程的id号来调用ptrace。这么做是告诉操 作系统——请重新启动子进程，但当子进程执行了下一条指令后再将其停止。然后父进程再次等待子进程的停止，整个循环继续得以执行。当从wait中得到的不 是关于子进程停止的信号时，循环结束。在正常运行这个跟踪程序时，会得到子进程正常退出（WIFEXITED会返回true）的信号。

  icounter会统计子进程执行的指令数量。因此我们这个简单的例子实际上还是做了点有用的事情——通过在命令行上指定一个程序名，我们的例子会执行这个指定的程序，然后统计出从开始到结束该程序执行过的CPU指令总数。让我们看看实际运行的情况。
 
#### 实际测试
我编译了下面这个简单的程序，然后在我们的跟踪程序下执行：
```
	#include <stdio.h>
	int main()
	{
		printf(“Hello, world!\n”);
		return 0;
	}
```
  令我惊讶的是，我们的跟踪程序运行了很长的时间然后报告显示一共有超过100000条指令得到了执行。仅仅只是一个简单的printf调用，为什么 会这样？答案非常有意思。默认情况下，Linux中的gcc编译器会动态链接到C运行时库。这意味着任何程序在运行时首先要做的事情是加载动态库。这需要 很多代码实现——记住，我们这个简单的跟踪程序会针对每一条被执行的指令计数，不仅仅是main函数，而是整个进程。

  因此，当我采用-static标志静态链接这个测试程序时（注意到可执行文件因此增加了500KB的大小，因为它静态链接了C运行时库），我们的跟 踪程序报告显示只有7000条左右的指令被执行了。这还是非常多，但如果你了解到libc的初始化工作仍然先于main的执行，而清理工作会在main之 后执行，那么这就完全说得通了。而且，printf也是一个复杂的函数。

  我们还是不满足于此，我希望能看到一些可检测的东西，例如我可以从整体上看到每一条需要被执行的指令是什么。这一点我们可以通过汇编代码来得到。因此我把这个“Hello，world”程序汇编（gcc -S）为如下的汇编码：
```
	section	.text
		; The _start symbol must be declared for the linker (ld)
		global _start
	 
	_start:
	 
		; Prepare arguments for the sys_write system call:
		;   - eax: system call number (sys_write)
		;   - ebx: file descriptor (stdout)
		;   - ecx: pointer to string
		;   - edx: string length
		mov	edx, len
		mov	ecx, msg
		mov	ebx, 1
		mov	eax, 4
	 
		; Execute the sys_write system call
		int	0x80
	 
		; Execute sys_exit
		mov	eax, 1
		int	0x80
	 
	section   .data
	msg db	'Hello, world!', 0xa
	len equ	$ - msg
```
这就足够了。现在跟踪程序会报告有7条指令得到了执行，我可以很容易地从汇编代码来验证这一点。
 
#### 深入指令流
汇编码程序得以让我为大家介绍ptrace的另一个强大的功能——详细检查被跟踪进程的状态。下面是run_debugger函数的另一个版本：
```
	void run_debugger(pid_t child_pid)
	{
		int wait_status;
		unsigned icounter = 0;
		procmsg("debugger started\n");
	 
		/* Wait for child to stop on its first instruction */
		wait(&wait_status);
	 
		while (WIFSTOPPED(wait_status)) {
			icounter++;
			struct user_regs_struct regs;
			ptrace(PTRACE_GETREGS, child_pid, 0, ®s);
			unsigned instr = ptrace(PTRACE_PEEKTEXT, child_pid, regs.eip, 0);
	 
			procmsg("icounter = %u.  EIP = 0x%08x.  instr = 0x%08x\n",
						icounter, regs.eip, instr);
	 
			/* Make the child execute another instruction */
			if (ptrace(PTRACE_SINGLESTEP, child_pid, 0, 0) < 0) {
				perror("ptrace");
				return;
			}
	 
			/* Wait for child to stop on its next instruction */
			wait(&wait_status);
		}
	 
		procmsg("the child executed %u instructions\n", icounter);
	}
```
  同前个版本相比，唯一的不同之处在于while循环的开始几行。这里有两个新的ptrace调用。第一个读取进程的寄存器值到一个结构体中。结构体 user_regs_struct定义在sys/user.h中。这儿有个有趣的地方——如果你打开这个头文件看看，靠近文件顶端的地方有一条这样的注 释：  
1  
/* 本文件的唯一目的是为GDB，且只为GDB所用。对于这个文件，不要看的太多。除了GDB以外不要用于任何其他目的，除非你知道你正在做什么。*/  
现在，我不知道你是怎么想的，但我感觉我们正处于正确的跑道上。无论如何，回到我们的例子上来。一旦我们将所有的寄存器值获取到regs中，我们就 可以通过PTRACE_PEEKTEXT标志以及将regs.eip（x86架构上的扩展指令指针）做参数传入ptrace来调用。我们所得到的就是指 令。让我们在汇编代码上运行这个新版的跟踪程序。  
```
$ simple_tracer traced_helloworld
[5700] debugger started
[5701] target started. will run 'traced_helloworld'
[5700] icounter = 1.  EIP = 0x08048080.  instr = 0x00000eba
[5700] icounter = 2.  EIP = 0x08048085.  instr = 0x0490a0b9
[5700] icounter = 3.  EIP = 0x0804808a.  instr = 0x000001bb
[5700] icounter = 4.  EIP = 0x0804808f.  instr = 0x000004b8
[5700] icounter = 5.  EIP = 0x08048094.  instr = 0x01b880cd
Hello, world!
[5700] icounter = 6.  EIP = 0x08048096.  instr = 0x000001b8
[5700] icounter = 7.  EIP = 0x0804809b.  instr = 0x000080cd
[5700] the child executed 7 instructions
```
OK，所以现在除了icounter以外，我们还能看到指令指针以及每一步的指令。如何验证这是否正确呢？可以通过在可执行文件上执行objdump –d来实现：
```
$ objdump -d traced_helloworld
 
traced_helloworld:	file format elf32-i386
 
Disassembly of section .text:
 
08048080 <.text>:
 8048080:	ba 0e 00 00 00		mov    $0xe,%edx
 8048085:	b9 a0 90 04 08		mov    $0x80490a0,%ecx
 804808a:	bb 01 00 00 00		mov    $0x1,%ebx
 804808f:	b8 04 00 00 00		mov    $0x4,%eax
 8048094:	cd 80				int    $0x80
 8048096:	b8 01 00 00 00		mov    $0x1,%eax
 804809b:	cd 80				int    $0x80
```
用这份输出对比我们的跟踪程序输出，应该很容易观察到相同的地方。
 
#### 关联到运行中的进程上
你已经知道了调试器也可以关联到已经处于运行状态的进程上。看到这里，你应该不会感到惊讶，这也是通过ptrace来实现的。这需要通过 PTRACE_ATTACH请求。这里我不会给出一段样例代码，因为通过我们已经看到的代码，这应该很容易实现。基于教学的目的，这里采用的方法更为便捷 （因为我们可以在子进程刚启动时立刻将它停止）。
 
#### 代码
本文给出的这个简单的跟踪程序的完整代码（更高级一点，可以将具体指令打印出来）可以在这里找到。程序通过-Wall –pedantic –std=c99编译选项在4.4版的gcc上编译。
 
#### 结论及下一步要做的
诚然，本文并没有涵盖太多的内容——我们离一个真正可用的调试器还差的很远。但是，我希望这篇文章至少已经揭开了调试过程的神秘面纱。ptrace是一个拥有许多功能的系统调用，目前我们只展示了其中少数几种功能。
能够单步执行代码是很有用处的，但作用有限。以“Hello， world”为例，要到达main函数，需要先遍历好几千条初始化C运行时库的指令。这就不太方便了。我们所希望的理想方案是可以在main函数入口处设 置一个断点，从断点处开始单步执行。下一篇文章中我将向您展示该如何实现断点机制。
 
#### 参考文献
写作本文时我发现下面这些文章很有帮助：  
[Playing with ptrace, Part I](http://www.linuxjournal.com/article/6100?page=0,1)  
[Process tracing using ptrace](http://linuxgazette.net/81/sandeep.html)  
[How debugger works](http://www.alexonlinux.com/how-debugger-works)  

