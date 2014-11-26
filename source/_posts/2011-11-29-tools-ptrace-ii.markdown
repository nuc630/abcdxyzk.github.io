---
layout: post
title: "Playing with ptrace, Part I — 玩转ptrace(二)"
date: 2011-11-29 19:23:00 +0800
comments: false
categories:
- 2011
- 2011~11
- language
- language~c
tags:
- koj
- judge
---
[本文地址](http://www.kgdb.info/gdb/playing_with_ptrace_part_ii/)

版权所有 © 转载时必须以链接形式注明作者和原始出处！
 
Playing with ptrace, Part II  
by Pradeep Padala p_padala@yahoo.com http://www.cise.ufl.edu/~ppadala  
Created 2002-11-01 02:00

翻译: Magic.D E-mail: adamgic@163.com

在第一部分中我们已经看到ptrace怎么获取子进程的系统调用以及改变系统调用的参数。在这篇文章中，我们将要研究如何在子进程中设置断点和往运行中的程序里插入代码。实际上调试器就是用这种方法来设置断点和执行调试句柄。与前面一样，这里的所有代码都是针对i386平台的。  
附着在进程上

在第一部分钟，我们使用ptrace(PTRACE_TRACEME, …)来跟踪一个子进程，如果你只是想要看进程是怎么进行系统调用和跟踪程序的，这个做法是不错的。但如果你要对运行中的进程进行调试，则需要使用 ptrace( PTRACE_ATTACH, ….)  

当 ptrace( PTRACE_ATTACH, …)在被调用的时候传入了子进程的pid时， 它大体是与ptrace( PTRACE_TRACEME, …)的行为相同的，它会向子进程发送SIGSTOP信号，于是我们可以察看和修改子进程，然后使用 ptrace( PTRACE_DETACH, …)来使子进程继续运行下去。  

下面是调试程序的一个简单例子
```
	int main()
	{
		int i;
		for(i = 0;i < 10; ++i) {
			printf("My counter: %d ", i);
			sleep(2);
		}
		return 0;
	}
```
将上面的代码保存为dummy2.c。按下面的方法编译运行：  
gcc -o dummy2 dummy2.c  
./dummy2 &

现在我们可以用下面的代码来附着到dummy2上。
```
	#include <sys/ptrace.h>
	#include <sys/types.h>
	#include <sys/wait.h>
	#include <unistd.h>
	#include <linux/user.h>   /* For user_regs_struct
								 etc. */
	int main(int argc, char *argv[])
	{
		pid_t traced_process;
		struct user_regs_struct regs;
		long ins;
		if(argc != 2) {
			printf("Usage: %s <pid to be traced>\n",
				argv[0], argv[1]);
			exit(1);
		}
		traced_process = atoi(argv[1]);
		ptrace(PTRACE_ATTACH, traced_process,
			NULL, NULL);
		wait(NULL);
		ptrace(PTRACE_GETREGS, traced_process,
			NULL, &regs);
		ins = ptrace(PTRACE_PEEKTEXT, traced_process,
			regs.eip, NULL);
		printf("EIP: %lx Instruction executed: %lx\n",
			regs.eip, ins);
		ptrace(PTRACE_DETACH, traced_process,
			NULL, NULL);
		return 0;
	}
```
上面的程序仅仅是附着在子进程上，等待它结束，并测量它的eip( 指令指针)然后释放子进程。
设置断点

调试器是怎么设置断点的呢？通常是将当前将要执行的指令替换成trap指令，于是被调试的程序就会在这里停滞，这时调试器就可以察看被调试程序的信息了。被调试程序恢复运行以后调试器会把原指令再放回来。这里是一个例子：
```
	#include <sys/ptrace.h>
	#include <sys/types.h>
	#include <sys/wait.h>
	#include <unistd.h>
	#include <linux/user.h>
	const int long_size = sizeof(long);
	void getdata(pid_t child, long addr, char *str, int len)
	{
		char *laddr;
		int i, j;
		union u {
			long val;
			char chars[long_size];
		} data;
		i = 0;
		j = len / long_size;
		laddr = str;
		while(i < j) {
			data.val = ptrace(PTRACE_PEEKDATA, child,
				addr + i * 4, NULL);
			memcpy(laddr, data.chars, long_size);
			++i;
			laddr += long_size;
		}
		j = len % long_size;
		if(j != 0) {
			data.val = ptrace(PTRACE_PEEKDATA, child,
				addr + i * 4, NULL);
			memcpy(laddr, data.chars, j);
		}
		str[len] = '\0';
	}
	void putdata(pid_t child, long addr, char *str, int len)
	{
		char *laddr;
		int i, j;
		union u {
			long val;
			char chars[long_size];
		} data;
		i = 0;
		j = len / long_size;
		laddr = str;
		while(i < j) {
			memcpy(data.chars, laddr, long_size);
			ptrace(PTRACE_POKEDATA, child,
				addr + i * 4, data.val);
			++i;
			laddr += long_size;
		}
		j = len % long_size;
		if(j != 0) {
			memcpy(data.chars, laddr, j);
			ptrace(PTRACE_POKEDATA, child,
				addr + i * 4, data.val);
		}
	}
	int main(int argc, char *argv[])
	{
		pid_t traced_process;
		struct user_regs_struct regs, newregs;
		long ins;
		/* int 0x80, int3 */
		char code[] = {0xcd,0x80,0xcc,0};
		char backup[4];
		if(argc != 2) {
			printf("Usage: %s <pid to be traced>\n",
				argv[0], argv[1]);
			exit(1);
		}
		traced_process = atoi(argv[1]);
		ptrace(PTRACE_ATTACH, traced_process,
			NULL, NULL);
		wait(NULL);
		ptrace(PTRACE_GETREGS, traced_process,
			NULL, &regs);
		/* Copy instructions into a backup variable */
		getdata(traced_process, regs.eip, backup, 3);
		/* Put the breakpoint */
		putdata(traced_process, regs.eip, code, 3);
		/* Let the process continue and execute
		   the int 3 instruction */
		ptrace(PTRACE_CONT, traced_process, NULL, NULL);
		wait(NULL);
		printf("The process stopped, putting back "
			"the original instructions\n");
		printf("Press <enter> to continue\n");
		getchar();
		putdata(traced_process, regs.eip, backup, 3);
		/* Setting the eip back to the original
		   instruction to let the process continue */
		ptrace(PTRACE_SETREGS, traced_process,
			NULL, &regs);
		ptrace(PTRACE_DETACH, traced_process,
			NULL, NULL);
		return 0;
	}
```
上面的程序将把三个byte的内容进行替换以执行trap指令，等被调试进程停滞以后，我们把原指令再替换回来并把eip修改为原来的值。下面的图中演示了指令的执行过程  
1. 进程停滞后  
2. 替换入trap指令  
3.断点成功，控制权交给了调试器  
4. 继续运行，将原指令替换回来并将eip复原  
在了解了断点的机制以后，往运行中的程序里面添加指令也不再是难事了，下面的代码会使原程序多出一个”hello world”的输出  

这时一个简单的”hello world”程序，当然为了我们的特殊需要作了点修改：
```
	void main()
	{
		__asm__("
			jmp forward
			backward:
				popl   %esi	# Get the address of
						# hello world string
				movl   $4, %eax	# Do write system call
				movl   $2, %ebx
				movl   %esi, %ecx
				movl   $12, %edx
				int	$0x80
				int3		# Breakpoint. Here the
						# program will stop and
						# give control back to
						# the parent
			forward:
				call   backward
				.string \"Hello World\\n\""
		);
	}
```
使用
gcc -o hello hello.c  
来编译它。  
在backward和forward之间的跳转是为了使程序能够找到”hello world” 字符串的地址。  
使用GDB我们可以得到上面那段程序的机器码。启动GDB,然后对程序进行反汇编：
```
(gdb) disassemble main
Dump of assembler code forfunction main:
0x80483e0<main>:	   push   %ebp
0x80483e1<main+1>:	 mov	%esp,%ebp
0x80483e3<main+3>:	 jmp	0x80483fa<forward>
End of assembler dump.
(gdb) disassemble forward
Dump of assembler code forfunction forward:
0x80483fa<forward>:	call   0x80483e5<backward>
0x80483ff<forward+5>:  dec	%eax
0x8048400<forward+6>:  gs
0x8048401<forward+7>:  insb   (%dx),%es:(%edi)
0x8048402<forward+8>:  insb   (%dx),%es:(%edi)
0x8048403<forward+9>:  outsl  %ds:(%esi),(%dx)
0x8048404<forward+10>: and	%dl,0x6f(%edi)
0x8048407<forward+13>: jb	 0x8048475
0x8048409<forward+15>: or	 %fs:(%eax),%al
0x804840c<forward+18>: mov	%ebp,%esp
0x804840e<forward+20>: pop	%ebp
0x804840f<forward+21>: ret
End of assembler dump.
(gdb) disassemble backward
Dump of assembler code forfunction backward:
0x80483e5<backward>:   pop	%esi
0x80483e6<backward+1>: mov	$0x4,%eax
0x80483eb<backward+6>: mov	$0x2,%ebx
0x80483f0<backward+11>:		mov	%esi,%ecx
0x80483f2<backward+13>:		mov	$0xc,%edx
0x80483f7<backward+18>:int	$0x80
0x80483f9<backward+20>:		int3
End of assembler dump.
```
我们需要使用从man+3到backward+20之间的字节码，总共41字节。使用GDB中的x命令来察看机器码。
```
(gdb) x/40bx main+3
<main+3>: eb 15 5e b8 04000000
<backward+6>: bb 0200000089 f1 ba
<backward+14>: 0c 000000 cd 80 cc
<forward+1>: e6 ff ff ff 4865 6c 6c
<forward+9>:6f20576f72 6c 64 0a
```
已经有了我们想要执行的指令，还等什么呢？只管把它们根前面那个例子一样插入到被调试程序中去！

代码：
```
	int main(int argc,char*argv[])
	{
		pid_t traced_process;
		struct user_regs_struct regs, newregs;
		long ins;
		int len =41;
		char insertcode[]=
			"\xeb\x15\x5e\xb8\x04\x00"
			"\x00\x00\xbb\x02\x00\x00\x00\x89\xf1\xba"
			"\x0c\x00\x00\x00\xcd\x80\xcc\xe8\xe6\xff"
			"\xff\xff\x48\x65\x6c\x6c\x6f\x20\x57\x6f"
			"\x72\x6c\x64\x0a\x00";
		char backup[len];
		if(argc != 2) {
			printf("Usage: %s <pid to be traced>\n",
				argv[0], argv[1]);
			exit(1);
		}
		traced_process = atoi(argv[1]);
		ptrace(PTRACE_ATTACH, traced_process,
			NULL, NULL);
		wait(NULL);
		ptrace(PTRACE_GETREGS, traced_process,
			NULL,&regs);
		getdata(traced_process, regs.eip, backup, len);
		putdata(traced_process, regs.eip,
			insertcode, len);
		ptrace(PTRACE_SETREGS, traced_process,
			NULL,&regs);
		ptrace(PTRACE_CONT, traced_process,
			NULL, NULL);
		wait(NULL);
		printf("The process stopped, Putting back the original instructions\n");
		putdata(traced_process, regs.eip, backup, len);
		ptrace(PTRACE_SETREGS, traced_process,
			NULL,&regs);
		printf("Letting it continue with original flow\n");
		ptrace(PTRACE_DETACH, traced_process,
			NULL, NULL);
		return0;
	}
```
将代码插入到自由空间

在前面的例子中我们将代码直接插入到了正在执行的指令流中，然而，调试器可能会被这种行为弄糊涂，所以我们决定把指令插入到进程中的自由空间中去。通过察看/proc/pid/maps可以知道这个进程中自由空间的分布。接下来这个函数可以找到这个内存映射的起始点：
```
	long freespaceaddr(pid_t pid)
	{
		FILE *fp;
		char filename[30];
		char line[85];
		long addr;
		char str[20];
		sprintf(filename,"/proc/%d/maps", pid);
		fp = fopen(filename,"r");
		if(fp == NULL)
			exit(1);
		while(fgets(line,85, fp) != NULL) {
			sscanf(line,"%lx-%*lx %*s %*s %s",&addr,
				str, str, str, str);
			if(strcmp(str,"00:00")==0)
				break;
		}
		fclose(fp);
		return addr;
	}
```
在/proc/pid/maps中的每一行都对应了进程中一段内存区域。主函数的代码如下：
```
	int main(int argc,char*argv[])
	{
		pid_t traced_process;
		struct user_regs_struct oldregs, regs;
		long ins;
		int len =41;
		char insertcode[]=
			"\xeb\x15\x5e\xb8\x04\x00"
			"\x00\x00\xbb\x02\x00\x00\x00\x89\xf1\xba"
			"\x0c\x00\x00\x00\xcd\x80\xcc\xe8\xe6\xff"
			"\xff\xff\x48\x65\x6c\x6c\x6f\x20\x57\x6f"
			"\x72\x6c\x64\x0a\x00";
		char backup[len];
		long addr;
		if(argc !=2){
			printf("Usage: %s <pid to be traced>\n",
				argv[0], argv[1]);
				exit(1);
		}
		traced_process = atoi(argv[1]);
		ptrace(PTRACE_ATTACH, traced_process,
			NULL, NULL);
		wait(NULL);
		ptrace(PTRACE_GETREGS, traced_process,
			NULL,&regs);
		addr = freespaceaddr(traced_process);
		getdata(traced_process, addr, backup, len);
		putdata(traced_process, addr, insertcode, len);
		memcpy(&oldregs,&regs,sizeof(regs));
		regs.eip= addr;
		ptrace(PTRACE_SETREGS, traced_process,
			NULL,&regs);
		ptrace(PTRACE_CONT, traced_process,
			NULL, NULL);
		wait(NULL);
		printf("The process stopped, Putting back the original instructions\n");
		putdata(traced_process, addr, backup, len);
		ptrace(PTRACE_SETREGS, traced_process,
			NULL,&oldregs);
		printf("Letting it continue with original flow\n");
		ptrace(PTRACE_DETACH, traced_process,
			NULL, NULL);
		return0;
	}
```
ptrace的幕后工作

那么，在使用ptrace的时候，内核里发生了声么呢？这里有一段简要的说明：当一个进程调用了 ptrace( PTRACE_TRACEME, …)之后，内核为该进程设置了一个标记，注明该进程将被跟踪。内核中的相关原代码如下：
```
Source: arch/i386/kernel/ptrace.c
	if(request == PTRACE_TRACEME){
		/* are we already being traced? */
		if(current->ptrace & PT_PTRACED)
			goto out;
		/* set the ptrace bit in the process flags. */
		current->ptrace |= PT_PTRACED;
		ret =0;
		goto out;
	}
```
一次系统调用完成之后，内核察看那个标记，然后执行trace系统调用（如果这个进程正处于被跟踪状态的话）。其汇编的细节可以在 arh/i386/kernel/entry.S中找到。

现在让我们来看看这个sys_trace()函数（位于 arch/i386/kernel/ptrace.c ）。它停止子进程，然后发送一个信号给父进程，告诉它子进程已经停滞，这个信号会激活正处于等待状态的父进程，让父进程进行相关处理。父进程在完成相关操作以后就调用ptrace( PTRACE_CONT, …)或者 ptrace( PTRACE_SYSCALL, …), 这将唤醒子进程，内核此时所作的是调用一个叫wake_up_process() 的进程调度函数。其他的一些系统架构可能会通过发送SIGCHLD给子进程来达到这个目的。
小结：

ptrace函数可能会让人们觉得很奇特，因为它居然可以检测和修改一个运行中的程序。这种技术主要是在调试器和系统调用跟踪程序中使用。它使程序员可以在用户级别做更多有意思的事情。已经有过很多在用户级别下扩展操作系统得尝试，比如UFO,一个用户级别的文件系统扩展，它使用ptrace来实现一些安全机制。 

