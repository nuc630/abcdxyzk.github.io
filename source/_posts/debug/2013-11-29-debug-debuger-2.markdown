---
layout: post
title: "调试器工作原理之二——实现断点"
date: 2013-11-29 09:34:00 +0800
comments: false
categories:
- 2013
- 2013~11
- debug
- debug~base
tags:
---
[调试器工作原理之一——基础篇](/blog/2013/11/29/debug-debuger-1/)  
调试器工作原理之二——实现断点  
[调试器工作原理之三——调试信息](/blog/2013/11/29/debug-debuger-3/)  

#### 本文的主要内容
  这里我将说明调试器中的断点机制是如何实现的。断点机制是调试器的两大主要支柱之一 ——另一个是在被调试进程的内存空间中查看变量的值。我们已经在第一篇文章中稍微涉及到了一些监视被调试进程的知识，但断点机制仍然还是个迷。阅读完本文之后，这将不再是什么秘密了。

#### 软中断
  要在x86体系结构上实现断点我们要用到软中断（也称为“陷阱”trap）。在我们深入细节之前，我想先大致解释一下中断和陷阱的概念。

  CPU有一个单独的执行序列，会一条指令一条指令的顺序执行。要处理类似IO或者硬件时钟这样的异步事件时CPU就要用到中断。硬件中断通常是一个 专门的电信号，连接到一个特殊的“响应电路”上。这个电路会感知中断的到来，然后会使CPU停止当前的执行流，保存当前的状态，然后跳转到一个预定义的地 址处去执行，这个地址上会有一个中断处理例程。当中断处理例程完成它的工作后，CPU就从之前停止的地方恢复执行。

  软中断的原理类似，但实际上有一点不同。CPU支持特殊的指令允许通过软件来模拟一个中断。当执行到这个指令时，CPU将其当做一个中断——停止当 前正常的执行流，保存状态然后跳转到一个处理例程中执行。这种“陷阱”让许多现代的操作系统得以有效完成很多复杂任务（任务调度、虚拟内存、内存保护、调 试等）。
一些编程错误（比如除0操作）也被CPU当做一个“陷阱”，通常被认为是“异常”。这里软中断同硬件中断之间的界限就变得模糊了，因为这里很难说这种异常到底是硬件中断还是软中断引起的。我有些偏离主题了，让我们回到关于断点的讨论上来。

#### 关于int 3指令
  看过前一节后，现在我可以简单地说断点就是通过CPU的特殊指令——int 3来实现的。int就是x86体系结构中的“陷阱指令”——对预定义的中断处理例程的调用。x86支持int指令带有一个8位的操作数，用来指定所发生的 中断号。因此，理论上可以支持256种“陷阱”。前32个由CPU自己保留，这里第3号就是我们感兴趣的——称为“trap to debugger”。

  不多说了，我这里就引用“圣经”中的原话吧（这里的圣经就是Intel’s Architecture software developer’s manual, volume2A）：  
  “INT 3指令产生一个特殊的单字节操作码（CC），这是用来调用调试异常处理例程的。（这个单字节形式非常有价值，因为这样可以通过一个断点来替换掉任何指令的第一个字节，包括其它的单字节指令也是一样，而不会覆盖到其它的操作码）。”

上面这段话非常重要，但现在解释它还是太早，我们稍后再来看。

#### 使用int 3指令
  是的，懂得事物背后的原理是很棒的，但是这到底意味着什么？我们该如何使用int 3来实现断点机制？套用常见的编程问答中出现的对话——请用代码说话！
实际上这真的非常简单。一旦你的进程执行到int 3指令时，操作系统就将它暂停。在Linux上（本文关注的是Linux平台），这会给该进程发送一个SIGTRAP信号。

  这就是全部——真的！现在回顾一下本系列文章的第一篇，跟踪（调试器）进程可以获得所有其子进程（或者被关联到的进程）所得到信号的通知，现在你知道我们该做什么了吧？
  就是这样，再没有什么计算机体系结构方面的东东了，该写代码了。

#### 手动设定断点
现在我要展示如何在程序中设定断点。用于这个示例的目标程序如下：
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
	mov	edx, len1
	mov	ecx, msg1
	mov	ebx, 1
	mov	eax, 4
 
	; Execute the sys_write system call
	int	0x80
 
	; Now print the other message
	mov	edx, len2
	mov	ecx, msg2
	mov	ebx, 1
	mov	eax, 4
	int	0x80
 
	; Execute sys_exit
	mov	eax, 1
	int	0x80
 
section	.data
 
msg1	db	'Hello,', 0xa
len1	equ	$ - msg1
msg2	db	'world!', 0xa
len2	equ	$ - msg2
```
  我现在使用的是汇编语言，这是为了避免当使用C语言时涉及到的编译和符号的问题。上面列出的程序功能就是在一行中打印“Hello，”，然后在下一行中打印“world！”。这个例子与上一篇文章中用到的例子很相似。

  我希望设定的断点位置应该在第一条打印之后，但恰好在第二条打印之前。我们就让断点打在第一个int 0×80指令之后吧，也就是mov edx, len2。首先，我需要知道这条指令对应的地址是什么。运行objdump –d：
```
traced_printer2:	file format elf32-i386
 
Sections:
Idx	Name	Size		VMA			LMA			File off	Algn
  0	.text	00000033	08048080	08048080	00000080	2**4
			CONTENTS,ALLOC,LOAD,READONLY,CODE
  1	.data	0000000e	080490b4	080490b4	000000b4  	2**2
			CONTENTS,ALLOC,LOAD,DATA
 
Disassembly of section .text:
 
08048080 <.text>:
 8048080:	ba 07 00 00 00		mov		$0x7,%edx
 8048085:	b9 b4 90 04 08		mov		$0x80490b4,%ecx
 804808a:	bb 01 00 00 00		mov		$0x1,%ebx
 804808f:	b8 04 00 00 00		mov		$0x4,%eax
 8048094:	cd 80				int		$0x80
 8048096:	ba 07 00 00 00		mov		$0x7,%edx
 804809b:	b9 bb 90 04 08		mov		$0x80490bb,%ecx
 80480a0:	bb 01 00 00 00		mov		$0x1,%ebx
 80480a5:	b8 04 00 00 00		mov		$0x4,%eax
 80480aa:	cd 80				int		$0x80
 80480ac:	b8 01 00 00 00		mov		$0x1,%eax
 80480b1:	cd 80				int		$0x80
```
  通过上面的输出，我们知道要设定的断点地址是0×8048096。等等，真正的调试器不是像这样工作的，对吧？真正的调试器可以根据代码行数或者函 数名称来设定断点，而不是基于什么内存地址吧？非常正确。但是我们离那个标准还差的远——如果要像真正的调试器那样设定断点，我们还需要涵盖符号表以及调 试信息方面的知识，这需要用另一篇文章来说明。至于现在，我们还必须得通过内存地址来设定断点。

看到这里我真的很想再扯一点题外话，所以你有两个选择。如果你真的对于为什么地址是0×8048096，以及这代表什么意思非常感兴趣的话，接着看下一节。如果你对此毫无兴趣，只是想看看怎么设定断点，可以略过这一部分。

#### 题外话——进程地址空间以及入口点
  坦白的说，0×8048096本身并没有太大意义，这只不过是相对可执行镜像的代码段（text section）开始处的一个偏移量。如果你仔细看看前面objdump出来的结果，你会发现代码段的起始位置是0×08048080。这告诉了操作系统 要将代码段映射到进程虚拟地址空间的这个位置上。在Linux上，这些地址可以是绝对地址（比如，有的可执行镜像加载到内存中时是不可重定位的），因为在 虚拟内存系统中，每个进程都有自己独立的内存空间，并把整个32位的地址空间都看做是属于自己的（称为线性地址）。

如果我们通过readelf工具来检查可执行文件的ELF头，我们将得到如下输出：
```
$ readelf -h traced_printer2
ELF Header:
  Magic:   7f 45 4c 46 01 01 01 00 00 00 00 00 00 00 00 00
  Class:								ELF32
  Data:									2's complement, little endian
  Version:								1 (current)
  OS/ABI:								UNIX - System V
  ABI Version:							0
  Type:									EXEC (Executable file)
  Machine:								Intel 80386
  Version:								0x1
  Entry point address:					0x8048080
  Start of program headers:				52 (bytes into file)
  Start of section headers:				220 (bytes into file)
  Flags:								0x0
  Size of this header:					52 (bytes)
  Size of program headers:				32 (bytes)
  Number of program headers:			2
  Size of section headers:				40 (bytes)
  Number of section headers:			4
  Section header string table index:	3
```
  注意，ELF头的“entry point address”同样指向的是0×8048080。因此，如果我们把ELF文件中的这个部分解释给操作系统的话，就表示：  
1. 将代码段映射到地址0×8048080处  
2. 从入口点处开始执行——地址0×8048080  
  但是，为什么是0×8048080呢？它的出现是由于历史原因引起的。每个进程的地址空间的前128MB被保留给栈空间了（注：这一部分原因可参考 Linkers and Loaders）。128MB刚好是0×80000000，可执行镜像中的其他段可以从这里开始。0×8048080是Linux下的链接器ld所使用的 默认入口点。这个入口点可以通过传递参数-Ttext给ld来进行修改。

  因此，得到的结论是这个地址并没有什么特别的，我们可以自由地修改它。只要ELF可执行文件的结构正确且在ELF头中的入口点地址同程序代码段（text section）的实际起始地址相吻合就OK了。

#### 通过int 3指令在调试器中设定断点
  要在被调试进程中的某个目标地址上设定一个断点，调试器需要做下面两件事情：  
1. 保存目标地址上的数据  
2. 将目标地址上的第一个字节替换为int 3指令  
  然后，当调试器向操作系统请求开始运行进程时（通过前一篇文章中提到的PTRACE_CONT），进程最终一定会碰到int 3指令。此时进程停止，操作系统将发送一个信号。这时就是调试器再次出马的时候了，接收到一个其子进程（或被跟踪进程）停止的信号，然后调试器要做下面几 件事：  
1. 在目标地址上用原来的指令替换掉int 3  
2. 将被跟踪进程中的指令指针向后递减1。这么做是必须的，因为现在指令指针指向的是已经执行过的int 3之后的下一条指令。  
3. 由于进程此时仍然是停止的，用户可以同被调试进程进行某种形式的交互。这里调试器可以让你查看变量的值，检查调用栈等等。  
4. 当用户希望进程继续运行时，调试器负责将断点再次加到目标地址上（由于在第一步中断点已经被移除了），除非用户希望取消断点。  
  让我们看看这些步骤如何转化为实际的代码。我们将沿用第一篇文章中展示过的调试器“模版”（fork一个子进程，然后对其跟踪）。无论如何，本文结尾处会给出完整源码的链接。
```
/* Obtain and show child's instruction pointer */
ptrace(PTRACE_GETREGS, child_pid, 0, ®s);
procmsg("Child started. EIP = 0x%08x\n", regs.eip);
 
/* Look at the word at the address we're interested in */
unsigned addr = 0x8048096;
unsigned data = ptrace(PTRACE_PEEKTEXT, child_pid, (void*)addr, 0);
procmsg("Original data at 0x%08x: 0x%08x\n", addr, data);
```
这里调试器从被跟踪进程中获取到指令指针，然后检查当前位于地址0×8048096处的字长内容。运行本文前面列出的汇编码程序，将打印出：
```
[13028] Child started. EIP = 0x08048080
[13028] Original data at 0x08048096: 0x000007ba
```
目前为止一切顺利，下一步：
```
/* Write the trap instruction 'int 3' into the address */
unsigned data_with_trap = (data & 0xFFFFFF00) | 0xCC;
ptrace(PTRACE_POKETEXT, child_pid, (void*)addr, (void*)data_with_trap);
 
/* See what's there again... */
unsigned readback_data = ptrace(PTRACE_PEEKTEXT, child_pid, (void*)addr, 0);
procmsg("After trap, data at 0x%08x: 0x%08x\n", addr, readback_data);
```
注意看我们是如何将int 3指令插入到目标地址上的。这部分代码将打印出：
```
[13028] After trap, data at 0x08048096: 0x000007cc
```
再一次如同预计的那样——0xba被0xcc取代了。调试器现在运行子进程然后等待子进程在断点处停止住。
```
	/* Let the child run to the breakpoint and wait for it to
	** reach it
	*/
	ptrace(PTRACE_CONT, child_pid, 0, 0);
	 
	wait(&wait_status);
	if (WIFSTOPPED(wait_status)) {
		procmsg("Child got a signal: %s\n", strsignal(WSTOPSIG(wait_status)));
	}
	else {
		perror("wait");
		return;
	}
	 
	/* See where the child is now */
	ptrace(PTRACE_GETREGS, child_pid, 0, ®s);
	procmsg("Child stopped at EIP = 0x%08x\n", regs.eip);
```
这段代码打印出：
```
Hello,
[13028] Child got a signal: Trace/breakpoint trap
[13028] Child stopped at EIP = 0x08048097
```
注意，“Hello,”在断点之前打印出来了——同我们计划的一样。同时我们发现子进程已经停止运行了——就在这个单字节的陷阱指令执行之后。
```
/* Remove the breakpoint by restoring the previous data
** at the target address, and unwind the EIP back by 1 to
** let the CPU execute the original instruction that was
** there.
*/
ptrace(PTRACE_POKETEXT, child_pid, (void*)addr, (void*)data);
regs.eip -= 1;
ptrace(PTRACE_SETREGS, child_pid, 0, ®s);
 
/* The child can continue running now */
ptrace(PTRACE_CONT, child_pid, 0, 0);
```
这会使子进程打印出“world！”然后退出，同之前计划的一样。  
注意，我们这里并没有重新加载断点。这可以在单步模式下执行，然后将陷阱指令加回去，再做PTRACE_CONT就可以了。本文稍后介绍的debug库实现了这个功能。  

#### 更多关于int 3指令
  现在是回过头来说说int 3指令的好机会，以及解释一下Intel手册中对这条指令的奇怪说明。

“这个单字节形式非常有价值，因为这样可以通过一个断点来替换掉任何指令的第一个字节，包括其它的单字节指令也是一样，而不会覆盖到其它的操作码。”

  x86架构上的int指令占用2个字节——0xcd加上中断号。int 3的二进制形式可以被编码为cd 03，但这里有一个特殊的单字节指令0xcc以同样的作用而被保留。为什么要这样做呢？因为这允许我们在插入一个断点时覆盖到的指令不会多于一条。这很重 要，考虑下面的示例代码：
```
.. some code ..
	jz	foo
	dec	eax
foo:
	call	bar
	.. some	code ..
```
  假设我们要在dec eax上设定断点。这恰好是条单字节指令（操作码是0×48）。如果替换为断点的指令长度超过1字节，我们就被迫改写了接下来的下一条指令（call）， 这可能会产生一些完全非法的行为。考虑一下条件分支jz foo，这时进程可能不会在dec eax处停止下来（我们在此设定的断点，改写了原来的指令），而是直接执行了后面的非法指令。

  通过对int 3指令采用一个特殊的单字节编码就能解决这个问题。因为x86架构上指令最短的长度就是1字节，这样我们可以保证只有我们希望停止的那条指令被修改。

#### 封装细节
  前面几节中的示例代码展示了许多底层的细节，这些可以很容易地通过API进行封装。我已经做了一些封装，使其成为一个小型的调试库——debuglib。代码在本文末尾处可以下载。这里我只想介绍下它的用法，我们要开始调试C程序了。

#### 跟踪C程序
目前为止为了简单起见我把重点放在对汇编程序的跟踪上了。现在升一级来看看我们该如何跟踪一个C程序。  
其实事情并没有很大的不同——只是现在有点难以找到放置断点的位置。考虑如下这个简单的C程序:  
```
	#include <stdio.h>
	 
	void do_stuff()
	{
		printf("Hello, ");
	}
	 
	int main()
	{
		for (int i = 0; i < 4; ++i)
			do_stuff();
		printf("world!\n");
		return 0;
	}
```
假设我想在do_stuff的入口处设置一个断点。我将请出我们的老朋友objdump来反汇编可执行文件，但得到的输出太多。其实，查看text 段不太管用，因为这里面包含了大量的初始化C运行时库的代码，我目前对此并不感兴趣。所以，我们只需要在dump出来的结果里看do_stuff部分就好 了。
```
080483e4 <do_stuff>:
 80483e4:	55						push	%ebp
 80483e5:	89 e5					mov		%esp,%ebp
 80483e7:	83 ec 18				sub		$0x18,%esp
 80483ea:	c7 04 24 f0 84 04 08	movl	$0x80484f0,(%esp)
 80483f1:	e8 22 ff ff ff			call	8048318 <puts@plt>
 80483f6:	c9						leave
 80483f7:	c3						ret
```
好的，所以我们应该把断点设定在0x080483e4上，这是do_stuff的第一条指令。另外，由于这个函数是在循环体中调用的，我们希望在循 环全部结束前保留断点，让程序可以在每一轮循环中都在断点处停下。我将使用debuglib来简化代码编写。这里是完整的调试器函数：
```
	void run_debugger(pid_t child_pid)
	{
		procmsg("debugger started\n");
	 
		/* Wait for child to stop on its first instruction */
		wait(0);
		procmsg("child now at EIP = 0x%08x\n", get_child_eip(child_pid));
	 
		/* Create breakpoint and run to it*/
		debug_breakpoint* bp = create_breakpoint(child_pid, (void*)0x080483e4);
		procmsg("breakpoint created\n");
		ptrace(PTRACE_CONT, child_pid, 0, 0);
		wait(0);
	 
		/* Loop as long as the child didn't exit */
		while (1) {
			/* The child is stopped at a breakpoint here. Resume its
			** execution until it either exits or hits the
			** breakpoint again.
			*/
			procmsg("child stopped at breakpoint. EIP = 0x%08X\n", get_child_eip(child_pid));
			procmsg("resuming\n");
			int rc = resume_from_breakpoint(child_pid, bp);
	 
			if (rc == 0) {
				procmsg("child exited\n");
				break;
			}
			else if (rc == 1) {
				continue;
			}
			else {
				procmsg("unexpected: %d\n", rc);
				break;
			}
		}
	 
		cleanup_breakpoint(bp);
	}
```
我们不用手动修改EIP指针以及目标进程的内存空间，我们只需要通过create_breakpoint, resume_from_breakpoint以及cleanup_breakpoint来操作就可以了。我们来看看当跟踪这个简单的C程序后的打印输出：
```
$ bp_use_lib traced_c_loop
[13363] debugger started
[13364] target started. will run 'traced_c_loop'
[13363] child now at EIP = 0x00a37850
[13363] breakpoint created
[13363] child stopped at breakpoint. EIP = 0x080483E5
[13363] resuming
Hello,
[13363] child stopped at breakpoint. EIP = 0x080483E5
[13363] resuming
Hello,
[13363] child stopped at breakpoint. EIP = 0x080483E5
[13363] resuming
Hello,
[13363] child stopped at breakpoint. EIP = 0x080483E5
[13363] resuming
Hello,
world!
[13363] child exited
```
跟预计的情况一模一样！

#### 代码
这里是完整的源码。在文件夹中你会发现：  
debuglib.h以及debuglib.c——封装了调试器的一些内部工作。  
bp_manual.c —— 本文一开始介绍的“手动”式设定断点。用到了debuglib库中的一些样板代码。  
bp_use_lib.c—— 大部分代码用到了debuglib，这就是本文中用于说明跟踪一个C程序中的循环的示例代码。  

#### 结论及下一步要做的
我们已经涵盖了如何在调试器中实现断点机制。尽管实现细节根据操作系统的不同而有所区别，但只要你使用的是x86架构的处理器，那么一切变化都基于相同的主题——在我们希望停止的指令上将其替换为int 3。  
我敢肯定，有些读者就像我一样，对于通过指定原始地址来设定断点的做法不会感到很激动。我们更希望说“在do_stuff上停住”，甚至是“在do_stuff的这一行上停住”，然后调试器就能照办。在下一篇文章中，我将向您展示这是如何做到的。

