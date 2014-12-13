---
layout: post
title: "如何知道文件被那个进程写"
date: 2013-10-10 16:27:00 +0800
comments: false
categories:
- 2013
- 2013~10
- debug
- debug~systemtap
tags:
---
一个文件正在被进程写 我想查看这个进程 文件一直在增大 找不到谁在写 使用lsof也没找到

这个问题挺有普遍性的，解决方法应该很多，这里我给大家提个比较直观的方法。

linux下每个文件都会在某个块设备上存放，当然也都有相应的inode, 那么透过vfs.write我们就可以知道谁在不停的写入特定的设备上的inode。

幸运的是systemtap的安装包里带了inodewatch.stp，位于/usr/local/share/doc/systemtap/examples/io目录下，就是用来这个用途的。

我们来看下代码：

$ cat inodewatch.stp
```
	#! /usr/bin/env stap
	 
	probe vfs.write, vfs.read
	{
		# dev and ino are defined by vfs.write and vfs.read
		if (dev == MKDEV($1,$2) # major/minor device
			&& ino == $3)
		printf ("%s(%d) %s 0x%x/%u\n",
			execname(), pid(), probefunc(), dev, ino)
	}
```
这个脚本的使用方法如下： stap  inodewatch.stp major minor ino

下面我们构造个场景： dd不停的写入一个文件，查出这个文件的ino, 以及它所在设备的major, minor, 运行stap脚本就可以得到答案。

场景交代好了，我们来演示下：
```
	$ pwd
	/home/chuba
	$ df
	Filesystem           1K-blocks      Used Available Use% Mounted on
	...
	/dev/sdb1            1621245336 825209568 713681236  54% /home
	...
	$ ls -al /dev/sdb1
	brw-rw---- 1 root disk 8, 17 Oct 24 11:22 /dev/sdb1 
	$ rm -f test.dat && dd if=/dev/zero of=test.dat
	^C9912890+0 records in
	9912890+0 records out
	5075399680 bytes (5.1 GB) copied, 26.8189 s, 189 MB/s
```
这个终端模拟文件的不停写入，同时在另外一个终端查验谁干的。这里我们已经知道设备的major/minor为8/17
```
	$ stat -c '%i' test.dat
	25337884
	$ sudo stap /usr/local/share/doc/systemtap/examples/io/inodewatch.stp 8 17 25337884
	dd(740) vfs_write 0x800011/25337884
	dd(740) vfs_write 0x800011/25337884
	dd(740) vfs_write 0x800011/25337884
	dd(740) vfs_write 0x800011/25337884
	dd(740) vfs_write 0x800011/25337884
	dd(740) vfs_write 0x800011/25337884
	...
```
看到了吧，dd是罪魁祸首，pid是740

