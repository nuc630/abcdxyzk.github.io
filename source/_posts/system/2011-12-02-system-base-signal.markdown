---
layout: post
title: "linux signal 处理"
date: 2011-12-02 15:26:00 +0800
comments: false
categories:
- 2011
- 2011~12
- system
- system~base
tags:
- koj
---
[原文](http://blog.sina.com.cn/s/blog_6f92c8fc0100x6i5.html)  

贴一部分：
 
##### 总结
信号分成两种：  
regularsignal( 非实时信号 ), 对应的编码值为 [1,31]  
real timesignal 对应的编码值为 [32,64]  
 
编码为 0 的信号 不是有效信号，只用于检查是当前进程否有发送信号的 权限 ，并不真正发送。

线程会有自己的悬挂信号队列 , 并且线程组也有一个信号悬挂队列 .
信号悬挂队列保存 task 实例接收到的信号 , 只有当该信号被处理后它才会从悬挂队列中卸下 .
 
信号悬挂队列还有一个对应的阻塞信号集合 , 当一个信号在阻塞信号集合中时 ,task 不会处理该被阻塞的信号 ( 但是该信号依旧在悬挂队列中 ). 当阻塞取消时 , 它会被处理 .
 
##### 对一个信号 , 要三种处理方式 :
忽略该信号 ;  
采用默认方式处理 ( 调用系统指定的信号处理函数 );  
使用用户指定的方式处理 ( 调用用户指定的信号处理函数 ).

对于某些信号只能采用默认的方式处理 (eg:SIGKILL,SIGSTOP).  
信号处理可以分成两个阶段 : 信号产生并通知到接收方 (generation), 接收方进行处理 (deliver)
.........

#### 简介
Unix 为了允许用户态进程之间的通信而引入signal. 此外, 内核使用signal 给进程通知系统事件.近30 年来,signal 只有很小的变化 .
以下我们先介绍linuxkernel 如何处理signal, 然后讨论允许进程间 exchange 信号的系统调用.
 
The Role of Signals

signal 是一种可以发送给一个进程或一组进程的短消息( 或者说是信号 , 但是这么容易和信号量混淆). 这种消息通常只是一个整数 , 而不包含额外的参数 .  
linux 提供了很多种signal, 这些signal 通过宏来标识( 这个宏作为这个信号的名字). 并且这些宏的名字的开头是SIG.eg: 宏SIGCHLD , 它对应的整数值为17, 用来表示子进程结束时给父进程发送的消息 ( 即当子进程结束时应该向父进程发送标识符为17 的signal/ 消息/ 信号) .宏SIGSEGV, 它对应的整数值为11, 当进程引用一个无效的物理地址时( 内核) 会向进程发送标识符为11 的signal/ 消息/ 信号 ( 参考linux 内存管理的页错误异常处理程序, 以及linux 中断处理).  
信号有两个目的:  
1. 使一个进程意识到一个特殊事件发生了( 不同的事件用不同的signal 标识) 
2. 并使目标进程进行相应处理(eg: 执行的信号处理函数 , signalhandler). 相应的处理也可以是忽略它 .

当然 , 这两个目的不是互斥的 , 因为通常一个进程意识到一个事件发生后就会执行该事件相应的处理函数 .

下表是linux2.6 在80x86 上的前31 个signals 及其相关说明 . 这些信号中有些是体系结构相关的(eg:SIGCHLD,SIGSTOP), 有些则专门了某些体系结构才存在的(eg:SIGSTKFLT)( 可以参考中断处理 , 里面也列出了一些异常对应的signal).
```
The first 31 signals in Linux/i386
Signal name
Default action
Comment
POSIX
1
SIGHUP
Terminate
Hang up controlling terminal or process
Yes
2
SIGINT
Terminate
Interrupt from keyboard
Yes
3
SIGQUIT
Dump
Quit from keyboard
Yes
4
SIGILL
Dump
Illegal instruction
Yes
5
SIGTRAP
Dump
Breakpoint for debugging
No
6
SIGABRT
Dump
Abnormal termination
Yes
6
SIGIOT
Dump
Equivalent to SIGABRT
No
7
SIGBUS
Dump
Bus error
No
8
SIGFPE
Dump
Floating-point exception
Yes
9
SIGKILL
Terminate
Forced-process termination
Yes
10
SIGUSR1
Terminate
Available to processes
Yes
11
SIGSEGV
Dump
Invalid memory reference
Yes
12
SIGUSR2
Terminate
Available to processes
Yes
13
SIGPIPE
Terminate
Write to pipe with no readers
Yes
14
SIGALRM
Terminate
Real-timerclock
Yes
15
SIGTERM
Terminate
Process termination
Yes
16
SIGSTKFLT
Terminate
Coprocessor stack error
No
17
SIGCHLD
Ignore
Child process stopped or terminated, or got signal if traced
Yes
18
SIGCONT
Continue
Resume execution, if stopped
Yes
19
SIGSTOP
Stop
Stop process execution
Yes
20
SIGTSTP
Stop
Stop process issued from tty
Yes
21
SIGTTIN
Stop
Background process requires input
Yes
22
SIGTTOU
Stop
Background process requires output
Yes
23
SIGURG
Ignore
Urgent condition on socket
No
24
SIGXCPU
Dump
CPU time limit exceeded
No
25
SIGXFSZ
Dump
File size limit exceeded
No
26
SIGVTALRM
Terminate
Virtual timer clock
No
27
SIGPROF
Terminate
Profile timer clock
No
28
SIGWINCH
Ignore
Window resizing
No
29
SIGIO
Terminate
I/O now possible
No
29
SIGPOLL
Terminate
Equivalent to SIGIO
No
30
SIGPWR
Terminate
Power supply failure
No
31
SIGSYS
Dump
Bad system call
No
31
SIGUNUSED
Dump
Equivalent to SIGSYS
No
```
上述signal 称为regularsignal . 除此之外,POSIX 还引入了另外一类singal 即real-timesignal . real timesignal 的标识符的值从32 到64. 它们与reagularsignal 的区别在于每一次发送的real timesignal 都会被加入悬挂信号队列，所以多次发送的real timesignal 会被缓存起来( 而不会导致后面的被忽略掉) . 而同一种( 即标识符一样)regularsignal 不会被缓存,即如果同一个signal 被发送多次 , 它们只有一个会被放入接受进程的悬挂队列 .
 
虽然linux kernel 并没有使用real timesignal. 但是它也( 通过特殊的系统调用) 支持posix定义的realtime signal.
 
有很多系统调用可以给进程发送singal, 也有很多系统调可以指定进程在接收某一个signal 时应该如何响应( 即实行哪一个函数). 下表给出了这类系统调用:( 关于这些系统调用的更多信息参考下文)
```
System call
Description
kill( )
Send a signal to a thread group
tkill( )
Send a signal to a process
tgkill( )
Send a signal to a process in a specific thread group
sigaction( )
Change the action associated with a signal
signal( )
Similar to sigaction( )
sigpending( )
Check whether there are pending signals
sigprocmask( )
Modify the set of blocked signals
sigsuspend( )
Wait for a signal
rt_sigaction( )
Change the action associated with a real-time signal
rt_sigpending( )
Check whether there are pending real-time signals
rt_sigprocmask( )
Modify the set of blocked real-time signals
rt_sigqueueinfo( )
Send a real-time signal to a thread group
rt_sigsuspend( )
Wait for a real-time signal
rt_sigtimedwait( )
Similar to rt_sigsuspend( )
```
signal 可能在任意时候被发送给一个状态未知的进程 . 当信号被发送给一个当前并不正在执行的进程时, 内核必须把先把该信号保存直到该进程恢复执行.(to do ???????)
被阻塞的信号尽管会被加入进程的悬挂信号队列 , 但是在其被解除阻塞之前不会被处理(deliver),Blockinga signal (described later) requires that delivery of the signal beheld off until it is later unblocked,which acer s the problemof signals being raised before they can be delivered.
 
#### 内核把信号传送分成两个阶段: 
signalgeneration: 内核更新信号的目的进程的相关数据结构 , 这样该进程就能知道它接收到了一个信号. 觉得称为收到信号阶段更恰当. 这个generation 翻译成目的进程接收也不错 .
 
signaldelivery(): 内核强制目的进程处理接收到的信号，这主要是通过修改进程的执行状态或者在目的进程中执行信号处理函数来实现的 . 觉得称为处理收到的信号阶段更恰当 . diliver 这里翻译成处理更恰当 .
deliver 的翻译: 有很多个 , 估计翻译成incomputing 比较合理
 
一个genearatedsignal 最多只能deliver 一次( 即一个信号最多只会被处理一次) . signal 是可消耗资源 , 一旦一个signal 被deliver, 那么所有进程对它的引用都会被取消 .
已经产生但是还未被处理(deliver) 的信号称为pendingsignal ( 悬挂信号). 对于regularsignal, 在某一个时刻 , 一种signal 在一个进程中只能有一个实例( 因为进程没有用队列缓存其收到的signal) . 因为有31 种regualarsignal , 所以一个进程某一个时刻可以有31 个各类signal 的实例. 此外因为linux 进程对realtimesignal 采用不同的处理方式, 它会保存接收到的realtimesignal 的实例 , 所以可以同时有很多同种signal 的实例 .

##### 问题: 不同种类的信号的优先级( 从值较小的开始处理) .
一般而言 , 一个信号可能会被悬挂很长是时间( 即一个进程收到一个信号后 , 该信号有可能在该进程里很久 , 因为进程没空来处理它), 主要有如下因素:  
1. 信号通常被当前进程处理 . Signalsare usually delivered only to the currently running process (thatis, to the current process).  
2. 某种类型的信号可能被本进程阻塞. 只有当其被取消阻塞好才会被处理 .  
3. 当一个进程执行某一种信号的处理函数时 , 一般会自动阻塞这种信号 , 等处理完毕后才会取消阻塞 . 这意味着一个信号处理函数不会被同种信号阻塞 .  
 
尽管信号在概念上很直观 , 但是内核的实现却相当复杂. 内核必须:  
1. 记录一个进程阻塞了哪些信号  
2. 当从核心态切换到用户态时 , 检查进程是否接受到了signal.( 几乎每一次时钟中断都要干这样的事 , 费时吗?).  
3. 检查信号是否可以被忽略. 当如下条件均满足时则可被忽略:  
1). 目标进程未被其它进程traced( 即PT_PTRACED==0). 但一个被traced 的进程收到一个信号时 , 内核停止目标线程 , 并且给tracing 进程发送信号SIGCHLD.tracing 进程可能会通过SIGCONT来恢复traced 进程的执行  
2). 目标进程未阻塞该信号 .  
3). 信号正被目标进程忽略( 或者由于忽略是显式指定的或者由于忽略是默认操作).  
4. 处理信号 . 这可能需要切换到信号处理函数  
 
此外, linux 还需要处理BSD, SystemV 中signal 语义的差异性 . 另外 , 还需要遵守POSIX 的定义 .

#### 处理信号的方式 (Actions Performed uponDelivering a Signal)
一个进程可以采用三中方式来响应它接收到的信号:  
1.(ignore) 显示忽略该信号  
2.(default) 调用默认的函数来响应该信号( 这些默认的函数由内核定义) , 一般这些默认的函数都分成如下几种( 采用哪一种取决于信号的类型 , 参考前面的表格): 
```
Terminate: The process is terminated(killed) 
Dump: The process is terminated (killed) and a core file containingits execution context is created, if possible; this file may beused for debug purposes. 
Ignore:The signal is ignored. 
Stop:The process is stopped, i.e., put in the TASK_STOPPEDstate. 
Continue:If the process was stopped (TASK_STOPPED), it is put intothe TASK_RUNNING state.
```
3.(catch) 调用相应的信号处理函数 ( 这个信号处理函数通常是程序员在运行时指定的). 这意味着进程需要在执行时显式地指明它需要catch 哪一种信号. 并且指明其处理函数 . catch 是一种主动处理的措施 .

注意上述的三个处理方式被标识为:ignore, default,catch. 这三个处理方式以后会通过这三个标识符引用 .
 
注意阻塞一个信号和忽略一个信号是不同 , 一个信号被阻塞是就当前不会被处理 , 即一个信号只有在解除阻塞后才会被处理 . 忽略一个信号是指采用忽略的方式来处理该信号( 即对该信号的处理方式就是什么也不做) .

SIGKILL 和SIGSTOP 这两个信号不能忽略 , 不能阻塞 , 不能使用用户定义的函数(caught) . 所以总是执行它们的默认行为 . 所以 , 它们允许具有恰当特权级的用户杀死别的进程, 而不必在意被杀进程的防护措施 ( 这样就允许高特权级用户杀死低特权级的用户占用大量cpu 的时间) .

注: 有两个特殊情况. 第一 , 任意进程都不能给进程0( 即swapper 进程) 发信号 . 第二 , 发给进程1 的信号都会被丢弃(discarded), 除非它们被catch. 所以进程 0 不会死亡, 进程1 仅在int 程序结束时死亡 .
 
一个信号对一个进程而言是致命的(fatal) , 当前仅当该信号导致内核杀死该进程 . 所以,SIGKILL 总是致命的. 此外 , 如果一个进程对一个信号的默认行为是terminate 并且该进程没有catch 该信号 , 那么该信号对这个进程而言也是致命的 . 注意 , 在catch 情况下 , 如果一个进程的信号处理函数自己杀死了该进程 , 那么该信号对这个进程而言不是致命的 , 因为不是内核杀死该进程而是进程的信号处理函数自己杀死了该进程.
 
#### POSIX 信号以及多线程程序
 
POSIX1003.1 标准对多线程程序的信号处理有更加严格的要求:   
( 由于linux 采用轻量级进程来实现线程 , 所以对linux 的实现也会有影响)  
1. 多线程程序的所有线程应该共享信号处理函数 , 但是每一个线程必须有自己的maskof pending and blocked signals  
2. POSIX 接口kill( ), sigqueue() 必须把信号发给线程组 , 而不是指定线程. 另外内核产生的SIGCHLD,SIGINT, or SIGQUIT 也必须发给线程组 .  
3. 线程组中只有有一个线程来处理(deliver) 的共享的信号就可以了 . 下问介绍如何选择这个线程 .  
4. 如果线程组收到一个致命的信号 , 内核要杀死线程组的所有线程, 而不是仅仅处理该信号的线程 .  
 
为了遵从POSIX 标准,linux2.6 使用轻量级进程实现线程组.
 
下文中 , 线程组表示OS 概念中的进程, 而线程表示linux 的轻量级进程. 进程也( 更多地时候)表示linux 的轻量级进程 . 另外每一个线程有一个私有的悬挂信号列表 , 线程组共享一个悬挂信号列表 .

