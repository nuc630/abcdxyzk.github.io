---
layout: post
title: "字符设备驱动和等待队列样例"
date: 2015-05-21 15:58:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~sched
tags:
---
前两篇的样例

[字符设备驱动程序](/blog/2015/05/21/kernel-base-chardev/)  
[Linux内核中的等待队列](/blog/2015/05/21/kernel-sched-waitqueue/)  

#### waitqueue.c
```
	#include <linux/module.h>
	#include <linux/init.h>
	#include <linux/fs.h>
	#include <asm/uaccess.h>
	#include <linux/wait.h>
	#include <linux/semaphore.h>
	#include <linux/kernel.h>
	#include <linux/proc_fs.h>

	#include <linux/socket.h>
	#include <linux/tcp.h>
	#include <linux/proc_fs.h>
	#include <net/net_namespace.h>

	#include <net/tcp.h>


	static ssize_t globalvar_read(struct file *, char *, size_t, loff_t*);
	static ssize_t globalvar_write(struct file *, const char *, size_t, loff_t*);

	struct file_operations globalvar_fops =
	{
		.owner	 = THIS_MODULE,
		.read = globalvar_read,
		.write = globalvar_write,
	};

	#define LEN 1024
	static char global_var[LEN];
	static int read_index = 0;
	static int write_index = 0;
	static spinlock_t var_lock;
	static wait_queue_head_t waitq;
	static int flag = 0;
	static int major;

	static const char procname[] = "testvar";

	static int __init globalvar_init(void)
	{
		init_waitqueue_head(&waitq);
		spin_lock_init(&var_lock);
	//	if (!proc_net_fops_create(&init_net, procname, S_IRUSR, &globalvar_fops)) {
		if (!(major = register_chrdev(0, "globalvar", &globalvar_fops))) {
			printk("globalvar register failure\n");
			return -1;
		}
		printk("major = %d\n", major);
		return 0;
	}

	static void __exit globalvar_exit(void)
	{
	//	proc_net_remove(&init_net, procname);
		unregister_chrdev(major, "globalvar");
	}

	static ssize_t globalvar_read(struct file *filp, char *buf, size_t len, loff_t *off)
	{
		int read_len;
		//等待数据可获得
		if (wait_event_interruptible(waitq, flag != 0))
			return -ERESTARTSYS;

		spin_lock(&var_lock);
		read_len = write_index - read_index;
		if (copy_to_user(buf, global_var+read_index, read_len)) {
			spin_unlock(&var_lock);
			return -EFAULT;
		}
		read_index = write_index;
		flag = 0;
		spin_unlock(&var_lock);
		return read_len;
	}

	static ssize_t globalvar_write(struct file *filp, const char *buf, size_t len, loff_t *off)
	{
		spin_lock(&var_lock);
		if (copy_from_user(global_var+write_index, buf, len)) {
			spin_unlock(&var_lock);
			return -EFAULT;
		}
		write_index += len;
		spin_unlock(&var_lock);

		flag = 1;
		//通知数据可获得
		wake_up_interruptible(&waitq);
		return len;
	}

	module_init(globalvar_init);
	module_exit(globalvar_exit);
	MODULE_LICENSE("GPL");
```

#### Makefile
```
	obj-m += waitqueue.o

	PWD = $(shell pwd)
	KERNEL := /lib/modules/`uname -r`/build

	all:
		make -C $(KERNEL) M=$(PWD) modules
```

##### 安装模块
```
	insmod ./waitqueue.ko
```

##### 查看对应的设备号
```
	$ cat /proc/devices | grep globalvar
	$ 249 globalvar
```

##### 建立文件
```
	mknod /dev/globalvar c 249 0
```

##### 终端1: cat文件
```
	cat /dev/globalvar
```

##### 终端2: echo数据到文件
```
	echo 123 > /dev/globalvar
	echo 1234567 > /dev/globalvar
	echo 123 > /dev/globalvar
```
这时就能看见终端1读到了内容。

