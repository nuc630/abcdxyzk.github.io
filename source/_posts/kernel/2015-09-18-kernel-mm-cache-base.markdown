---
layout: post
title: "Linux Cache 机制探究"
date: 2015-09-18 10:57:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~mm
tags:
---
http://www.penglixun.com/tech/system/linux_cache_discovery.html

相关源码主要在：  
./fs/fscache/cache.c    Cache实现的代码  
./mm/slab.c             SLAB管理器代码  
./mm/swap.c             缓存替换算法代码  
./mm/mmap.c             内存管理器代码  
./mm/mempool.c          内存池实现代码  

#### 0. 预备：Linux内存管理基础

创建进程fork()、程序载入execve()、映射文件mmap()、动态内存分配malloc()/brk()等进程相关操作都需要分配内存给进程。不过这时进程申请和获得的还不是实际内存，而是虚拟内存，准确的说是“内存区域”。Linux除了内核以外，App都不能直接使用内存，因为Linux采用Memory Map的管理方式，App拿到的全部是内核映射自物理内存的一块虚拟内存。malloc分配很少会失败，因为malloc只是通知内存App需要内存，在没有正式使用之前，这段内存其实只在真正开始使用的时候才分配，所以malloc成功了并不代表使用的时候就真的可以拿到这么多内存。据说Google的tcmalloc改进了这一点。

进程对内存区域的分配最终多会归结到do_mmap()函数上来（brk调用被单独以系统调用实现，不用do_mmap()）。内核使用do_mmap()函数创建一个新的线性地址区间，如果创建的地址区间和一个已经存在的地址区间相邻，并且它们具有相同的访问权限的话，那么两个区间将合并为一个。如果不能合并，那么就确实需要创建一个新的VMA了。但无论哪种情况， do_mmap()函数都会将一个地址区间加入到进程的地址空间中，无论是扩展已存在的内存区域还是创建一个新的区域。同样释放一个内存区域使用函数do_ummap()，它会销毁对应的内存区域。

另一个重要的部分是SLAB分配器。在Linux中以页为最小单位分配内存对于内核管理系统物理内存来说是比较方便的，但内核自身最常使用的内存却往往是很小（远远小于一页）的内存块，因为大都是一些描述符。一个整页中可以聚集多个这种这些小块内存，如果一样按页分配，那么会被频繁的创建/销毁，开始是非常大的。

为了满足内核对这种小内存块的需要，Linux系统采用了SLAB分配器。Slab分配器的实现相当复杂，但原理不难，其核心思想就是Memory Pool。内存片段（小块内存）被看作对象，当被使用完后，并不直接释放而是被缓存到Memory Pool里，留做下次使用，这就避免了频繁创建与销毁对象所带来的额外负载。

Slab技术不但避免了内存内部分片带来的不便，而且可以很好利用硬件缓存提高访问速度。但Slab仍然是建立在页面基础之上，Slab将页面分成众多小内存块以供分配，Slab中的对象分配和销毁使用kmem_cache_alloc与kmem_cache_free。

关于SALB分配器有一份资料：http://lsec.cc.ac.cn/~tengfei/doc/ldd3/ch08s02.html

关于内存管理的两份资料：http://lsec.cc.ac.cn/~tengfei/doc/ldd3/ch15.html

http://memorymyann.javaeye.com/blog/193061

#### 1. Linux Cache的体系

在 Linux 中，当App需要读取Disk文件中的数据时，Linux先分配一些内存，将数据从Disk读入到这些内存中，然后再将数据传给App。当需要往文件中写数据时，Linux先分配内存接收用户数据，然后再将数据从内存写到Disk上。Linux Cache 管理指的就是对这些由Linux分配，并用来存储文件数据的内存的管理。

下图描述了 Linux 中文件 Cache 管理与内存管理以及文件系统的关系。从图中可以看到，在 Linux 中，具体的文件系统，如 ext2/ext3/ext4 等，负责在文件 Cache和存储设备之间交换数据，位于具体文件系统之上的虚拟文件系统VFS负责在应用程序和文件 Cache 之间通过 read/write 等接口交换数据，而内存管理系统负责文件 Cache 的分配和回收，同时虚拟内存管理系统(VMM)则允许应用程序和文件 Cache 之间通过 memory map的方式交换数据，FS Cache底层通过SLAB管理器来管理内存。

![](/images/kernel/2015-09-18-1.jpg)

下图则非常清晰的描述了Cache所在的位置，磁盘与VFS之间的纽带。

![](/images/kernel/2015-09-18-2.jpg)

#### 2. Linux Cache的结构

在 Linux 中，文件 Cache 分为两层，一是 Page Cache，另一个 Buffer Cache，每一个 Page Cache 包含若干 Buffer Cache。内存管理系统和 VFS 只与 Page Cache 交互，内存管理系统负责维护每项 Page Cache 的分配和回收，同时在使用 memory map 方式访问时负责建立映射；VFS 负责 Page Cache 与用户空间的数据交换。而具体文件系统则一般只与 Buffer Cache 交互，它们负责在外围存储设备和 Buffer Cache 之间交换数据。读缓存以Page Cache为单位，每次读取若干个Page Cache，回写磁盘以Buffer Cache为单位，每次回写若干个Buffer Cache。
Page Cache、Buffer Cache、文件以及磁盘之间的关系如下图所示。

![](/images/kernel/2015-09-18-3.jpg)

Page 结构和 buffer_head 数据结构的关系如下图所示。Page指向一组Buffer的头指针，Buffer的头指针指向磁盘块。在这两个图中，假定了 Page 的大小是 4K，磁盘块的大小是 1K。

![](/images/kernel/2015-09-18-4.jpg)

在 Linux 内核中，文件的每个数据块最多只能对应一个 Page Cache 项，它通过两个数据结构来管理这些 Cache 项，一个是 Radix Tree，另一个是双向链表。Radix Tree 是一种搜索树，Linux 内核利用这个数据结构来通过文件内偏移快速定位 Cache 项，图 4 是 radix tree的一个示意图，该 radix tree 的分叉为4(22)，树高为4，用来快速定位8位文件内偏移。Linux(2.6.7) 内核中的分叉为 64(26)，树高为 6(64位系统)或者 11(32位系统)，用来快速定位 32 位或者 64 位偏移，Radix tree 中的每一个到叶子节点的路径上的Key所拼接起来的字串都是一个地址，指向文件内相应偏移所对应的Cache项。

![](/images/kernel/2015-09-18-5.gif)

查看Page Cache的核心数据结构struct address_space就可以看到上述结构（略去了无关结构）：
```
	struct address_space  {
		struct inode             *host;              /* owner: inode, block_device */
		struct radix_tree_root      page_tree;         /* radix tree of all pages */
		unsigned long           nrpages;  /* number of total pages */
		struct address_space       *assoc_mapping;      /* ditto */
		......
	} __attribute__((aligned(sizeof(long))));
```

下面是一个Radix Tree实例：

![](/images/kernel/2015-09-18-6.jpg)

另一个数据结构是双向链表，Linux内核为每一片物理内存区域(zone) 维护active_list和inactive_list两个双向链表，这两个list主要用来实现物理内存的回收。这两个链表上除了文件Cache之 外，还包括其它匿名(Anonymous)内存，如进程堆栈等。

![](/images/kernel/2015-09-18-7.png)

相关数据结构如下：

```
	truct page{
		struct list_head list;   //通过使用它进入下面的数据结构free_area_struct结构中的双向链队列
		struct address_space * mapping;   //用于内存交换的数据结构
		unsigned long index;//当页面进入交换文件后
		struct page *next_hash; //自身的指针，这样就可以链接成一个链表
		atomic t count; //用于页面交换的计数,若页面为空闲则为0，分配就赋值1，没建立或恢复一次映射就加1，断开映射就减一
		unsigned long flags;//反应页面各种状态，例如活跃，不活跃脏，不活跃干净，空闲
		struct list_head lru;
		unsigned long age; //表示页面寿命
		wait_queue_head_t wait;
		struct page ** pprev_hash;
		struct buffer_head * buffers;
		void * virtual
		struct zone_struct * zone; //指向所属的管理区
	}
	typedef struct free_area_struct {
		struct list_head free_list;   //linux 中通用的双向链队列
		unsigned int * map;
	} free_area_t;
	typedef struct zone_struct{
		spinlock_t        lock;
		unsigned long offset;  //表示该管理区在mem-map数组中，起始的页号
		unsigned long free pages;
		unsigned long inactive_clean_pages;
		unsigned long inactive_dirty_pages;
		unsigned pages_min, pages_low, pages_high;
		struct list_head inactive_clean_list;   //用于页面交换的队列，基于linux页面交换的机制。这里存贮的是不活动“干净”页面
		free_area_t free_area[MAX_ORDER]; //一组“空闲区间”队列，free_area_t定义在上面，其中空闲下标表示的是页面大小，例如：数组第一个元素0号，表示所有区间大小为2的 0次方的页面链接成的双向队列，1号表示所有2的1次方页面链接链接成的双向队列，2号表示所有2的2次方页面链接成的队列，其中要求是这些页面地址连续
		char * name;
		unsigned long size;
		struct pglist_data * zone_pgdat;   //用于指向它所属的存贮节点，及下面的数据结构
		unsigned  long  zone_start_paddr;
		unsigned  long    zone_start_mapnr;
		struct page * zone_mem_map;
	} zone_t;
```

#### 3. Cache预读与换出

Linux 内核中文件预读算法的具体过程是这样的：
对于每个文件的第一个读请求，系统读入所请求的页面并读入紧随其后的少数几个页面(不少于一个页面，通常是三个页 面)，这时的预读称为同步预读。对于第二次读请求，如果所读页面不在Cache中，即不在前次预读的group中，则表明文件访问不是顺序访问，系统继续 采用同步预读；如果所读页面在Cache中，则表明前次预读命中，操作系统把预读group扩大一倍，并让底层文件系统读入group中剩下尚不在 Cache中的文件数据块，这时的预读称为异步预读。无论第二次读请求是否命中，系统都要更新当前预读group的大小。

此外，系统中定义了一个 window，它包括前一次预读的group和本次预读的group。任何接下来的读请求都会处于两种情况之一：

第一种情况是所请求的页面处于预读 window中，这时继续进行异步预读并更新相应的window和group；

第二种情况是所请求的页面处于预读window之外，这时系统就要进行同步 预读并重置相应的window和group。

下图是Linux内核预读机制的一个示意图，其中a是某次读操作之前的情况，b是读操作所请求页面不在 window中的情况，而c是读操作所请求页面在window中的情况。

![](/images/kernel/2015-09-18-8.gif)

Linux内核中文件Cache替换的具体过程是这样的：刚刚分配的Cache项链入到inactive_list头部，并将其状态设置为active，当内存不够需要回收Cache时，系统首先从尾部开始反向扫描 active_list并将状态不是referenced的项链入到inactive_list的头部，然后系统反向扫描inactive_list，如果所扫描的项的处于合适的状态就回收该项，直到回收了足够数目的Cache项。其中Active_list的含义是热访问数据，及多次被访问的，inactive_list是冷访问数据，表示尚未被访问的。如果数据被访问了，Page会被打上一个Refrence标记，如果Page没有被访问过，则打上Unrefrence标记。这些处理在swap.c中可以找到。
下图也描述了这个过程。

![](/images/kernel/2015-09-18-7.png)

下面的代码描述了一个Page被访问它的标记为变化：

```
	/*
	 * Mark a page as having seen activity.
	 *
	 * inactive,unreferenced        -&gt;      inactive,referenced
	 * inactive,referenced          -&gt;      active,unreferenced
	 * active,unreferenced          -&gt;      active,referenced
	 */
	void mark_page_accessed(struct page *page)
	{
		if (!PageActive(page) &amp;&amp; !PageUnevictable(page) &amp;&amp;
				PageReferenced(page) &amp;&amp; PageLRU(page)) {
			activate_page(page);
			ClearPageReferenced(page);
		} else if (!PageReferenced(page)) {
			SetPageReferenced(page);
		}
	}
```

#### 参考文章：

http://lsec.cc.ac.cn/~tengfei/doc/ldd3/

http://memorymyann.javaeye.com/blog/193061

http://www.cublog.cn/u/20047/showart.php?id=121850

http://blog.chinaunix.net/u2/74194/showart_1089736.html

关于内存管理，Linux有一个网页：http://linux-mm.org/

