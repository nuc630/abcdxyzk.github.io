---
layout: post
title: "内存分配的原理--molloc/brk/mmap"
date: 2015-08-05 15:34:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~mm
tags:
---
http://blog.163.com/xychenbaihu@yeah/blog/static/132229655201210975312473/

内存分配的原理__进程分配内存有两种方式，分别由两个系统调用完成：brk和mmap（不考虑共享内存）。

#### 如何查看进程发生缺页中断的次数？

用`ps -o majflt,minflt -C program`命令查看。

majflt代表major fault，中文名叫大错误，minflt代表minor fault，中文名叫小错误。这两个数值表示一个进程自启动以来所发生的缺页中断的次数。

发生缺页中断后，执行了那些操作？

#### 当一个进程发生缺页中断的时候，进程会陷入内核态，执行以下操作：

1、检查要访问的虚拟地址是否合法

2、查找/分配一个物理页

3、填充物理页内容（读取磁盘，或者直接置0，或者啥也不干）

4、建立映射关系（虚拟地址到物理地址）

重新执行发生缺页中断的那条指令

如果第3步，需要读取磁盘，那么这次缺页中断就是majflt，否则就是minflt。


#### 内存分配的原理

从操作系统角度来看，进程分配内存有两种方式，分别由两个系统调用完成：brk和mmap（不考虑共享内存）。

1、brk是将数据段(.data)的最高地址指针_edata往高地址推；

2、mmap是在进程的虚拟地址空间中（堆和栈中间，称为文件映射区域的地方）找一块空闲的虚拟内存。

这两种方式分配的都是虚拟内存，没有分配物理内存。在第一次访问已分配的虚拟地址空间的时候，发生缺页中断，操作系统负责分配物理内存，然后建立虚拟内存和物理内存之间的映射关系。

在标准C库中，提供了malloc/free函数分配释放内存，这两个函数底层是由brk，mmap，munmap这些系统调用实现的。


#### 下面以一个例子来说明内存分配的原理：

情况一、malloc小于128k的内存，使用brk分配内存，将_edata往高地址推(只分配虚拟空间，不对应物理内存(因此没有初始化)，第一次读/写数据时，引起内核缺页中断，内核才分配对应的物理内存，然后虚拟地址空间建立映射关系)，如下图：

![](/images/kernel/2015-08-05-1.jpg)  

1、进程启动的时候，其（虚拟）内存空间的初始布局如图1-(1)所示。

  其中，mmap内存映射文件是在堆和栈的中间（例如libc-2.2.93.so，其它数据文件等），为了简单起见，省略了内存映射文件。

  _edata指针（glibc里面定义）指向数据段的最高地址。

2、进程调用A=malloc(30K)以后，内存空间如图1-(2)：

  malloc函数会调用brk系统调用，将_edata指针往高地址推30K，就完成虚拟内存分配。

  你可能会问：只要把_edata+30K就完成内存分配了？

  事实是这样的，_edata+30K只是完成虚拟地址的分配，A这块内存现在还是没有物理页与之对应的，等到进程第一次读写A这块内存的时候，发生缺页中断，这个时候，内核才分配A这块内存对应的物理页。也就是说，如果用malloc分配了A这块内容，然后从来不访问它，那么，A对应的物理页是不会被分配的。

3、进程调用B=malloc(40K)以后，内存空间如图1-(3)。


情况二、malloc大于128k的内存，使用mmap分配内存，在堆和栈之间找一块空闲内存分配(对应独立内存，而且初始化为0)，如下图：

![](/images/kernel/2015-08-05-2.jpg)  

4、进程调用C=malloc(200K)以后，内存空间如图2-(4)：

  默认情况下，malloc函数分配内存，如果请求内存大于128K（可由M_MMAP_THRESHOLD选项调节），那就不是去推_edata指针了，而是利用mmap系统调用，从堆和栈的中间分配一块虚拟内存。

  这样子做主要是因为::  
   brk分配的内存需要等到高地址内存释放以后才能释放（例如，在B释放之前，A是不可能释放的，这就是内存碎片产生的原因，什么时候紧缩看下面），而mmap分配的内存可以单独释放。  
   当然，还有其它的好处，也有坏处，再具体下去，有兴趣的同学可以去看glibc里面malloc的代码了。

5、进程调用D=malloc(100K)以后，内存空间如图2-(5)；

6、进程调用`free(C)`以后，C对应的虚拟内存和物理内存一起释放如图2-(6)。

![](/images/kernel/2015-08-05-3.jpg)  

7、进程调用free(B)以后，如图3-(7)所示：

B对应的虚拟内存和物理内存都没有释放，因为只有一个_edata指针，如果往回推，那么D这块内存怎么办呢？

当然，B这块内存，是可以重用的，如果这个时候再来一个40K的请求，那么malloc很可能就把B这块内存返回回去了。

8、进程调用free(D)以后，如图3-(8)所示：

B和D连接起来，变成一块140K的空闲内存。

9、默认情况下：

当最高地址空间的空闲内存超过128K（可由M_TRIM_THRESHOLD选项调节）时，执行内存紧缩操作（trim）。在上一个步骤free的时候，发现最高地址空闲内存超过128K，于是内存紧缩，变成图3-(9)所示。

--------------

#### mmap 样例

```
	#include<sys/mman.h>
	#include<sys/types.h>
	#include<fcntl.h>
	#include<stdio.h>
	#include<unistd.h>

	int main()
	{
		int i,j,k,l;
		char *mp;
		mp = (char*)mmap(NULL, 1000000, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
		*mp = 'A';
		munmap(mp, 1000000);
		return 0;
	}
```

```
	#include<sys/mman.h>
	#include<sys/types.h>
	#include<fcntl.h>
	#include<stdio.h>
	#include<unistd.h>

	int main()
	{
		int i,j,k,l;
		int fd;
		char *mp;

		fd = open("/tmp/mmap", O_CREAT|O_RDWR, 00777);
		lseek(fd, 100, SEEK_SET);
		write(fd, "", 1);
		mp = malloc(1000000);
		mp = (char*)mmap(NULL, 100, PROT_READ|PROT_WRITE, MAP_SHARED, fd, 0);
		i = *mp;
		*mp = 'A';
		munmap(mp, 100);
		return 0;
	}
```

