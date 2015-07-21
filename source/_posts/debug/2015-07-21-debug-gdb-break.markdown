---
layout: post
title: "gdb break/watch/catch"
date: 2015-07-21 15:49:00 +0800
comments: false
categories:
- 2015
- 2015~07
- debug
- debug~gdb
tags:
---
http://sourceware.org/gdb/current/onlinedocs/gdb

[gdb break 断点设置（一）](http://blog.csdn.net/yangzhongxuan/article/details/6897968)  
[gdb watch 断点设置（二）](http://blog.csdn.net/yangzhongxuan/article/details/6899186)  
[gdb catch 断点设置（三）](http://blog.csdn.net/yangzhongxuan/article/details/6901440)  
[gdb 断点删除（四）](http://blog.csdn.net/yangzhongxuan/article/details/6901477)  

----------
### 二、断点设置

#### gdb断点分类：

以设置断点的命令分类：

breakpoint 可以根据行号、函数、条件生成断点。
watchpoint 监测变量或者表达式的值发生变化时产生断点。
catchpoint 监测信号的产生。例如c++的throw，或者加载库的时候。

gdb中的变量从1开始标号，不同的断点采用变量标号同一管理，可以 用enable、disable等命令管理，同时支持断点范围的操作，比如有些命令接受断点范围作为参数。

#### 1、break及break变种详解：
相关命令有break，tbreak，rbreak,hbreak，thbreak，后两种是基于硬件的，先不介绍。

##### break 与 tbeak
break，tbreak可以根据行号、函数、条件生成断点。tbreak设置方法与break相同，只不过tbreak只在断点停一次，过后会自动将断点删除，break需要手动控制断点的删除和使能。

break 可带如下参数：  
  linenum            本地行号，即list命令可见的行号  
  filename:linenum   制定个文件的行号  
  function           函数，可以是自定义函数也可是库函数，如open  
  filename:function  制定文件中的函数  
  condtion           条件  
  *address           地址，可是函数，变量的地址，此地址可以通过info add命令得到。  

例如：
```
	break 10    
	break test.c:10
	break main
	break test.c:main
	break system
	break open
```

如果想在指定的地址设置断点，比如在main函数的地址出设断点。可用info add main 获得main的地址如0x80484624，然后用break *0x80484624.

###### 条件断点
就是在如上述指定断点的同时指定进入断点的条件。

例如：（假如有int 类型变量 index）
```
	break 10 if index == 3
	tbreak 12 if index == 5
```

##### rbreak
rbreak 可以跟一个规则表达式。rbreak + 表达式的用法与grep + 表达式相似。即在所有与表达式匹配的函数入口都设置断点。
 
rbreak list_* 即在所有以 list_ 为开头字符的函数地方都设置断点。

rbreak ^list_ 功能与上同。

##### 查看断点信息
```
	info break [break num ]
	info break 可列出所有断点信息，info break 后也可设置要查看的break num如：
	info break 1 列出断点号是1的断点信息

	Num        Type                    Disp Enb  Address      What
	 1       breakpoint                keep y    <MULTIPLE>
         stop only if i==1
         breakpoint already hit 1 time
	 1.1                                    y    0x080486a2 in void foo<int>() at t.cc:8
	 1.2                                    y    0x080486ca in void foo<double>() at t.cc:8
```

---------------

#### 2、watch
```
	watch [-l|-location] expr [thread threadnum] [mask maskvalue]
```
-l 与 mask没有仔细研究，thread threadnum 是在多线程的程序中限定只有被线程号是threadnum的线程修改值后进入断点。

经常用到的如下命令：
watch <expr>  
为表达式（变量）expr设置一个观察点。变量量表达式值有变化时，马上停住程序。
 
表达式可以是一个变量, 例如：watch value_a
 
表达式可以是一个地址, 例如：watch *(int *)0x12345678 可以检测4个字节的内存是否变化。
 
表达式可以是一个复杂的语句表达式, 例如：watch a*b + c/d
 
watch 在有些操作系统支持硬件观测点，硬件观测点的运行速度比软件观测点的快。如果系统支持硬件观测的话，当设置观测点是会打印如下信息：`Hardware watchpoint num: expr`

如果不想用硬件观测点的话可如下设置：`set can-use-hw-watchpoints`
 
watch两个变种 rwatch，awatch，这两个命令只支持硬件观测点如果系统不支持硬件观测点会答应出不支持这两个命令的信息:，
 
rwatch <expr>  
当表达式（变量）expr被读时，停住程序。
   
awatch <expr>  
当表达式（变量）的值被读或被写时，停住程序。
   
info watchpoints  
列出当前所设置了的所有观察点。
 
watch 所设置的断点也可以用控制断点的命令来控制。如 disable、enable、delete等。 
 
可以为停止点设定运行命令
``` 
	commands [bnum]
	... command-list ...
	end
```

为断点号bnum指写一个命令列表。当程序被该断点停住时，gdb会依次运行命令列表中的命令。

例如：
``` 
	break foo if x>0
	commands
	printf "x is %d/n",x
	continue
	end
```

断点设置在函数foo中，断点条件是x>0，如果程序被断住后，也就是，一旦x的值在foo函数中大于0，GDB会自动打印出x的值，并继续运行程序。 

注意：watch 设置也是断点，如果调试的时候设置的断点（任何种类的断点）过多的时候，watch断点会被忽略，有时候没有任何提示，这是我在测试的时候发现的，只有把多余的断点删除后才可用。

------------------

在调试的时候通常用catchpoints来捕获事件，如c++的异常等。捕获点的设置通过catch与tcatch两个命令。

tcatch所设置的断点停止一次后自动删除，设置断点的方法与catch相同。

用法：catch event

这些event事件如下：
```
	throw
		The throwing of a C++ exception.
	catch
		The catching of a C++ exception.
	exception

	exception unhandled
		An exception that was raised but is not handled by the program.
	assert
		Ada 语言 assert断言失败时，断点被踩到。
	exec
		调用exec时断点被踩到。
	syscall
	syscall [name | number] ...
		通过系统函数的名称和系统号，来设置捕获点，当所设定的系统调用时，断点被踩到。
		因为经常在linux用c语言，所以主要用到的event是最后四个，其他的没有仔细研究。
```

例如：
```
	catch syscall open
	catch syscall 5
```
这两个捕获断点一样。

--------------

断点的删除与断点的设置同样的重要。删除断点的命令有两个: delete, clear

##### delete
用法：  
delete [breakpoints num] [range...]

delete可删除单个断点，也可删除一个断点的集合，这个集合用连续的断点号来描述。

例如：
```
	delete 5
	delete 1-10
```

##### clear
用法:  
clear  
删除所在行的多有断点。

clear location  
clear 删除所选定的环境中所有的断点  
clear location location描述具体的断点。  

例如：
```
	clear list_insert         //删除函数的所有断点
	clear list.c:list_delet   //删除文件：函数的所有断点
	clear 12                  //删除行号的所有断点
	clear list.c:12           //删除文件：行号的所有断点
```

clear 删除断点是基于行的，不是把所有的断点都删除。

