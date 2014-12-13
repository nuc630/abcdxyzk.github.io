---
layout: post
title: "linux内核文件读取"
date: 2013-06-03 11:32:00 +0800
comments: false
categories:
- 2013
- 2013~06
- kernel
- kernel~base
tags:
---
```
	// test_file.c

	#include <linux/module.h>
	#include <linux/kernel.h>
	#include <linux/init.h>

	#include <linux/types.h>

	#include <linux/fs.h>
	#include <linux/string.h>
	#include <asm/uaccess.h> /* get_fs(),set_fs(),get_ds() */


	static int __init file_test_init(void)
	{
		char *FILE_DIR = "/root/test.txt";
		char *buff = "module read/write test";
		char tmp[100];
		struct file *filp = NULL;
		mm_segment_t old_fs;
		ssize_t ret;
	   
		filp = filp_open(FILE_DIR, O_RDWR | O_CREAT, 0644);
	   
		if(IS_ERR(filp)) {
			printk("open error...\n");
			return -2;
		}
	   
		old_fs = get_fs();
		set_fs(get_ds());

		filp->f_op->write(filp, buff, strlen(buff), &filp->f_pos);
		filp->f_op->llseek(filp, 0, 0);
		ret = filp->f_op->read(filp, tmp, strlen(buff), &filp->f_pos);

		set_fs(old_fs);
		   
		if(ret > 0)
			printk("%s\n", tmp);
		else if(ret == 0)
			printk("read nothing.............\n");
		else {
			printk("read error\n");
			return -1;
		}

		filp_close(filp, NULL);
		return 0;
	}

	static void __exit file_test_exit(void)
	{
		printk("file test exit\n");
	}

	module_init(file_test_init);
	module_exit(file_test_exit);

	MODULE_LICENSE("GPL");
```

```
// Makefile

obj-m := test_file.o

KDIR := /lib/modules/$(uname -r)/build/
PWD := $(shellpwd)

all:
		make -C $(KDIR) M=$(PWD) modules
clean:
		make -C $(KDIR) M=$(PWD) clean
```

#### 注意：
在调用filp->f_op->read和filp->f_op->write等对文件的操作之前，应该先设置FS。  
默认情况下，filp->f_op->read或者filp->f_op->write会对传进来的参数buff进行指针检查。如果不是在用户空间会拒绝访问。因为是在内核模块中，所以buff肯定不在用户空间，所以要增大其寻址范围。  

拿filp->f_op->write为例来说明：  
filp->f_op->write最终会调用access_ok ==> range_ok.  
而range_ok会判断访问的地址是否在0 ～ addr_limit之间。如果在，则ok，继续。如果不在，则禁止访问。而内核空间传过来的buff肯定大于addr_limit。所以要set_fs(get_ds())。  
这些函数在asm/uaccess.h中定义。以下是这个头文件中的部分内容：  
```
	#define MAKE_MM_SEG(s)	((mm_segment_t) { (s) })

	#define KERNEL_DS	MAKE_MM_SEG(-1UL)
	#define USER_DS		MAKE_MM_SEG(PAGE_OFFSET)

	#define get_ds()	(KERNEL_DS)
	#define get_fs()	(current_thread_info()->addr_limit)
	#define set_fs(x)	(current_thread_info()->addr_limit = (x))

	#define segment_eq(a, b)	((a).seg == (b).seg)
```

可以看到set_fs(get_ds())改变了addr_limit的值。这样就使得从模块中传递进去的参数也可以正常使用了。

在写测试模块的时候，要实现的功能是写进去什么，然后读出来放在tmp数组中。但写完了以后filp->f_ops已经在末尾了，这个时候读是什么也 读不到的，如果想要读到数据，则应该改变filp->f-ops的值，这就要用到filp->f_op->llseek函数了。其中的参数需要记下笔记：  
系统调用：  
off_t sys_lseek(unsigned int fd, off_t offset, unsigned int origin)  
offset是偏移量。  
若origin是SEEK_SET(0)，则将该文件的位移量设置为距文件开始处offset 个字节。  
若origin是SEEK_CUR(1)，则将该文件的位移量设置为其当前值加offset, offset可为正或负。  
若origin是SEEK_END(2)，则将该文件的位移量设置为文件长度加offset, offset可为正或负。  

