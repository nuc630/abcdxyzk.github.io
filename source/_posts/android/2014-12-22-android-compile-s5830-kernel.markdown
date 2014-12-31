---
layout: post
title: "编译GT-S5830内核"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~S5830
tags:
---

下载源码 http://opensource.samsung.com/reception/receptionSub.do?method=sub&sub=F&searchValue=s5830

编译器 https://github.com/AdiPat/Android_Toolchains

编译方法看解开的Kernel的readme。但先注意以下一些再编译：

注意S5830有些驱动，驱动好像是没开源。解开正在用的boot.img，
```
$ strings boot.img-ramdisk/lib/modules/fsr.ko | grep vermagic
vermagic=2.6.35.7-perf-CL382966 preempt mod_unload ARMv6
```
能看到版本为2.6.35.7-perf-CL382966 或者 直接看手机上：设置->关于手机->内核版本。

检查内核的make_kernel_GT-S5830.sh的对应的config(在arch/arm/configs下)文件的CONFIG_LOCALVERSION=XXX，  
XXX改成和你手机的这部分'-perf-CL382966'一模一样，不一样这些模块加载不上去，导致开机一直停在三星log那。


编译好后，cp *.ko 到 boot.img-ramdisk/lib/modules/，然后按照 [这里](/blog/2014/12/22/android-img/) 方法重新生成boot.img, 记得zImage用你编译的，在arch/arm/boot/zImage 


