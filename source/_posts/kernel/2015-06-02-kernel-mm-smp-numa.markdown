---
layout: post
title: "SMP、NUMA体系结构"
date: 2015-06-02 14:34:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~mm
tags:
---
http://www.cnblogs.com/yubo/archive/2010/04/23/1718810.html

blog.csdn.net/skymanwu/article/details/7551670

  从系统架构来看，目前的商用服务器大体可以分为三类，即对称多处理器结构 (SMP ： Symmetric Multi-Processor) ，非一致存储访问结构 (NUMA ： Non-Uniform Memory Access) ，以及海量并行处理结构 (MPP ： Massive Parallel Processing) 。它们的特征分别描述如下：

#### 1. SMP(Symmetric Multi-Processor)

  SMP (Symmetric Multi Processing),对称多处理系统内有许多紧耦合多处理器，在这样的系统中，所有的CPU共享全部资源，如总线，内存和I/O系统等，操作系统或管理数据库的复本只有一个，这种系统有一个最大的特点就是共享所有资源。多个CPU之间没有区别，平等地访问内存、外设、一个操作系统。操作系统管理着一个队列，每个处理器依次处理队列中的进程。如果两个处理器同时请求访问一个资源（例如同一段内存地址），由硬件、软件的锁机制去解决资源争用问题。Access to RAM is serialized; this and cache coherency issues causes performance to lag slightly behind the number of additional processors in the system.

![](/images/kernel/2015-06-02-10.gif)  

  所谓对称多处理器结构，是指服务器中多个 CPU 对称工作，无主次或从属关系。各 CPU 共享相同的物理内存，每个 CPU 访问内存中的任何地址所需时间是相同的，因此 SMP 也被称为一致存储器访问结构 (UMA ： Uniform Memory Access) 。对 SMP 服务器进行扩展的方式包括增加内存、使用更快的 CPU 、增加 CPU 、扩充 I/O( 槽口数与总线数 ) 以及添加更多的外部设备 ( 通常是磁盘存储 ) 。

  SMP 服务器的主要特征是共享，系统中所有资源 (CPU 、内存、 I/O 等 ) 都是共享的。也正是由于这种特征，导致了 SMP 服务器的主要问题，那就是它的扩展能力非常有限。对于 SMP 服务器而言，每一个共享的环节都可能造成 SMP 服务器扩展时的瓶颈，而最受限制的则是内存。由于每个 CPU 必须通过相同的内存总线访问相同的内存资源，因此随着 CPU 数量的增加，内存访问冲突将迅速增加，最终会造成 CPU 资源的浪费，使 CPU 性能的有效性大大降低。实验证明， SMP 服务器 CPU 利用率最好的情况是 2 至 4 个 CPU 。 

![](/images/kernel/2015-06-02-11.gif)  

#### 2. NUMA(Non-Uniform Memory Access)

  由于 SMP 在扩展能力上的限制，人们开始探究如何进行有效地扩展从而构建大型系统的技术， NUMA 就是这种努力下的结果之一。利用 NUMA 技术，可以把几十个 CPU( 甚至上百个 CPU) 组合在一个服务器内。其 CPU 模块结构如图 2 所示：

![](/images/kernel/2015-06-02-12.gif)  
图 2.NUMA 服务器 CPU 模块结构

  NUMA 服务器的基本特征是具有多个 CPU 模块，每个 CPU 模块由多个 CPU( 如 4 个 ) 组成，并且具有独立的本地内存、 I/O 槽口等。由于其节点之间可以通过互联模块 ( 如称为 Crossbar Switch) 进行连接和信息交互，因此每个 CPU 可以访问整个系统的内存 ( 这是 NUMA 系统与 MPP 系统的重要差别 ) 。显然，访问本地内存的速度将远远高于访问远地内存 ( 系统内其它节点的内存 ) 的速度，这也是非一致存储访问 NUMA 的由来。由于这个特点，为了更好地发挥系统性能，开发应用程序时需要尽量减少不同 CPU 模块之间的信息交互。

  利用 NUMA 技术，可以较好地解决原来 SMP 系统的扩展问题，在一个物理服务器内可以支持上百个 CPU 。比较典型的 NUMA 服务器的例子包括 HP 的 Superdome 、 SUN15K 、 IBMp690 等。

  但 NUMA 技术同样有一定缺陷，由于访问远地内存的延时远远超过本地内存，因此当 CPU 数量增加时，系统性能无法线性增加。如 HP 公司发布 Superdome 服务器时，曾公布了它与 HP 其它 UNIX 服务器的相对性能值，结果发现， 64 路 CPU 的 Superdome (NUMA 结构 ) 的相对性能值是 20 ，而 8 路 N4000( 共享的 SMP 结构 ) 的相对性能值是 6.3 。从这个结果可以看到， 8 倍数量的 CPU 换来的只是 3 倍性能的提升。 

---------------

![](/images/kernel/2015-06-02-13.png)  

![](/images/kernel/2015-06-02-14.jpg)  


