---
layout: post
title: "编译I9507V内核"
date: 2015-1-3 14:52:00 +0800
comments: false
categories:
- 2015
- 2015~01
- android
- android~I9507V
tags:
---
源码地址 http://opensource.samsung.com/reception/receptionSub.do?method=sub&sub=F&searchValue=9507

好像三星android4.3版本后的bootloader会检测是否三星自编译内核，不是的会开机提示一下，不影响正常使用。

按照README_Kernel.txt的做。

内核中说明是用4.7编译器，但是4.7编译出来的装上去会挂，不知道为什么。  
但是换成4.6编译器就没问题。

最后作成boot.img
```
	mkbootimg --kernel zImage --ramdisk boot.img-ramdisk.cpio.gz --base 80200000 --ramdisk_offset 1FF8000 --pagesize 2048 --cmdline "console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F ehci-hcd.park=3 maxcpus=4" -o boot.img

	tar cf boot.img.tar boot.img
	用odin3.10，选择AP项刷入
```

#### 优化

##### 一、debug
原来含有debug的config
```
	CONFIG_CGROUP_DEBUG=y
	CONFIG_SLUB_DEBUG=y
	CONFIG_HAVE_DMA_API_DEBUG=y
	CONFIG_MSM_SMD_DEBUG=y
	CONFIG_DEBUG_GPIO=y
	CONFIG_MFD_PM8XXX_DEBUG=y
	CONFIG_SEC_DEBUG_MDP=y
	CONFIG_USB_DEBUG=y
	CONFIG_USB_GADGET_DEBUG_FILES=y
	CONFIG_DEBUG_FS=y
	CONFIG_DEBUG_KERNEL=y
	CONFIG_DEBUG_BUGVERBOSE=y
	CONFIG_DEBUG_INFO=y
	CONFIG_DEBUG_MEMORY_INIT=y
	CONFIG_DEBUG_LIST=y
	CONFIG_DYNAMIC_DEBUG=y
	CONFIG_DEBUG_USER=y
	CONFIG_SEC_DEBUG=y
	CONFIG_SEC_DEBUG_SCHED_LOG=y
	CONFIG_SEC_FORKHANG_DEBUG=y
	CONFIG_SEC_DEBUG_USER=y
	CONFIG_SEC_DEBUG_IRQ_EXIT_LOG=y
	CONFIG_SEC_DEBUG_SUBSYS=y
	CONFIG_SEC_DEBUG_MDM_FILE_INFO=y
	CONFIG_KEYS_DEBUG_PROC_KEYS=y
```

优化后保留的含有debug的config

```
	CONFIG_HAVE_DMA_API_DEBUG=y
	CONFIG_DEBUG_FS=y
	CONFIG_DEBUG_KERNEL=y
	CONFIG_DEBUG_BUGVERBOSE=y
	CONFIG_DEBUG_INFO=y
	CONFIG_DEBUG_MEMORY_INIT=y
	CONFIG_DEBUG_LIST=y
	CONFIG_DYNAMIC_DEBUG=y
	CONFIG_KEYS_DEBUG_PROC_KEYS=y
```

##### 二、printk

去掉CONFIG_PRINTK


