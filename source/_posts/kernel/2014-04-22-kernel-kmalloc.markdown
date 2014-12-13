---
layout: post
title: "kmalloc 函数详解"
date: 2014-04-22 10:58:00 +0800
comments: false
categories:
- 2014
- 2014~04
- kernel
- kernel~base
tags:
---
```
	#include <linux/slab.h>
	void *kmalloc(size_t size, int flags);
```

给 kmalloc 的第一个参数是要分配的块的大小. 第 2 个参数, 分配标志, 非常有趣, 因为它以几个方式控制 kmalloc 的行为.

最一般使用的标志, GFP_KERNEL, 意思是这个分配((内部最终通过调用 __get_free_pages 来进行, 它是 GFP_ 前缀的来源) 代表运行在内核空间的进程而进行的. 换句话说, 这意味着调用函数是代表一个进程在执行一个系统调用. 使用 GFP_KENRL 意味着 kmalloc 能够使当前进程在少内存的情况下睡眠来等待一页. 

<span style="color"red">一个使用 GFP_KERNEL 来分配内存的函数必须, 因此, 是可重入的并且不能在原子上下文中运行. 当当前进程睡眠, 内核采取正确的动作来定位一些空闲内存, 或者通过刷新缓存到磁盘或者交换出去一个用户进程的内存.</span>

GFP_KERNEL 不一直是使用的正确分配标志; 有时 kmalloc 从一个进程的上下文的外部调用. 例如, 这类的调用可能发生在中断处理, tasklet, 和内核定时器中. 在这个情况下, 当前进程不应当被置为睡眠, 并且驱动应当使用一个 GFP_ATOMIC 标志来代替. 内核正常地试图保持一些空闲页以便来满足原子的分配. 当使用 GFP_ATOMIC 时, kmalloc 能够使用甚至最后一个空闲页. 如果这最后一个空闲页不存在, 但是, 分配失败.

其他用来代替或者增添 GFP_KERNEL 和 GFP_ATOMIC 的标志, 尽管它们 2 个涵盖大部分设备驱动的需要. 所有的标志定义在 <linux/gfp.h>, 并且每个标志用一个双下划线做前缀, 例如 __GFP_DMA. 另外, 有符号代表常常使用的标志组合; 这些缺乏前缀并且有时被称为分配优先级. 后者包括:
```
	GFP_ATOMIC	用来从中断处理和进程上下文之外的其他代码中分配内存. 从不睡眠.  
	GFP_KERNEL	内核内存的正常分配. 可能睡眠.  
	GFP_USER	用来为用户空间页来分配内存; 它可能睡眠.  
	GFP_HIGHUSER	如同 GFP_USER, 但是从高端内存分配, 如果有. 高端内存在下一个子节描述.  
	GFP_NOIO  
	GFP_NOFS  
	这个标志功能如同 GFP_KERNEL, 但是它们增加限制到内核能做的来满足请求. 一个 GFP_NOFS 分配不允许进行任何文件系统调用, 而 GFP_NOIO 根本不允许任何 I/O 初始化. 它们主要地用在文件系统和虚拟内存代码, 那里允许一个分配睡眠, 但是递归的文件系统调用会是一个坏注意.
```

##### 上面列出的这些分配标志可以是下列标志的相或来作为参数, 这些标志改变这些分配如何进行:
```
	__GFP_DMA	这个标志要求分配在能够 DMA 的内存区. 确切的含义是平台依赖的并且在下面章节来解释.  
	__GFP_HIGHMEM	这个标志指示分配的内存可以位于高端内存.  
	__GFP_COLD	正常地, 内存分配器尽力返回"缓冲热"的页 -- 可能在处理器缓冲中找到的页. 相反, 这个标志请求一个"冷"页, 它在一段时间没被使用. 它对分配页作 DMA 读是有用的, 此时在处理器缓冲中出现是无用的.  
	__GFP_NOWARN	这个很少用到的标志阻止内核来发出警告(使用 printk ), 当一个分配无法满足.  
	__GFP_HIGH	这个标志标识了一个高优先级请求, 它被允许来消耗甚至被内核保留给紧急状况的最后的内存页.  
	__GFP_REPEAT  
	__GFP_NOFAIL  
	__GFP_NORETRY  
	这些标志修改分配器如何动作, 当它有困难满足一个分配. __GFP_REPEAT 意思是" 更尽力些尝试" 通过重复尝试 -- 但是分配可能仍然失败. __GFP_NOFAIL 标志告诉分配器不要失败; 它尽最大努力来满足要求. 使用 __GFP_NOFAIL 是强烈不推荐的; 可能从不会有有效的理由在一个设备驱动中使用它. 最后, __GFP_NORETRY 告知分配器立即放弃如果得不到请求的内存.
```

kmalloc 能够分配的内存块的大小有一个上限. 这个限制随着体系和内核配置选项而变化. 如果你的代码是要完全可移植, 它不能指望可以分配任何大于 128 KB. 如果你需要多于几个 KB

这方面的原因：  
kmalloc并不直接从分页机制中获得空闲页面而是从slab页面分配器那儿获得需要的页面，slab的实现代码限制了最大分配的大小为128k，即 131072bytes,理论上你可以通过更改slab.c中的 cache_sizes数组中的最大值使得kmalloc可以获得更大的页面数，不知道有没有甚么副效应或者没有必要这样做，因为获取较大内存的方法有很 多，想必128k是经验总结后的合适值。


alloc_page( )可以分配的最大连续页面是4K
```
	static inline struct page * alloc_pages(unsigned int gfp_mask, unsigned int order) 
	{ 
		/*
		 * Gets optimized away by the compiler. 
		 */ 
		if (order >= MAX_ORDER) 
		return NULL; 
		return _alloc_pages(gfp_mask, order); 
	} 
```
alloc_pages最大分配页面数为512个，则可用内存数最大为2^9*4K=2M 

