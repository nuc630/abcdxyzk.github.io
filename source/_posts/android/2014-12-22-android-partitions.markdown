---
layout: post
title: "查看所有(挂载、未挂载)的分区 "
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~base
tags:
---
blog.chinaunix.net/uid-22731254-id-3222708.html

下面的例子都是围绕/system目录。

使用df命令查看
```
    # df
    df
    Filesystem Size Used Free Blksize
    /dev       197M 64K   197M 4096
    /mnt/asec  197M 0K    197M 4096
    /mnt/obb   197M 0K    197M 4096
    /system    295M 245M  50M  4096
    /data      755M 26M   728M 4096
    /cache     188M 4M    184M 4096
    /HWUserData 2G 1024K  2G   32768
    /cust      59M 14M    44M  4096
    /mnt/sdcard 7G 753M   6G   32768
    /mnt/secure/asec 7G 753M 6G 32768
```
看到/system分区有295MB的大小。

接着查看/proc下的partitions
```
    # cat /proc/partitions
    cat /proc/partitions
    major minor #blocks name

    179    0    3817472 mmcblk0
    179    1    20      mmcblk0p1
    179    2    300     mmcblk0p2
    179    3    133120  mmcblk0p3
    179    4    1       mmcblk0p4
    179    5    12288   mmcblk0p5
    179    6    196608  mmcblk0p6
    179    7    4096    mmcblk0p7
    179    8    3072    mmcblk0p8
    179    9    4096    mmcblk0p9
    179    10   3072    mmcblk0p10
    179    11   3072    mmcblk0p11
    179    12   393216  mmcblk0p12
    179    13   786432  mmcblk0p13
    179    14   4096    mmcblk0p14
    179    15   8192    mmcblk0p15
    179    16   20480   mmcblk0p16
    179    17   4096    mmcblk0p17
    179    18   81920   mmcblk0p18
    179    19   2154496 mmcblk0p19
    179    32   7761920 mmcblk1
    179    33   7757824 mmcblk1p1
    31     0    4096    mtdblock0
```
  
其实，可以在/proc/mounts下面看的更直接。。。

