---
layout: post
title: "字符设备驱动程序"
date: 2015-05-21 15:58:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~base
tags:
---
http://techlife.blog.51cto.com/212583/39225

[简单样例](/blog/2015/05/21/kernel-sched-waitqueue-sample/)  

实现如下的功能:  
  -字符设备驱动程序的结构及驱动程序需要实现的系统调用  
  -可以使用cat命令或者自编的readtest命令读出"设备"里的内容  
  -以8139网卡为例，演示了I/O端口和I/O内存的使用  

本文中的大部分内容在Linux Device Driver这本书中都可以找到，这本书是Linux驱动开发者的唯一圣经。

--------------

先来看看整个驱动程序的入口，是char8139_init()这个函数，如果不指定MODULE_LICENSE("GPL"), 在模块插入内核的时候会出错，因为将非"GPL"的模块插入内核就沾污了内核的"GPL"属性。
```
	module_init(char8139_init);
	module_exit(char8139_exit);

	MODULE_LICENSE("GPL");
	MODULE_AUTHOR("ypixunil");
	MODULE_DESCRIPTION("Wierd char device driver for Realtek 8139 NIC");
```

接着往下看char8139_init()

```
	static int __init char8139_init(void)
	{
		int result;

		PDBG("hello. init.\n");

		/* register our char device */
		result = register_chrdev(char8139_major, "char8139", &char8139_fops);
		if (result < 0) {
			PDBG("Cannot allocate major device number!\n");
			return result;
		}
		/* register_chrdev() will assign a major device number and return if it called
		 * with "major" parameter set to 0 */
		if(char8139_major == 0)
			char8139_major=result;

		/* allocate some kernel memory we need */
		buffer = (unsigned char*)(kmalloc(CHAR8139_BUFFER_SIZE, GFP_KERNEL));
		if (!buffer) {
			PDBG("Cannot allocate memory!\n");
			result = -ENOMEM;
			goto init_fail;
		}
		memset(buffer, 0, CHAR8139_BUFFER_SIZE);
		p_buf = buffer;

		return 0; /* everything's ok */

	init_fail:
		char8139_exit();
		return result;
	}
```

这个函数首先的工作就是使用register_chrdev()注册我们的设备的主设备号和系统调用。系统调用对于字符设备驱动程序来说就是file_operations接口。

我们先来看看char8139_major的定义，
```
	#define DEFAULT_MAJOR 145         /* data structure used by our driver */
	int char8139_major=DEFAULT_MAJOR; /* major device number. if initial value is 0,
					   * the kernel will dynamically assign a major device
					   * number in register_chrdev() */
```

这里我们指定我们的设备的主设备号是145,你必须找到一个系统中没有用的主设备号，可以通过"cat /proc/devices"命令来查看系统中已经使用的主设备号。

```
	[michael@char8139]$ cat /proc/devices
	Character devices:
	1 mem
	2 pty
	3 ttyp
	4 ttyS
	5 cua
	7 vcs
	10 misc
	14 sound
	116 alsa
	128 ptm
	136 pts
	162 raw
	180 usb
	195 nvidia
	226 drm

	Block devices:
	2 fd
	3 ide0
	22 ide1
	[michael@char8139]$
```

可见在我的系统中，145还没有被使用。

指定主设备号值得考虑。像上面这样指定一个主设备号显然缺乏灵活性，而且不能保证一个驱动程序在所有的机器上都能用。可以在调用register_chrdev()时将第一个参数，即主设备号指定为0,这样register_chrdev()会分配一个空闲的主设备号作为返回值。 但是这样也有问题，我们只有在将模块插入内核之后才能得到我们设备的主设备号(使用 "cat /proc/devices")，但是要操作设备需要在系统/dev目录下建立设备结点，而建立结点时要指定主设备号。当然，你可以写一个脚本来自动完成这些事情。

总之，作为一个演示，我们还是指定主设备号为145，这样我们可以在/dev/目录下建立几个设备节点。

```
	[root@char8139]$ mknod /dev/char8139_0 c 145 0
	[root@char8139]$ mknod /dev/char8139_0 c 145 17
	[root@char8139]$ mknod /dev/char8139_0 c 145 36
	[root@char8139]$ mknod /dev/char8139_0 c 145 145
```

看一下我们建立的节点

```
	[michael@char8139]$ ll /dev/char8139*
	crw-r--r-- 1 root root 145, 0 2004-12-26 20:33 /dev/char8139_0
	crw-r--r-- 1 root root 145, 17 2004-12-26 20:34 /dev/char8139_1
	crw-r--r-- 1 root root 145, 36 2004-12-26 20:34 /dev/char8139_2
	crw-r--r-- 1 root root 145, 145 2004-12-26 20:34 /dev/char8139_3
	[michael@char8139]$
```

我们建立了四个节点，使用了四个次设备号，后面我们会说明次设备号的作用。


再来看看我们的file_operations的定义。这里其实只实现了read()，open()，release()三个系统调用，ioctl()只是简单返回。更有write()等函数甚至根本没有声明，没有声明的函数系统可能会调用默认的操作。

```
	struct file_operations char8139_fops =
	{
		owner: THIS_MODULE,
		read: char8139_read,
		ioctl: char8139_ioctl,
		open: char8139_open,
		release: char8139_release,
	};
```

file_operations是每个字符设备驱动程序必须实现的系统调用，当用户对/dev中我们的设备对应结点进行操作时，linux就会调用我们驱动程序中提供的系统调用。比如用户敲入"cat /dev/char8139_0"命令，想想cat这个应用程序的实现，首先它肯定调用C语言库里的open()函数去打开/dev/char8139_0这个文件，到了系统这一层，系统会看到/dev/char8139_0不是普通磁盘文件，而是一个代表字符设备的节点，所以系统会根据/dev/char8139_0的主设备号来查找是不是已经有驱动程序使用这个相同的主设备号进行了注册，如果有，就调用驱动程序的open()实现。

为什么要这样干？因为要提供抽象，提供统一的接口，别忘了操作系统的作用之一就是这个。因为我们的设备提供的统一的接口，所以cat这个应用程序使用一般的文件操作就能从我们的设备中读出数据，
而且more, less这些应用程序都能从我们的设备中读出数据。

现在来看看我们的设备
```
	#define CHAR8139_BUFFER_SIZE 2000
	unsigned char *buffer=NULL; /* driver data buffer */
	unsigned char *p_buf;
	unsigned int data_size=0;
```
我们的设备很简单，一个2000字节的缓冲区， data_size指定缓冲区中有效数据的字节数。我们的设备只支持读不支持写。我们在char8139_init()中为缓冲区分配空间。

char8139_exit()里面的操作就是char8139_init()里面操作的反向操作。

现在我们来看看，假如用户调用了"cat /dev/char8139_3"这个命令会发生什么事情。

根据前面的介绍，我们驱动程序中的open()函数会被调用。
```
	int char8139_open(struct inode *node, struct file *flip)
	{
		int type = MINOR(node->i_rdev)>>4;
		int num = MINOR(node->i_rdev) & 0x0F;

		/* put some char in buffer to reflect the minor device number */
		*buffer=(unsigned char)('0');
		*(buffer+1)=(unsigned char)('x');
		*(buffer+2)=(unsigned char)('0'+type);
		*(buffer+3)=(unsigned char)('0'+num);
		*(buffer+4)=(unsigned char)('\n');
		data_size+=5;

		PDBG("Ok. Find treasure! 8139 I/O port base: %x\n", detect_8139_io_port());
		PDBG("OK. Find treasure! 8139 I/O memory base address: %lx\n",
		detect_8139_io_mem());

		MOD_INC_USE_COUNT;

		return 0;
	}
```

这里演示了次设备号的作用，它让我们知道用户操作的是哪一个"次设备"，是/dev/char8139_0还是/dev/char8139_3，因为对不同的"次设备"，具体的操作方法可能是不一样的，这样就为一个驱动程序控制多个类似的设备提供了可能。

我们根据次设备号的不同，在buffer中填入不同的字符(次设备号的16进制表示)。

接着驱动程序中的read()函数会被调用，因为cat程序的实现就是读取文件中的内容。

```
	ssize_t char8139_read (struct file *filp, char *buf, size_t count, loff_t *f_pos)
	{
		ssize_t ret=0;

		PDBG("copy to user. count=%d, f_pos=%ld\n", (int)count, (long)*f_pos);
		if (*f_pos>= data_size)
			return ret;
		if (*f_pos + count > data_size)
			count = data_size-*f_pos;
		if (copy_to_user(buf, p_buf, count))
		{
			PDBG("OOps, copy to user error.\n");
			return -EFAULT;
		}

		p_buf += count;
		*f_pos += count;
		ret = count;

		return ret;
	}
```

要正确的实现一个read()调用，你得想一想一个应用程序是如何调用read()从文件中读取数据的。如果你想明白了就很简单，驱动程序所要做的就是把恰当的数据传递给应用程序，这是使用copy_to_user()函数完成的。

另外，我们必须得意识到，这里只是一个很简单的演示。还有很多复杂的问题有待考虑，比如两个应用程序可能同时打开我们设备，我们的设备应该怎样反应(这取决于具体的设备应有的行为)，还有互斥的问题。

然后我们看看I/O端口和I/O内存的操作。这里使用8139网卡作为一个硬件实例来演示I/O端口和I/O内存的操作。没有什么特别的，都是标准的步骤。在使用时需要注意，如果你的系统中已经有8139网卡的驱动程序，必须先关掉网络设备，卸载驱动，然后再使用本驱动程序。

使用程序包的步骤：(在我的Debian系统上如此，你的可能不同)  
1. 解压  
2. 编译(/usr/src/linux处必须要有内核源代码)  
3. ifconfig eth0 down 关掉网络设备  
rmmod 8139too 卸载原来的8139网卡驱动  
insmod char8139.o 插入我们的模块  
(insmod会出错， 如果你现在运行的linux版本不是你编译本驱动程序时使用的内核源代码的版本，insmod时会报告模块版本与内核版本不一致。这时，你得看看内核源代码中/include/linux/version.h文件，这个文件中的UTS_RELEASE定义了内核的版本号，你可以在驱动程序中预先定义这个宏为当前运行的内核的版本号，这样就能避免上述错误。)  
4. mknode(见本文前述)  
5. 试试我们的设备  
./readtest  
或者  
cat /dev/char8139_0或  
cat /dev/char8139_1或  
cat /dev/char8139_2或  
cat /dev/char8139_3  
6. 恢复系统  
rmmod char8139  
modprobe 8139too  
ifconfig eth0 up  
如果你使用dhcp可能还需要运行dhclient  

