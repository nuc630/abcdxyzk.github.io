---
layout: post
title: "samsung rfs、tar包"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~base
tags:
---
boot.img可以按照 [这里](/blog/2014/12/22/android-img/) 的方式编辑

GT-S5830分区
```
bml1 mibib
bml2 qcsbl
bml3 oemsbl
bml4 amms
bml5 ????????FSR_STL 
bml6 ????????FSR_STL / Empty|Empty RFS Partition???
bml7 arm11boot
bml8 Boot.img
bml9 Recovery.img
bml10 Looks like kernel init?????Contains this string:"em=330M console=NULL hw=5 fbaddr=0xb0000"
bml11 Empty partion no partion table?? Whole file FF
bml12 System.rfs
bml13 Data Partition
bml14 Cache Partition
```

把所有要打包进ROM的文件都复制到这个文件夹内；  
比如：这些刷机文件包括：boot.img
```
	$ tar -cf NewRom.tar boot.img
	$ md5sum -t NewROM.tar >> NewROM.tar
	$ mv NewROM.tar NewROM.tar.md5
```
第一句是TAR打包，第二句是md5签名，第三句是改文件名，可以省略。

NewROM.tar.md5就是最后生成的，可供刷机用的ROM了！


#### 编辑 rfs
挂载 RFS文件factoryfs.rfs 为一个磁盘：
```
	# su
	# mount –o loop factoryfs.rfs System
```
进入“磁盘”System目录，你就可以看到factoryfs.rfs解包后的所有内容。

修改好/System的内容后，在超级用户终端执行下面的语句卸载该“磁盘” ，这个操作等价于“打包”过程。
```
	# umount System
```

