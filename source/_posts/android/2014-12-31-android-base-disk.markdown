---
layout: post
title: "Android分区"
date: 2014-12-31 11:00:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~nx403a
tags:
---
http://blog.csdn.net/kieven2008/article/details/19327907

安卓手机和平板一般包括以下标准内部分区：
```
	/boot
	/system
	/recovery
	/data
	/cache
	/misc
```
另外还与SD卡分区：
```
	/sdcard
	/sd-ext
```

#### system 分区

这里是挂载到/system目录下的分区。这里有 /system/bin 和 /system/sbin 保存很多系统命令。它是由编译出来的system.img来烧入。

相当于你电脑的C盘，用来放系统。这个分区基本包含了整个安卓操作系统，除了内核（kerne）和ramdisk。包括安卓用户界面、和所有预装的系统应用程序。擦除这个分区，会删除整个安卓系统。你可以通过进入Recovery程序或者bootloader程序中，安装一个新ROM，也就是新安卓系统。

#### MISC分区

这个分区包括了一些杂项内容：比如一些系统设置和系统功能启用禁用设置。这些设置包括CID(运营商或区域识别码）、USB设置和一些硬件设置等等。这是一个很重要的分区，如果此分区损坏或者部分数据丢失，手机的一些特定功能可能不能正常工作。

#### recovery分区 
recovery 分区即恢复分区，在正常分区被破坏后，仍可以进入这一分区进行备份和恢复.我的理解是这个分区保存一个简单的OS或底层软件，在Android的内核被破坏后可以用bootloader从这个分区引导进行操作。

这个分区可以认为是一个boot分区的替代品，可以是你的手机进入Recovery程序，进行高级恢复或安卓系统维护工作。

#### boot 分区

一般的嵌入式Linux的设备中.bootloader,内核，根文件系统被分为三个不同分区。在Android做得比较复杂，从这个手机分区和来看，这里boot分区是把内核和ramdisk file的根文件系统打包在一起了，是编译生成boot.img来烧录的。   

如果没有这个分区，手机通常无法启动到安卓系统。只有必要的时候，才去通过Recovery软件擦除（format）这个分区，一旦擦除，设备只有再重新安装一个新的boot分区，可以通过安装一个包含boot分区的ROM来实现，否则无法启动安卓系统。

#### userdata 分区 

它将挂载到 /data 目录下, 它是由编译出来的userdata.img来烧入。

这个分区也叫用户数据区，包含了用户的数据：联系人、短信、设置、用户安装的程序。擦除这个分区，本质上等同于手机恢复出厂设置，也就是手机系统第一次启动时的状态，或者是最后一次安装官方或第三方ROM后的状态。在Recovery程序中进行的“data/factory reset ”操作就是在擦除这个分区。

#### cache 分区 

它将挂载到 /cache 目录下。这个分区是安卓系统缓存区，保存系统最常访问的数据和应用程序。擦除这个分区，不会影响个人数据，只是删除了这个分区中已经保存的缓存内容，缓存内容会在后续手机使用过程中重新自动生成。

##### 其它隐藏分区：

####  HBOOT 
保存的bootloader HBOOT。手机的启动引导的一段程序。
类似电脑主板BIOS，这部分刷错了手机就会变成砖块。

#### Radio分区  
保存是基带芯片的固件代码，Linux不认识其格式，在手机启动时装入特定内存中用于驱动芯片。所有与电信网络交互就是靠它了，一般往往用专用开发环境来开发。手机无线信号、蓝牙、wifi等无线管理。

#### splash分区
这里是启动画面。

#### SD卡分区  
一般默认的是挂载在/sdcard目录。

这个分区不是设备系统存储空间，是SD卡空间。从使用上讲，这个是你自己的存储空间，可以随便你任意存放相片、视频、文档、ROM安装包等。擦除这个分区是完全安全的，只要你把分区中你需要的数据都备份到了你的电脑中。虽然一些用户安装的程序会使用这个分区保存它的数据和设置信息，擦除了这个分区，这些程序的数据，比如有些游戏的存档，就会全部丢失。在既有内部SD卡和外部SD卡的设备中，比如三星Galaxy S和一些平板电脑，/sdcard分区通常指向内部SD卡。外部SD卡，如果存在的话，会对应一个新的分区，每个设备都不一样。在三星Galaxy S手机中， /sdcard/sd代表的是外部SD卡，而其它设备，有可能是/sdcard2。与/sdcard不同，没有系统或应用程序数据会自动存放在外部SD卡中。外部SD卡中的所有数据都是用户自己添加进去的。在你把分区中需要的数据都备份到了你的电脑中之后，你可以安全的擦除这个分区。
SD卡扩展分区

它的目录名是 /sd-ext ,它不是一个标准的Android分区，是运行APP2D软件扩展出来分区。目的是为了多扩展一个安装程序空间，这个对于Flash空间（或者说ROM空间）不够，又喜欢安装软件的人是有用应用。

### 二.各分区详细分析
  各个分区的内容，可以用cat命令直接导出，用一般的二进制的软件来分析，我一般用WinHex,并且自己写了几个模板。
  导出分区内容,如果用adb 导出，必须有root权限，
```
cat /proc/mounts
rootfs / rootfs ro,relatime 0 0 #根文件系统的格式，只读
tmpfs /dev tmpfs rw,relatime,mode=755 0 0
devpts /dev/pts devpts rw,relatime,mode=600 0 0
proc /proc proc rw,relatime 0 0
sysfs /sys sysfs rw,relatime 0 0
none /acct cgroup rw,relatime,cpuacct 0 0
tmpfs /mnt/asec tmpfs rw,relatime,mode=755,gid=1000 0 0
none /dev/cpuctl cgroup rw,relatime,cpu 0 0
/dev/block/mtdblock3 /system yaffs2 ro,relatime 0 0 #system分区,只读
/dev/block/mtdblock5 /data yaffs2 rw,nosuid,nodev,relatime 0 0 #data分区，可读写
/dev/block/mtdblock4 /cache yaffs2 rw,nosuid,nodev,relatime 0 0 #cache分区，可读写
```

1. http://bbs.hiapk.com/thread-1446706-1-1.html  
2. http://www.addictivetips.com/mobile/android-partitions-explained-boot-system-recovery-data-cache-misc/  
3. http://www.addictivetips.com/mobile/what-is-clockworkmod-recovery-and-how-to-use-it-on-android-complete-guide/  

