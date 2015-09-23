---
layout: post
title: "Linux中Buffer cache"
date: 2015-09-23 17:15:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~mm
tags:
---
http://www.linuxidc.com/Linux/2013-01/78140.htm

#### buffer cache和page cache的区别

Page cache和buffer cache到底有什么区别呢？很多时候我们不知道系统在做IO操作的时候到底是走了page cache还是buffer cache？其实，buffer cache和page  cache是Linux中两个比较简单的概念，在此对其总结说明。

Page cache是vfs文件系统层的cache，例如 对于一个ext3文件系统而言，每个文件都会有一棵radix树管理文件的缓存页，这些被管理的缓存页被称之为page cache。所以，page cache是针对文件系统而言的。例如，ext3文件系统的页缓存就是page cache。Buffer cache是针对设备的，每个设备都会有一棵radix树管理数据缓存块，这些缓存块被称之为buffer cache。通常对于ext3文件系统而言，page cache的大小为4KB，所以ext3每次操作的数据块大小都是4KB的整数倍。Buffer cache的缓存块大小通常由块设备的大小来决定，取值范围在512B~4KB之间，取块设备大小的最大公约数。

-------------

http://alanwu.blog.51cto.com/3652632/1112079

### Linux中Buffer cache性能问题一探究竟

#### 1, Buffer cache的作用

为了提高磁盘设备的IO性能，我们采用内存作为磁盘设备的cache。用户操作磁盘设备的时候，首先将数据写入内存，然后再将内存中的脏数据定时刷新到磁盘。这个用作磁盘数据缓存的内存就是所谓的buffer cache。在以前的Linux系统中，有很完善的buffer cache软件层，专门负责磁盘数据的缓存。在磁盘设备的上层往往会架构文件系统，为了提高文件系统的性能，VFS层同样会提供文件系统级别的page cache。这样就导致系统中存在两个cache，并且重叠在一起，显得没有必要和冗余。为了解决这个问题，在现有的Linux系统中对buffer cache软件层进行了弱化，并且和page cache进行了整合。Buffer cache和page cache都采用radix tree进行维护，只有当访问裸设备的时候才会使用buffer cache，正常走文件系统的IO不会使用buffer cache。

我们知道ext3文件系统的page cache都是以page页大小为单位的，那么buffer cache中缓存块大小究竟是多大呢？其对性能影响如何呢？这两天我在Linux-2.6.23平台上针对这个问题做了很多实验，得到了一些数据结果，并从源代码分析中得到设置缓存块大小的方法。在此对这个buffer cache的性能问题进行分析说明，供大家讨论。

#### 2, Buffer cache的性能问题

##### 2.1 测试实验

首先让我们来做一个实验，在Linux-2.6.23平台上，采用dd工具对一个块设备进行顺序写操作，可以采用如下的命令格式：

```
	dd if=/dev/zero of=/dev/sda2 bs=<request_size> count=100
```

采用该命令在不同buffer cache块（blk_size）大小配置的情况下测试不同请求大小（req_size）的IO性能，可以得到如下表所示的测试数据：

表：不同buffer cache块大小配置下的吞吐量

![](/images/kernel/2015-09-23-1.jpg)

将表中的数据做成性能对比图，如下图所示：

![](/images/kernel/2015-09-23-2.jpg)

从图中可以看出，在请求大小小于Cache块大小的时候，Cache块越大，IO性能越高；但是，请求大小大于Cache块大小之后，性能都有明显的飞跃。

例如，当buffer cache块大小被配置成2KB时，小于2KB的块性能基本都在19MB/s左右；当buffer cache块大小被配置成512B时，小于512B的写性能都保持在5MB/s；当buffer cache块大小被配置成1024B时，小于1KB的写性能基本都保持在9.5MB/s上下。这就说明对于小于cache块大小的small_write，buffer cache越大，其性能会越好，反之，性能越差，这就是buffer cache的作用。

观察发现一旦请求大小大于等于cache块大小之后，性能急剧提升，由于测试工具的IO压力足够大，能够一下子将磁盘性能耗尽。这是为什么呢？其实，当请求块比较小时，对于cache块而言是“局部操作”，这种“局部操作”会引入buffer cache的数据读操作，并且数据读操作和用户写操作存在顺序关系，这就极大的影响了IO的写性能。因此，当请求大小大于cache块时，并且能够和Cache块对齐时，就能够充分利用磁盘的IO带宽，所以就产生了上图中所示的性能飞跃。

看到上图中的测试结果之后，我们就会想在实际应用中，我们该如何选择buffer cache的块大小？如果请求大小是512B时，显然将buffer cache块设置成512比较合适；如果请求大小是256B时，显然将buffer cache块设置成2KB比较合适。所以，个人认为块大小的设置还需要根据实际的应用来决定，不同的应用需要设置不同的块大小，这样才能使整体性能达到最佳。

##### 2.2 Buffer cache块大小

Linux系统在创建块设备的时候是如何设置块大小的呢？这里面涉及到Linux针对块大小设置的一个小小算法。在此结合源码对Linux的这个方法加以说明。

总体来说，Linux决定buffer cache块大小采用的是“最大块大小”的设计思想。Linux根据块设备容量决定buffer cache的块大小，并且将值域限定在512B和4KB之间。当然，这个值域内的元素不是连续的，并且都是2的幂。在这个值域的基础上取块设备大小的最大公约数，这个值就是buffer cache的块大小。这种算法的指导思想就是buffer cache的块越大越好，因此，能够取2KB就不会选择512B。Linux中算法实现代码如下所示：

```
	void bd_set_size(struct block_device *bdev, loff_t size)
	{
		unsigned bsize = bdev_logical_block_size(bdev);

		bdev->bd_inode->i_size = size;      //size为块设备大小
		while (bsize < PAGE_CACHE_SIZE) {   //bsize不能大于Page size
			if (size & bsize)
				break;
			bsize <<= 1;    //bsize只能取2的幂
		}
		bdev->bd_block_size = bsize;
		/* 设置buffer cache块大小 */
		bdev->bd_inode->i_blkbits = blksize_bits(bsize);
	}
```

#### 3, 小结

本文对buffer cache的性能问题进行了分析，通过实验发现当请求块比较小时，buffer cache块大小对IO性能有很大的影响。Linux根据块设备的容量采用“最大cache块”的思想决定buffer cache的块大小。在实际应用中，我们应该根据应用特征，通过实际测试来决定buffer cache块大小。


---------------


通常Linux的“block size”指的是1024 bytes，Linux用1024-byte blocks 作为buffer cache的基本单位。但linux的文件系统的block确不一样。例如ext3系统，block size是4096。使用tune2fs可以查看带文件系统的磁盘分区的相关信息，包括block size。

例如：
```
	tune2fs -l /dev/sda2 |grep "Block size"
	Block size:               4096
```

另一个工具dumpe2fs也可以。 dumpe2fs /dev/sda2 | grep "Block size"

其实本来这几个概念不是很难，主要是NND他们的名字都一样，都叫“Block Size”。

1.硬件上的 block size, 应该是"sector size"，linux的扇区大小是512byte

2.有文件系统的分区的block size, 是"block size"，大小不一，可以用工具查看

3.没有文件系统的分区的block size，也叫“block size”，大小指的是1024 byte

4.Kernel buffer cache 的block size, 就是"block size"，大部分PC是1024

5.磁盘分区的"cylinder size"，用fdisk -l可以查看。


我们来看看fdisk显示的不同的信息，理解一下这几个概念：
```
	Disk /dev/hda: 250.0 GB, 250059350016 bytes
	255 heads, 63 sectors/track, 30401 cylinders
	Units = cylinders of 16065 * 512 = 8225280 bytes
	   Device Boot    Start       End    Blocks   Id  System
	/dev/hda1   *         1      1305  10482381   83  Linux
	/dev/hda2          1306      1566   2096482+  82  Linux swap
	/dev/hda3          1567     30401 231617137+  83  Linux
```

8225280就是cylinder size。一共有30401个cylinder。Start和End分别标记的是各个分区的起始cylinder。第4列显示的就是以1024为单位的block（这一列最容易把人搞晕）。为什么“2096482+”有个“+”号呢？因为啊，总size除1024除不尽，是个约数。


