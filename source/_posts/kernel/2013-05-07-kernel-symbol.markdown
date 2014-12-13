---
layout: post
title: "获取Linux内核未导出符号"
date: 2013-05-07 18:16:00 +0800
comments: false
categories:
- 2013
- 2013~05
- kernel
- kernel~base
tags:
---
  从Linux内核的2.6某个版本开始，内核引入了导出符号的机制。只有在内核中使用EXPORT_SYMBOL或EXPORT_SYMBOL_GPL导出的符号才能在内核模块中直接使用。

然而，内核并没有导出所有的符号。例如，在3.8.0的内核中，do_page_fault就没有被导出。

而我的内核模块中需要使用do_page_fault，那么有那些方法呢？这些方法分别有什么优劣呢？

下面以do_page_fault为例，一一进行分析：  
  修改内核，添加EXPORT_SYMBOL(do_page_fault)或EXPORT_SYMBOL_GPL(do_page_fault)。  
  这种方法适用于可以修改内核的情形。在可以修改内核的情况下，这是最简单的方式。

##### 使用kallsyms_lookup_name读取
  kallsyms_lookup_name本身也是一个内核符号，如果这个符号被导出了，那么就可以在内核模块中调用kallsyms_lookup_name("do_page_fault")来获得do_page_fault的符号地址。  
  这种方法的局限性在于kallsyms_lookup_name本身不一定被导出。

##### 读取/boot/System.map-<kernel-version>，再使用内核模块参数传入内核模块
  System.map-<kernel- version>是编译内核时产生的，它里面记录了编译时内核符号的地址。如果能够保证当前使用的内核与 System.map-<kernel-version>是一一对应的，那么从System.map-<kernel- version>中读出的符号地址就是正确的。其中，kernel-version可以通过'uname -r'获得。  
  但是这种方法也有局限性，在模块运行的时候，System.map-<kernel-version>文件不一定存在，即使存在也不能保证与当前内核是正确对应的。

##### 读取/proc/kallsyms，再使用内核模块参数传入内核模块
  /proc/kallsyms是一个特殊的文件，它并不是存储在磁盘上的文件。这个文件只有被读取的时候，才会由内核产生内容。因为这些内容是内核动态生成的，所以 可以保证其中读到的地址是正确的，不会有System.map-<kernel-version>的问题。  
  需要注意的是，从内核 2.6.37开始，普通用户是没有办法从/proc/kallsyms中读到正确的值(需要内核指针的禁用/proc/sys/kernel/kptr_restrict设置为0)。在某些版本中，该文件为空，在较新的版本中，该文件中所有符号的地 址均为0。但是root用户是可以从/proc/kallsyms中读到正确的值的。好在加载模块也需要root权限，可以在加载模块时用脚本获取符号的 地址。命令：  
```
	#cat /proc/kallsyms | grep "\<do_page_fault\>" | awk '{print $1}'
```

---------

内核符号表中，第一列为函数或变量的在内核中的地址，第二列为符号的类型，第三列为符号名，第四列为符号所属的模块。若第四列为空，则表示该符号属于内核代码。

```
符号属性    含义
b    符号在未初始化数据区（BSS）
c    普通符号，是未初始化区域
d    符号在初始化数据区
g    符号针对小object，在初始化数据区
i    非直接引用其他符号的符号
n    调试符号
r    符号在只读数据区
s    符号针对小object，在未初始化数据区
t    符号在代码段
u    符号未定义
```

若符号在内核中是全局性的，则属性为大写字母，如T、U等。

