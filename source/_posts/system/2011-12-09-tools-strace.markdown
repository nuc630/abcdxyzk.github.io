---
layout: post
title: "跟踪系统调用和信号"
date: 2011-12-09 00:16:00 +0800
comments: false
categories:
- 2011
- 2011~12
- system
- system~tools
tags:
---
  strace 用来截取程序发出的系统调用并将其显示出来。被 strace 跟踪的程序，可以是从 strace 命令运行的，也可以是系统上已经运行的进程。strace 是调试汇编语言和高级语言程序时价值无法估量的工具。

  为了简单起见(不让 strace 输出太多内容)，这里使用 strace 截取 http://www.groad.net/bbs/read.php?tid-2622.html 中“系统调用返回值“ 里的示例程序：  
```
$ strace ./syscall2
execve("./syscall2", ["./syscall2"], [/* 43 vars */]) = 0
getpid()                                = 2467
getuid()                                = 1000
getgid()                                = 1000
_exit(0)                                = ?
```
上面，左侧一列显示了系统调用名称，右侧显示系统调用生成的返回值。

高级 strace 参数：
```
参数		描述
-c		统计每个系统调用的时间、调用和错误
-d		显示 strace 的一些调试输出
-e		指定输出的过滤表达式
-f		在创建子进程的时候跟踪它们
-ff		如果写入到输出文件，则把每个子进程写入到单独的文件中
-i		显示执行系统调用时的指令指针
-o		把输出写入到指定文件
-p		附加到由PID指定的现有进程
-q		抑制关于附加和分离的消息
-r		对每个系统调用显示一个相对的时间戳
-t		把时间添加到每一行
-tt		把时间添加到每一行，包括微秒
-ttt		添加epoch形式的时间(从1970年1月1日开始的秒数)，包括微秒
-T		显示每个系统调用花费的时间
-v		显示系统调用信息的不经省略版本(详细的)
-x		以十六进制格式显示所有非ASCII字符
-xx		以十六进制格式显示所有字符串
```
其中，-e 参数很方便，因为它可以用于只显示系统调用的子集，而不是全部。-e 参数格式为：  
`trace=call_list`  
上面，call_list 是系统调用清单。如上面的程序，如果我们只希望看到系统调用 getuid 和 getgid，那么可以：  
```
$ strace -e trace=getpid,getgid ./syscall2
getpid()                                = 2653
getgid()                                = 1000
```
注意，上面的 getpid 和 getgid 之间以逗号相隔，不能再有其它符号，包括空格。

使用 -o 参数可以将结果导出到一个文件中，如将跟踪 id 这个命令时，可以：
```
$ strace -o outfile id
uid=1000(beyes) gid=1000(beyes) 组=4(adm),20(dialout),24(cdrom),46(plugdev),105(lpadmin),119(admin),122(sambashare),1000(beyes)
```
从输出看出，id 指令也运行了，并在当前目录下生成 outfile 文件，在 outfile 文件里，列出了 id 指令所调用的系统调用。这些系统调用非常多，总共有278次之多。为了帮助组织这些调用信息，我们尝试使用 -c 参数，这时结果会按照时间排列调用：
```
$ strace -c id
uid=1000(beyes) gid=1000(beyes) 组=4(adm),20(dialout),24(cdrom),46(plugdev),105(lpadmin),119(admin),122(sambashare),1000(beyes)
% time     seconds  usecs/call     calls    errors syscall
------ ----------- ----------- --------- --------- ----------------
  -nan    0.000000           0        17           read
  -nan    0.000000           0         1           write
  -nan    0.000000           0        44         3 open
  -nan    0.000000           0        47           close
  -nan    0.000000           0         1           execve
  -nan    0.000000           0         9         9 access
  -nan    0.000000           0         3           brk
  -nan    0.000000           0        18           munmap
  -nan    0.000000           0        10           mprotect
  -nan    0.000000           0        20           _llseek
  -nan    0.000000           0        51           mmap2
  -nan    0.000000           0        40           fstat64
  -nan    0.000000           0         1           getuid32
  -nan    0.000000           0         1           getgid32
  -nan    0.000000           0         1           geteuid32
  -nan    0.000000           0         1           getegid32
  -nan    0.000000           0         2           getgroups32
  -nan    0.000000           0         1           fcntl64
  -nan    0.000000           0         1           set_thread_area
  -nan    0.000000           0         1           statfs64
  -nan    0.000000           0         4           socket
  -nan    0.000000           0         4         4 connect
------ ----------- ----------- --------- --------- ----------------
100.00    0.000000                   278        16 total
```
从上面的输出结果可以看到，调用 open 时发生了 3 次错误，调用 connect 时发生了 4 次错误。为了进一步跟踪这些错误，可以将它们单独挑选出来：
```
$ strace -e trace=open,connect id
open("/etc/ld.so.cache", O_RDONLY)      = 3
open("/lib/libselinux.so.1", O_RDONLY)  = 3
open("/lib/tls/i686/cmov/libc.so.6", O_RDONLY) = 3
open("/lib/tls/i686/cmov/libdl.so.2", O_RDONLY) = 3
open("/proc/filesystems", O_RDONLY|O_LARGEFILE) = 3
open("/proc/filesystems", O_RDONLY|O_LARGEFILE) = 3
open("/usr/lib/locale/locale-archive", O_RDONLY|O_LARGEFILE) = -1 ENOENT (No such file or directory)
open("/usr/share/locale/locale.alias", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_IDENTIFICATION", O_RDONLY) = 3
open("/usr/lib/gconv/gconv-modules.cache", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_MEASUREMENT", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_TELEPHONE", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_ADDRESS", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_NAME", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_PAPER", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_MESSAGES", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_MESSAGES/SYS_LC_MESSAGES", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_MONETARY", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_COLLATE", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_TIME", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_NUMERIC", O_RDONLY) = 3
open("/usr/lib/locale/zh_CN.utf8/LC_CTYPE", O_RDONLY) = 3
open("/usr/share/locale/zh_CN/LC_MESSAGES/coreutils.mo", O_RDONLY) = -1 ENOENT (No such file or directory)
open("/usr/share/locale/zh/LC_MESSAGES/coreutils.mo", O_RDONLY) = -1 ENOENT (No such file or directory)
open("/usr/share/locale-langpack/zh_CN/LC_MESSAGES/coreutils.mo", O_RDONLY) = 3
connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
open("/etc/nsswitch.conf", O_RDONLY)    = 3
open("/etc/ld.so.cache", O_RDONLY)      = 3
open("/lib/tls/i686/cmov/libnss_compat.so.2", O_RDONLY) = 3
open("/lib/tls/i686/cmov/libnsl.so.1", O_RDONLY) = 3
open("/etc/ld.so.cache", O_RDONLY)      = 3
open("/lib/tls/i686/cmov/libnss_nis.so.2", O_RDONLY) = 3
open("/lib/tls/i686/cmov/libnss_files.so.2", O_RDONLY) = 3
open("/etc/passwd", O_RDONLY|O_CLOEXEC) = 3
connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
connect(3, {sa_family=AF_FILE, path="/var/run/nscd/socket"}, 110) = -1 ENOENT (No such file or directory)
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/proc/sys/kernel/ngroups_max", O_RDONLY) = 3
open("/proc/sys/kernel/ngroups_max", O_RDONLY) = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
open("/etc/group", O_RDONLY|O_CLOEXEC)  = 3
uid=1000(beyes) gid=1000(beyes) 组=4(adm),20(dialout),24(cdrom),46(plugdev),105(lpadmin),119(admin),122(sambashare),1000(beyes)
```
从输出结果(红色加亮部分)可以知道错误在哪里了。

#### 附加到正在运行的程序
strace 的另一个非常好的特性是监视已经运行在系统上的程序的能力。-p 参数可以把 strace 附加到一个 PID 并且捕获系统调用。下面程序可以在后台运行，并且这个程序将维持运行一段时间，在此期间我们用 strace 来捕获它。  
程序代码：  
```
	.section.data
timespec:
	.int5,0
output:
	.ascii"This is a test/n"
output_end:
	.equlen,output_end-output

.section.bss
	.lcommrem,8

.section.text
.global_start
_start:
	nop
	movl$10,%ecx
    
loop1:
	pushl%ecx
	movl$4,%eax
	movl$1,%ebx
	movl$output,%ecx
	movl$len,%edx
	int$0x80

	movl$162,%eax
	movl$timespec,%ebx
	movl$rem,%ecx
	int$0x80
	popl%ecx
	looploop1
    
	movl$1,%eax
	movl$0,%ebx
	int$0x80
```
程序中使用了 nanosleep() 这个系统调用函数。在一个终端里后台运行这个函数：  
```
	./nanostrace &
```
然后使用 ps 命令得到此进程的 PID 值，接着可以用 strace 来跟踪了：
```
$ strace -p 3069
Process 3069 attached - interrupt to quit
restart_syscall(<... resuming interrupted call ...>) = 0
write(1, "This is a test/n", 15)        = 15
nanosleep({5, 0}, 0x80490d0)            = 0
write(1, "This is a test/n", 15)        = 15
nanosleep({5, 0}, 0x80490d0)            = 0
write(1, "This is a test/n", 15)        = 15
nanosleep({5, 0}, 0x80490d0)            = 0
write(1, "This is a test/n", 15)        = 15
nanosleep({5, 0}, 0x80490d0)            = 0
_exit(0)                                = ?
```
由上可见，程序中使用了 write, nanosleep, exit 3个系统调用。 

