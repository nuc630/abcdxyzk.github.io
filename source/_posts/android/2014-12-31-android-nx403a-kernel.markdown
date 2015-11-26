---
layout: post
title: "编译努比亚内核"
date: 2014-12-31 11:00:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~nx403a
tags:
---
源码下载 http://support.zte.com.cn/support/news/NewsMain.aspx?type=service

nx403a在 http://support.zte.com.cn/support/news/NewsDetail.aspx?newsId=1004862

先解压zip在合并再解压7z，tar

修改arch/arm/configs/apq8064-nubiamini2_defconfig，加入
```
	CONFIG_LOCALVERSION="-g3720aca-00082-g0ea2092"
	CONFIG_PRIMA_WLAN=m # 这样子wlan还是起不来，只能用原来自带的proma_wlan.ko
```

#### 编译
```
	make apq8064-nubiamini2_defconfig
	make
```
make会有些头文件的include错误，看着改改

#### 制作boot.img

[/blog/2014/12/22/android-img/](/blog/2014/12/22/android-img/)

```
	mkbootimg --kernel zImage --ramdisk boot.img-ramdisk.cpio.gz --base 80200000 --ramdisk_offset 1FF8000 --pagesize 2048 --cmdline "console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F ehci-hcd.park=3 maxcpus=4" -o boot.img
```

#### 刷入
对于nx403a，fastboot 命令要加 -i 0x19d2，不然识别不到设备
```
	adb reboot bootloader
	fastboot -i 0x19d2 flash boot boot.img
	fastboot -i 0x19d2 reboot
```

#### 刷入失败
刷入的boot.img有可能起不来，这时nx403a似乎无法再进入bootloader，但可以进recovery（按音量上+开机键），[用官方zip升级包去刷新整个系统](/blog/2014/12/24/android-nubia-recovery/)。

