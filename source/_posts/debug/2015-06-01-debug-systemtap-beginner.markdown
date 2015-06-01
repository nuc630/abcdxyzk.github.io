---
layout: post
title: "SystemTap Beginner"
date: 2015-06-01 15:03:00 +0800
comments: false
categories:
- 2015
- 2015~06
- debug
- debug~systemtap
tags:
---
http://blog.csdn.net/kafeiflynn/article/details/6429976

### SystemTap
应用：

  对管理员，SystemTap可用于监控系统性能，找出系统瓶颈，而对于开发者，可以查看他们的程序运行时在linux系统内核内部的运行情况。主要用于查看内核空间事件信息，对用户空间事件的探测，目前正加紧改进。

#### 安装
1、SystemTap的安装及使用需要针对正在使用的内核安装相应的kernel-devel、kernel-debuginfo和kernel-debuginfo-common包，以插入探针。  
2、安装SystemTap和SystemTap-runtime包  
3、使用如下命令测试一下：  

```
	stap -v -e 'probe vfs.read {printf("read performed/n"); exit()}'
```

为目标机产生SystemTap instrumentation:

这样就可以在一台机器上为多种内核产生SystemTap instrumentation，而且目标机上只安装SystemTap-runtime即可。

操作如下：  
1.在目标机上安装systemtap-runtime RPM包；  
2.使用uname –r查看目标机内核；  
3.在host system上安装SystemTap；  
4.在host system上安装目标机内核及相关RPMs  
5.在host name上运行命令：  
```
	stap -r kernel_version script -m module_name
```

6.把新产生的模块拷贝到目标机，并运行如下命令：
```
	staprun module_name.ko
```

注意：host system和目标机架构及操作系统版本必须一致。

#### 运行SystemTap脚本

运行stap和staprun需要被授以权限，一般用户需要运行SystemTap，则需要被加入到以下用户组的一个：  
1、stapdev：用stap编译SystemTap脚本成内核模块，并加载进内核；  
2、stapusr：仅能运行staprun加载/lib/modules/kernel_version/systemtap/目录下模块。  

##### SystemTap Flight Recorder模式
该模式允许长时间运行SystemTap脚本，但仅focus on 最近的输出，有2个变种：in-memory和file模式，两种情况下SystemTap都作为后台进程运行。

##### In-memory模式：
```
	stap -F iotime.stp
```

一旦脚本启动后，你可以看到以下输出信息以辅助命令重新连到运行中的脚本：
```
	Disconnecting from systemtap module.
	To reconnect, type "staprun -A stap_5dd0073edcb1f13f7565d8c343063e68_19556"
```
当感兴趣的事件发生时，可以重新连接到运行中的脚本，并在内存Buffer中输出最近的数据并持续输出：
```
	staprun -A stap_5dd0073edcb1f13f7565d8c343063e68_19556
```
内存Buffer默认1MB，可以使用-S选项，例如-S2指定为2MB
```
	File Flight Recorder
	stap -F -o /tmp/pfaults.log -S 1,2  pfaults.stp
```
命令结果输出到/tmp/pfaults.log.[0-9]，每个文件1MB，并且仅保存最近的两个文件，-S指定了第一个参数：每个输出文件大小1MB，第二个参数：仅保留最近的两个文件，systemtap在pfaults.log后面加.[0-9]后缀。

该命令的输出是systemtap脚本进程ID，使用如下命令可以终止systemtap脚本

```
	kill -s SIGTERM 7590
```

运行
```
	ls –sh /tmp/pfaults.log.*

	1020K /tmp/pfaults.log.5    44K /tmp/pfaults.log.6
```

#### SystemTap如何工作

SystemTap的基本工作原理就是：event/handler，运行systemtap脚本产生的加载模块时刻监控事件的发生，一旦发生，内核就调用相关的handler处理。

一运行一个SystemTap脚本就会产生一个SystemTap session：  
1.SystemTap检查脚本以及所使用的相关tapset库；  
2.SystemTap将脚本转换成C语言文件，并运行C语言编译器编译之创建一个内核模块；  
3.SystemTap加载该模块，从而使用所有探针(events和handlers)；  
4.事件发生时，执行相关handlers  
5.一旦SystemTap session停止，则探针被禁止，该内核模块被卸载。  

探针：event及其handler，一个SystemTap脚本可以包含多个探针。

SystemTap脚本以.stp为扩展名，其基本格式如下所示：

```
	probe event {statements}
```

允许一个探针内多个event，以,隔开，任一个event发生时，都会执行statements，各个语句之间不需要特殊的结束符号标记。而且可以在一个statements block中包含其他的statements block。

函数编写：

```
	function function_name(arguments) {statements}

	probe event {function_name(arguments)}
```
	
#### SystemTap Event

可大致划分为synchronous和asynchronous。

##### 同步事件：

执行到定位到内核代码中的特定位置时触发event

1.syscall.system_call  
系统调用入口和exit处：syscall.system_call和syscall.system_call.return，比如对于close系统调用：syscall.close和syscall.close.return

2.vfs.file_operation  
vfs.file_operation和vfs.file_operation.return

3.kernel.function("function")  
如：kernel.function(“sys_open”)和kernel.function(“sys_open”).return

可使用*来代表wildcards：
```
	probe kernel.function("*@net/socket.c") { }
	probe kernel.function("*@net/socket.c").return { }
```

代表了net/socket.c中所有函数的入口和exit口。

4.kernel.trace("tracepoint")  
2.6.30及newer为内核中的特定事件定义了instrumentation，入kernel.trace(“kfree_skb”)代表内核中每次网络buffer被释放掉时的event。

5.module("module").function("function")
```
	probe module("ext3").function("*") { }
	probe module("ext3").function("*").return { }
```

系统内核模块多存放在/lib/modules/kernel_version

#### Asynchronous Events

不绑定到内核的特定指令或位置处。包括：  
1、begin：SystemTap session开始时触发，当SystemTap脚本开始运行时触发；  
2、end ：SystemTap session终止时触发；  
3、timer事件：  

```
	probe timer.s(4)
	{
		printf("hello world/n")
	}
```

• timer.ms(milliseconds)  
• timer.us(microseconds)  
• timer.ns(nanoseconds)  
• timer.hz(hertz)  
• timer.jiffies(jiffies)

可查看man stapprobes来查看其它支持的events

#### SystemTap Handler/Body

支持的函数：  
1、  printf ("format string/n", arguments)，%s：字符串，%d数字，以 , 隔开；  
2、  tid()：当前线程ID；  
3、  uid()：当前用户ID；  
4、  cpu()：当前CPU号；  
5、  gettimeofday_s()：自从Epoch开始的秒数；  
6、  ctime()将从Unix Epoch开始的秒数转换成date；  
7、  pp()：描述当前被处理的探针点的字符串；  
8、  thread_indent()：  

```
	probe kernel.function("*@net/socket.c")
	{
		printf ("%s -> %s/n", thread_indent(1), probefunc())
	}

	probe kernel.function("*@net/socket.c").return
	{
		printf ("%s <- %s/n", thread_indent(-1), probefunc())
	}

	0 ftp(7223): -> sys_socketcall
	1159 ftp(7223):  -> sys_socket
	2173 ftp(7223):   -> __sock_create
	2286 ftp(7223):    -> sock_alloc_inode
	2737 ftp(7223):    <- sock_alloc_inode
	3349 ftp(7223):    -> sock_alloc
	3389 ftp(7223):    <- sock_alloc
	3417 ftp(7223):   <- __sock_create
	4117 ftp(7223):   -> sock_create
	4160 ftp(7223):   <- sock_create
	4301 ftp(7223):   -> sock_map_fd
	4644 ftp(7223):    -> sock_map_file
	4699 ftp(7223):    <- sock_map_file
	4715 ftp(7223):   <- sock_map_fd
	4732 ftp(7223):  <- sys_socket
	4775 ftp(7223): <- sys_socketcall
```

  函数thread_indent()只有1个参数：代表对线程的”indentation counter”的增减数，即系统调用显示的步数，返回字符串(自从第一次调用thread_indent()以来的描述：进程名(进程ID))

9、name  
标记系统调用的名字，仅用于syscall.system_call中。

10、target()  
与stap script -x process ID or stap script -c command联合使用，如果想在脚本中获得进程ID或命令可以如此做

```
	probe syscall.* {
		if (pid() == target())
			printf("%s/n", name)
	}
```

#### SystemTap Handler构造

##### 变量
1、不必事先声明，直接使用即可，由SystemTap自动判断其属于string还是integer，整数则默认为0，默认在probe中声明的是local变量  
2、在各个probe之间共享的变量使用global声明  

```
	global count_jiffies, count_ms
	probe timer.jiffies(100) { count_jiffies ++ }
	probe timer.ms(100) { count_ms ++ }
	probe timer.ms(12345)
	{
		hz=(1000*count_jiffies) / count_ms
		printf ("jiffies:ms ratio %d:%d => CONFIG_HZ=%d/n",
			count_jiffies, count_ms, hz)
		exit()
	}
```

##### Target变量

Probe event可以映射到代码的实际位置，如kernel.function(“function”)、kernel.statement(“statement”)，这允许使用target变量来记录代码中指定位置处可视变量的值。

运行如下命令：可以显示指定vfs_read处可视target变量

```
	stap -L 'kernel.function("vfs_read")'
```

显示
```
	kernel.function("vfs_read@fs/read_write.c:277") $file:struct file* $buf:char* $count:size_t

	$pos:loff_t*
```

每个target变量以$开头：变量类型。如果是结构体类型，则SystemTap可以使用->来查看其成员。对基本类型，integer或string，SystemTap有函数可以直接读取address处的值，如：

```
	# 好像有时对于小于8位的函数，会取出8为长度的值
	kernel_char(address)
	Obtain the character at address from kernel memory.

	kernel_short(address)
	Obtain the short at address from kernel memory.

	kernel_int(address)
	Obtain the int at address from kernel memory.

	kernel_long(address)
	Obtain the long at address from kernel memory

	kernel_string(address)
	Obtain the string at address from kernel memory.

	kernel_string_n(address, n)
	Obtain the string at address from the kernel memory and limits the string to n bytes.
```

##### 打印target变量
```
	$$vars：类似sprintf("parm1=%x ... parmN=%x var1=%x ... varN=%x", parm1, ..., parmN, var1, ..., varN)，目的是打印probe点处的每个变量；

	$$locals：$$vars子集，仅打印local变量；

	$$parms：$$vars子集，仅包含函数参数；

	$$return：仅在return probes存在，类似sprintf("return=%x", $return)，如果没有返回值，则是空串
```

例子如下：

```
	stap -e 'probe kernel.function("vfs_read") {printf("%s/n", $$parms); exit(); }'
```

函数vfs_read有4个参数：file、buf、count和pos，输出如下：
```
	file=0xffff8800b40d4c80 buf=0x7fff634403e0 count=0x2004 pos=0xffff8800af96df48
```
如果你想知道数据结构里面的成员信息，可以在”$$params”后面加一个”$”，如下所示：

```
	stap -e 'probe kernel.function("vfs_read") {printf("%s/n", $$parms$); exit(); }'
```
输出如下：

```
	file={.f_u={...}, .f_path={...}, .f_op=0xffffffffa06e1d80, .f_lock={...}, .f_count={...}, .f_flags=34818, buf="" count=8196 pos=-131938753921208
```

仅一个”$”表示，不展开数据结构域成员，如想展开，则需使用”$$”
```
	stap -e 'probe kernel.function("vfs_read") {printf("%s/n", parms); exit(); }'
```

输出受限于最大字符串大小：

```
	file={.f_u={.fu_list={.next=0xffff8801336ca0e8, .prev=0xffff88012ded0840}, .fu_rcuhead={.next=0xffff8801336ca0e8
```

##### 强制类型转换

大多数情况下，SystemTap都可以从debuginfo中获得变量类型，但对于代码中void指针则debuginfo中类型信息不可用，同样probe handler里面的类型信息在function里面也不可用，怎么办呢？

SystemTap函数参数使用long来代替typed pointer，SystemTap的@cast操作可以指出对象正确类型：

```
	function task_state:long (task:long)
	{
		return @cast(task, "task_struct", "kernel<linux/sched.h>")->state
	}
```

第一个参数是指向对象的指针， 第二个参数是将该对象(参数1)要强制类型转换成的类型，第三个参数指出类型定义的出处，是可选的。

##### 检查Target变量可用性

随着代码运行，变量可能失效，因此需要用@defined来判断该变量是否可用：

```
	probe vm.pagefault = kernel.function("__handle_mm_fault@mm/memory.c") ?,

	kernel.function("handle_mm_fault@mm/memory.c") ?
	{
		name = "pagefault"
		write_access = (@defined($flags) ? $flags & FAULT_FLAG_WRITE : $write_access)
		address = $address
	}
```

##### 条件语句
```
	if (condition)
		statement1
	else
		statement2
```
 
```
	global countread, countnonread
	probe kernel.function("vfs_read"),kernel.function("vfs_write")
	{
		if (probefunc()=="vfs_read")
			countread ++
		else
			countnonread ++
	}

	probe timer.s(5) { exit() }

	probe end
	{
		printf("VFS reads total %d/n VFS writes total %d/n", countread, countnonread)
	}
```

##### 循环语句

```
	while (condition)
		statement

	for (initialization; conditional; increment) statement
```

##### 比较：
```
	==、>=、<=、!=
```

##### 命令行参数：
使用$标志着希望输入的是integer类型命令行参数，@：string
```
	probe kernel.function(@1) { }
	probe kernel.function(@1).return { }
```

#### 关联数组

关联数组一般在multiple probes里面处理，所以必须声明为global，不管是在一个还是多个probes里面用，要读取数组成员值，可以：
```
	array_name[index_expression]
```
如下所示：
```
	foo["tom"] = 23
	foo["dick"] = 24
	foo["harry"] = 25
```

一个索引可以包含最多9个索引表达式，用 , 隔开：

```
	device[pid(),execname(),uid(),ppid(),"W"] = devname
```
 
##### SystemTap的数组操作

###### 赋值：
```
	array_name[index_expression] = value
```
例子：索引和值可以使用handler function：

```
	foo[tid()] = gettimeofday_s()
```

每次触发这个语句，多次后就会构成一个关联数组，如果tid()返回值在foo索引中已有一个，则用新值代替旧值。

###### 读取数组值：

```
	delta = gettimeofday_s() - foo[tid()]
```

如果无法找到指定”索引”对应的值，则数组读返回0(int)或null/empty值(string)

###### 增加关联数组值

```
	array_name[index_expression] ++
```

处理数组的多个成员：

```
	global reads
	probe vfs.read
	{
		reads[execname()] ++
	}

	probe timer.s(3)
	{
		foreach (count in reads)
		printf("%s : %d /n", count, reads[count])
	}
```

这个foreach无序打印所有reads数组值，如果想升序/降序，则需要使用升序(+)、降序(-)，也可以限制处理的数组数目：

```
	probe timer.s(3)
	{
		foreach (count in reads- limit 10)
		printf("%s : %d /n", count, reads[count])
	}
```

##### Clearing/Deleting数组和数组成员

```
	global reads
	probe vfs.read
	{
		reads[execname()] ++
	}

	probe timer.s(3)
	{
		foreach (count in reads)
		printf("%s : %d /n", count, reads[count])

		delete reads
	}
```

使用delete操作来删除数组成员或整个数组。

```
	global reads, totalreads
	probe vfs.read
	{
		reads[execname()] ++
		totalreads[execname()] ++
	}

	probe timer.s(3)
	{
		printf("=======/n")
		foreach (count in reads-)
			printf("%s : %d /n", count, reads[count])
		delete reads
	}

	probe end
	{
		printf("TOTALS/n")
		foreach (total in totalreads-)
		printf("%s : %d /n", total, totalreads[total])
	}
```

在if语句中使用数组：

```
	global reads
	probe vfs.read
	{
		reads[execname()] ++
	}

	probe timer.s(3)
	{
		printf("=======/n")
		foreach (count in reads-)
		if (reads[count] >= 1024)
			printf("%s : %dkB /n", count, reads[count]/1024)
		else
			printf("%s : %dB /n", count, reads[count])
	}
```

##### 检查成员

可以检查是否一个指定健是数组键值：
```
	if([index_expression] in array_name) statement
```

```
	global reads
	probe vfs.read
	{
		reads[execname()] ++
	}

	probe timer.s(3)
	{
		printf("=======/n")
		foreach (count in reads+)
			printf("%s : %d /n", count, reads[count])
		if(["stapio"] in reads) {
			printf("stapio read detected, exiting/n")
			exit()
		}
	}
```

##### 计算统计集合

统计集合用于收集数值的统计信息，用于计算新值

```
	global reads
	probe vfs.read
	{
		reads[execname()] <<< count
	}
```

操作符<<<用于将count返回的值存放在read数组中execname()相关的值中，即一个键值关联多个相关值。

为计算统计信息，使用@extractor(variable/array index expression)，extractor可以是如下integer extractor：

```
	count：@count(writes[execname()])返回存放在writes数组中某单一键值对应的值数目；
	sum：@sum(writes[execname()])返回在writes数组中某单一键值对应的值的和
	min：最小值
	max：最大值
	avg：variable/array作为索引的统计集合中数据的平均值
```

```
	global reads
	probe vfs.read
	{
		reads[execname(),pid()] <<< 1
	}

	probe timer.s(3)
	{
		foreach([var1,var2] in reads)
		printf("%s (%d) : %d /n", var1, var2, @count(reads[var1,var2]))
	}
```

#### Tapsets
Tapsets是脚本库，里面预写好了probes和functions可以被SystemTap脚本调用，tapsets也使用.stp作为后缀，默认位于：/usr/share/systemtap/tapset，但无法直接运行。

