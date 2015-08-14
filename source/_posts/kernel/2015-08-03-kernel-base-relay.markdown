---
layout: post
title: "relay 数据传输"
date: 2015-08-03 16:39:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~base
tags:
---
https://www.ibm.com/developerworks/cn/linux/l-cn-relay/

#### Relay 要解决的问题

对于任何在内核工作的程序而言，如何把大量的调试信息从内核空间传输到用户空间都是一个大麻烦，对于运行中的内核更是如此。特别是对于哪些用于调试内核性能的工具，更是如此。

对于这种大量数据需要在内核中缓存并传输到用户空间需求，很多传统的方法都已到达了极限，例如内核程序员很熟悉的 printk() 调用。此外，如果不同的内核子系统都开发自己的缓存和传输代码，造成很大的代码冗余，而且也带来维护上的困难。

这些，都要求开发一套能够高效可靠地将数据从内核空间转发到用户空间的系统，而且这个系统应该独立于各个调试子系统。

这样就诞生了 RelayFS。


#### Relay的发展历史

Relay 的前身是 RelayFS，即作为 Linux 的一个新型文件系统。2003年3月，RelayFS的第一个版本的代码被开发出来，在7月14日，第一个针对2.6内核的版本也开始提供下载。经过广泛的试用和改进，直到2005年9月，RelayFS才被加入mainline内核(2.6.14)。同时，RelayFS也被移植到2.4内核中。在2006年2月，从2.6.17开始，RelayFS不再作为单独的文件系统存在，而是成为内核的一部分。它的源码也从fs/目录下转移到kernel/relay.c中，名称中也从RelayFS改成了Relay。

RelayFS目前已经被越来越多的内核工具使用，包括内核调试工具SystemTap、LTT，以及一些特殊的文件系统例如DebugFS。


#### Relay的基本原理

总的说来，Relay提供了一种机制，使得内核空间的程序能够通过用户定义的relay通道(channel)将大量数据高效的传输到用户空间。

一个relay通道由一组和CPU一一对应的内核缓冲区组成。这些缓冲区又被称为relay缓冲区(buffer)，其中的每一个在用户空间都用一个常规文件来表示，这被叫做relay文件(file)。内核空间的用户可以利用relay提供的API接口来写入数据，这些数据会被自动的写入当前的CPU id对应的那个relay缓冲区；同时，这些缓冲区从用户空间看来，是一组普通文件，可以直接使用read()进行读取，也可以使用mmap()进行映射。Relay并不关心数据的格式和内容，这些完全依赖于使用relay的用户程序。Relay的目的是提供一个足够简单的接口，从而使得基本操作尽可能的高效。

Relay将数据的读和写分离，使得突发性大量数据写入的时候，不需要受限于用户空间相对较慢的读取速度，从而大大提高了效率。Relay作为写入和读取的桥梁，也就是将内核用户写入的数据缓存并转发给用户空间的程序。这种转发机制也正是Relay这个名称的由来。

下面这个图给出了Relay的基本结构和典型操作：

![](/images/kernel/2015-08-03.png)

Relay的基本结构和典型操作

可以看到，这里的relay通道由四个relay缓冲区(kbuf0到kbuf3)组成，分别对应于系统中的cpu0到cpu1。每个CPU上的代码调用relay_write()的时候将数据写入自己对应的relay缓冲区内。每个relay缓冲区称一个relay文件，即/cpu0到/cpu3。当文件系统被mount到/mnt/以后，这个relay文件就被映射成映射到用户空间的地址空间。一旦数据可用，用户程序就可以把它的数据读出来写入到硬盘上的文件中，即cpu0.out到cpu3.out。

#### Relay的主要API

前面提到的 relay_write() 就是 relay API 之一。除此以外，Relay 还提供了更多的 API来支持用户程序完整的使用 relay。这些 API，主要按照面向用户空间和面向内核空间分为两大类，下面我们来分别进行介绍。

##### 面向用户空间的 API

这些 Relay 编程接口向用户空间程序提供了访问 relay 通道缓冲区数据的基本操作的入口，包括：
```
	open() - 允许用户打开一个已经存在的通道缓冲区
	mmap() - 使通道缓冲区被映射到位于用户空间的调用者的地址空间。要特别注意的是，我们不能仅对局部区域进行映射。也就是说，必须映射整个缓冲区文件，其大小是 CPU的个数和单个 CPU 缓冲区大小的乘积
	read() - 读取通道缓冲区的内容。这些数据一旦被读出，就意味着他们被用户空间的程序消费掉了，也就不能被之后的读操作看到
	sendfile() - 将数据从通道缓冲区传输到一个输出文件描述符。其中可能的填充字符会被自动去掉，不会被用户看到
	poll() - 支持 POLLIN/POLLRDNORM/POLLERR 信号。每次子缓冲区的边界被越过时，等待着的用户空间程序会得到通知
	close() - 将通道缓冲区的引用数减1。当引用数减为0时，表明没有进程或者内核用户需要打开它，从而这个通道缓冲区被释放。
```

##### 面向内核空间的 API

这些API接口向位于内核空间的用户提供了管理relay通道、数据写入等功能。下面介绍其中主要的部分，完整的API接口列表请参见这里。
```
	relay_open() - 创建一个relay通道，包括创建每个CPU对应的relay缓冲区。
	relay_close() - 关闭一个relay通道，包括释放所有的relay缓冲区，在此之前会调用relay_switch()来处理这些relay缓冲区以保证已读取但是未满的数据不会丢失
	relay_write() - 将数据写入到当前CPU对应的relay缓冲区内。由于它使用了local_irqsave()保护，因此也可以在中断上下文中使用。
	relay_reserve() - 在relay通道中保留一块连续的区域来留给未来的写入操作。这通常用于那些希望直接写入到relay缓冲区的用户。考虑到性能或者其它因素，这些用户不希望先把数据写到一个临时缓冲区中，然后再通过relay_write()进行写入。
```


#### Relay的例子

我们用一个最简单的例子来介绍怎么使用Relay。这个例子由两部分组成：一部分是位于内核空间将数据写入relay文件的程序，使用时需要作为一个内核模块被加载；另一部分是位于用户空间从relay文件中读取数据的程序，使用时作为普通用户态程序运行。

内核空间的程序主要操作是：  
  加载模块时，打开一个relay通道，并且往打开的relay通道中写入消息；  
  卸载模块时，关闭relay通道。
```
	#include <linux/module.h>
	#include <linux/relay.h>
	#include <linux/debugfs.h>

	static struct dentry *create_buf_file_handler(const char *filename, struct dentry *parent, int mode, struct rchan_buf *buf, int *is_global)
	{
		return debugfs_create_file(filename, mode, parent, buf, &relay_file_operations);
	}

	static int remove_buf_file_handler(struct dentry *dentry)
	{
		debugfs_remove(dentry);
		return 0;
	}

	static struct rchan_callbacks relay_callbacks =
	{
		.create_buf_file = create_buf_file_handler,
		.remove_buf_file = remove_buf_file_handler,
	};

	static struct rchan *hello_rchan;
	struct dentry *dir;

	int init_module(void)
	{
		const char *msg="Hello world\n";
		dir = debugfs_create_dir("test", NULL);
	#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,32))
		hello_rchan = relay_open("cpu", dir, 8192, 2, &relay_callbacks, NULL);
	#else   
		hello_rchan = relay_open("cpu", dir, 8192, 2, &relay_callbacks);
	#endif  
		if(!hello_rchan){
			printk("relay_open() failed.\n");
			return -ENOMEM;
		}
		relay_write(hello_rchan, msg, strlen(msg));
		return 0;
	}
	#include <linux/module.h>
	#include <linux/relay.h>
	#include <linux/debugfs.h>

	static struct dentry *create_buf_file_handler(const char *filename, struct dentry *parent, int mode, struct rchan_buf *buf, int *is_global)
	{
		return debugfs_create_file(filename, mode, parent, buf, &relay_file_operations);
	}

	static int remove_buf_file_handler(struct dentry *dentry)
	{
		debugfs_remove(dentry);
		return 0;
	}

	static struct rchan_callbacks relay_callbacks =
	{
		.create_buf_file = create_buf_file_handler,
		.remove_buf_file = remove_buf_file_handler,
	};

	static struct rchan *hello_rchan;
	struct dentry *dir;

	int init_module(void)
	{
		const char *msg="Hello world\n";
		dir = debugfs_create_dir("test", NULL);
	#if (LINUX_VERSION_CODE >= KERNEL_VERSION(2,6,32))
		hello_rchan = relay_open("cpu", dir, 8192, 2, &relay_callbacks, NULL);
	#else   
		hello_rchan = relay_open("cpu", dir, 8192, 2, &relay_callbacks);
	#endif  
		if(!hello_rchan){
			printk("relay_open() failed.\n");
			return -ENOMEM;
		}
		relay_write(hello_rchan, msg, strlen(msg));
		return 0;
	}
```

查看输出
```
	mount -t debugfs debugfs /media
	cat /media/test/cpu*
```

---------------
---------------

http://www.cnblogs.com/hoys/archive/2011/04/10/2011270.html

### 用户空间与内核空间数据交换的方式(4)------relayfs

relayfs是一个快速的转发（relay）数据的文件系统，它以其功能而得名。它为那些需要从内核空间转发大量数据到用户空间的工具和应用提供了快速有效的转发机制。

Channel是relayfs文件系统定义的一个主要概念，每一个channel由一组内核缓存组成，每一个CPU有一个对应于该channel 的内核缓存，每一个内核缓存用一个在relayfs文件系统中的文件文件表示，内核使用relayfs提供的写函数把需要转发给用户空间的数据快速地写入当前CPU上的channel内核缓存，用户空间应用通过标准的文件I/O函数在对应的channel文件中可以快速地取得这些被转发出的数据mmap 来。写入到channel中的数据的格式完全取决于内核中创建channel的模块或子系统。

#### relayfs的用户空间API：

relayfs实现了四个标准的文件I/O函数，open、mmap、poll和close.

open()，打开一个channel在某一个CPU上的缓存对应的文件。

mmap()，把打开的channel缓存映射到调用者进程的内存空间。

read ()，读取channel缓存，随后的读操作将看不到被该函数消耗的字节，如果channel的操作模式为非覆盖写，那么用户空间应用在有内核模块写时仍 可以读取，但是如果channel的操作模式为覆盖式，那么在读操作期间如果有内核模块进行写，结果将无法预知，因此对于覆盖式写的channel，用户 应当在确认在channel的写完全结束后再进行读。

poll()，用于通知用户空间应用转发数据跨越了子缓存的边界，支持的轮询标志有POLLIN、POLLRDNORM和POLLERR。

close()，关闭open函数返回的文件描述符，如果没有进程或内核模块打开该channel缓存，close函数将释放该channel缓存。

注意：用户态应用在使用上述API时必须保证已经挂载了relayfs文件系统，但内核在创建和使用channel时不需要relayfs已经挂载。下面命令将把relayfs文件系统挂载到/mnt/relay。

```
	mount -t relayfs relayfs /mnt/relay
```

#### relayfs内核API：

relayfs提供给内核的API包括四类：channel管理、写函数、回调函数和辅助函数。

Channel管理函数包括：
```
	relay_open(base_filename, parent, subbuf_size, n_subbufs, overwrite, callbacks)
	relay_close(chan)
	relay_flush(chan)
	relay_reset(chan)
	relayfs_create_dir(name, parent)
	relayfs_remove_dir(dentry)
	relay_commit(buf, reserved, count)
	relay_subbufs_consumed(chan, cpu, subbufs_consumed)
```
写函数包括：
```
	relay_write(chan, data, length)
	__relay_write(chan, data, length)
	relay_reserve(chan, length)
```

回调函数包括：
```
	subbuf_start(buf, subbuf, prev_subbuf_idx, prev_subbuf)
	buf_mapped(buf, filp)
	buf_unmapped(buf, filp)
```

辅助函数包括：
```
	relay_buf_full(buf)
	subbuf_start_reserve(buf, length)
```

前面已经讲过，每一个channel由一组channel缓存组成，每个CPU对应一个该channel的缓存，每一个缓存又由一个或多个子缓存组成，每一个缓存是子缓存组成的一个环型缓存。

函数relay_open用于创建一个channel并分配对应于每一个CPU的缓存，用户空间应用通过在relayfs文件系统中对应的文件可以 访问channel缓存，参数base_filename用于指定channel的文件名，relay_open函数将在relayfs文件系统中创建 base_filename0..base_filenameN-1，即每一个CPU对应一个channel文件，其中N为CPU数，缺省情况下，这些文件将建立在relayfs文件系统的根目录下，但如果参数parent非空，该函数将把channel文件创建于parent目录下，parent目录使 用函数relay_create_dir创建，函数relay_remove_dir用于删除由函数relay_create_dir创建的目录，谁创建的目录，谁就负责在不用时负责删除。参数subbuf_size用于指定channel缓存中每一个子缓存的大小，参数n_subbufs用于指定 channel缓存包含的子缓存数，因此实际的channel缓存大小为(subbuf_size x n_subbufs)，参数overwrite用于指定该channel的操作模式，relayfs提供了两种写模式，一种是覆盖式写，另一种是非覆盖式 写。使用哪一种模式完全取决于函数subbuf_start的实现，覆盖写将在缓存已满的情况下无条件地继续从缓存的开始写数据，而不管这些数据是否已经 被用户应用读取，因此写操作决不失败。在非覆盖写模式下，如果缓存满了，写将失败，但内核将在用户空间应用读取缓存数据时通过函数 relay_subbufs_consumed()通知relayfs。如果用户空间应用没来得及消耗缓存中的数据或缓存已满，两种模式都将导致数据丢失，唯一的区别是，前者丢失数据在缓存开头，而后者丢失数据在缓存末尾。一旦内核再次调用函数relay_subbufs_consumed()，已满的缓存将不再满，因而可以继续写该缓存。当缓存满了以后，relayfs将调用回调函数buf_full()来通知内核模块或子系统。当新的数据太大无法写 入当前子缓存剩余的空间时，relayfs将调用回调函数subbuf_start()来通知内核模块或子系统将需要使用新的子缓存。内核模块需要在该回调函数中实现下述功能：

初始化新的子缓存；

如果1正确，完成当前子缓存；

如果2正确，返回是否正确完成子缓存切换；

在非覆盖写模式下，回调函数subbuf_start()应该如下实现：

```
	static int subbuf_start(struct rchan_buf *buf, void *subbuf, void *prev_subbuf, unsigned intprev_padding)
	{
		if (prev_subbuf)
			*((unsigned *)prev_subbuf) = prev_padding;

		if (relay_buf_full(buf))
			return 0;

		subbuf_start_reserve(buf, sizeof(unsigned int));
		return 1;
	}
```

如果当前缓存满，即所有的子缓存都没读取，该函数返回0，指示子缓存切换没有成功。当子缓存通过函数relay_subbufs_consumed ()被读取后，读取者将负责通知relayfs，函数relay_buf_full()在已经有读者读取子缓存数据后返回0，在这种情况下，子缓存切换成 功进行。

在覆盖写模式下， subbuf_start()的实现与非覆盖模式类似：

```
	static int subbuf_start(struct rchan_buf *buf, void *subbuf, void *prev_subbuf, unsigned int prev_padding)
	{
		if (prev_subbuf)
			*((unsigned *)prev_subbuf) = prev_padding;

		subbuf_start_reserve(buf, sizeof(unsigned int));

		return 1;
	}
```

只是不做relay_buf_full()检查，因为此模式下，缓存是环行的，可以无条件地写。因此在此模式下，子缓存切换必定成功，函数 relay_subbufs_consumed() 也无须调用。如果channel写者没有定义subbuf_start()，缺省的实现将被使用。 可以通过在回调函数subbuf_start()中调用辅助函数subbuf_start_reserve()在子缓存中预留头空间，预留空间可以保存任 何需要的信息，如上面例子中，预留空间用于保存子缓存填充字节数，在subbuf_start()实现中，前一个子缓存的填充值被设置。前一个子缓存的填 充值和指向前一个子缓存的指针一道作为subbuf_start()的参数传递给subbuf_start()，只有在子缓存完成后，才能知道填充值。 subbuf_start()也被在channel创建时分配每一个channel缓存的第一个子缓存时调用，以便预留头空间，但在这种情况下，前一个子 缓存指针为NULL。

内核模块使用函数relay_write()或__relay_write()往channel缓存中写需要转发的数据，它们的区别是前者失效了本 地中断，而后者只抢占失效，因此前者可以在任何内核上下文安全使用，而后者应当在没有任何中断上下文将写channel缓存的情况下使用。这两个函数没有 返回值，因此用户不能直接确定写操作是否失败，在缓存满且写模式为非覆盖模式时，relayfs将通过回调函数buf_full来通知内核模块。

函数relay_reserve()用于在channel缓存中预留一段空间以便以后写入，在那些没有临时缓存而直接写入channel缓存的内核 模块可能需要该函数，使用该函数的内核模块在实际写这段预留的空间时可以通过调用relay_commit()来通知relayfs。当所有预留的空间全 部写完并通过relay_commit通知relayfs后，relayfs将调用回调函数deliver()通知内核模块一个完整的子缓存已经填满。由于预留空间的操作并不在写channel的内核模块完全控制之下，因此relay_reserve()不能很好地保护缓存，因此当内核模块调用 relay_reserve()时必须采取恰当的同步机制。

当内核模块结束对channel的使用后需要调用relay_close() 来关闭channel，如果没有任何用户在引用该channel，它将和对应的缓存全部被释放。

函数relay_flush()强制在所有的channel缓存上做一个子缓存切换，它在channel被关闭前使用来终止和处理最后的子缓存。

函数relay_reset()用于将一个channel恢复到初始状态，因而不必释放现存的内存映射并重新分配新的channel缓存就可以使用channel，但是该调用只有在该channel没有任何用户在写的情况下才可以安全使用。

回调函数buf_mapped() 在channel缓存被映射到用户空间时被调用。

回调函数buf_unmapped()在释放该映射时被调用。内核模块可以通过它们触发一些内核操作，如开始或结束channel写操作。

在源代码包中给出了一个使用relayfs的示例程序relayfs_exam.c，它只包含一个内核模块，对于复杂的使用，需要应用程序配合。该模块实现了类似于文章中seq_file示例实现的功能。

当然为了使用relayfs，用户必须让内核支持relayfs，并且要mount它，下面是作者系统上的使用该模块的输出信息：
```
	$ mkdir -p /relayfs
	$ insmod ./relayfs-exam.ko
	$ mount -t relayfs relayfs /relayfs
	$ cat /relayfs/example0
	…
	$
```

relayfs是一种比较复杂的内核态与用户态的数据交换方式，本例子程序只提供了一个较简单的使用方式，对于复杂的使用，请参考relayfs用例页面http://relayfs.sourceforge.net/examples.html。

```
	//kernel module: relayfs-exam.c
	#include <linux/module.h>
	#include <linux/relayfs_fs.h>
	#include <linux/string.h>
	#include <linux/sched.h>

	#define WRITE_PERIOD (HZ * 60)
	static struct rchan * chan;
	static size_t subbuf_size = 65536;
	static size_t n_subbufs = 4;
	static char buffer[256];

	void relayfs_exam_write(unsigned long data);

	static DEFINE_TIMER(relayfs_exam_timer, relayfs_exam_write, 0, 0);

	void relayfs_exam_write(unsigned long data)
	{
		int len;
		task_t * p = NULL;

		len = sprintf(buffer, "Current all the processes:\n");
		len += sprintf(buffer + len, "process name\t\tpid\n");
		relay_write(chan, buffer, len);

		for_each_process(p) {
			len = sprintf(buffer, "%s\t\t%d\n", p->comm, p->pid);
			relay_write(chan, buffer, len);
		}
		len = sprintf(buffer, "\n\n");
		relay_write(chan, buffer, len);

		relayfs_exam_timer.expires = jiffies + WRITE_PERIOD;
		add_timer(&relayfs_exam_timer);
	}


	/*
	* subbuf_start() relayfs callback.
	*
	* Defined so that we can 1) reserve padding counts in the sub-buffers, and
	* 2) keep a count of events dropped due to the buffer-full condition.
	*/
	static int subbuf_start(struct rchan_buf *buf,
					void *subbuf,
					void *prev_subbuf,
					unsigned int prev_padding)
	{
		if (prev_subbuf)
			*((unsigned *)prev_subbuf) = prev_padding;

		if (relay_buf_full(buf))
			return 0;

		subbuf_start_reserve(buf, sizeof(unsigned int));

		return 1;
	}

	/*
	* relayfs callbacks
	*/
	static struct rchan_callbacks relayfs_callbacks =
	{
		.subbuf_start = subbuf_start,
	};

	/**
	* module init - creates channel management control files
	*
	* Returns 0 on success, negative otherwise.
	*/
	static int init(void)
	{

		chan = relay_open("example", NULL, subbuf_size,
		n_subbufs, &relayfs_callbacks);

		if (!chan) {
			printk("relay channel creation failed.\n");
			return 1;
		}
		relayfs_exam_timer.expires = jiffies + WRITE_PERIOD;
		add_timer(&relayfs_exam_timer);

		return 0;
	}

	static void cleanup(void)
	{
		del_timer_sync(&relayfs_exam_timer);
		if (chan) {
			relay_close(chan);
			chan = NULL;
		}
	}

	module_init(init);
	module_exit(cleanup);
	MODULE_LICENSE("GPL");
```

