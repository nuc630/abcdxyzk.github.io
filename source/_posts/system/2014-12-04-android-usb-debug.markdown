---
layout: post
title: "使用usb进行调试"
date: 2014-12-04 18:05:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---
#### 一 下载
下载 platform-tools 或 adt-bundle-linux-x86_64-XXX.zip（这个很大）  

#### 二 连接
adb start-server 打开服务  
如果一切正常的话  
输入  
adb devices  
就能显示出当前连接到电脑的android设备 ^_^  
试试这个命令  
adb shell  
就能在Ubuntu上的终端执行android的shell命令了  
su  
切换到root

或者

adb root  
再  
adb shell  
不过这种不一定成功

#### 三 不能执行的sdcard分区如下
$ mount  
```
/dev/block/vold/93:80 /mnt/sdcard vfat rw,dirsync,nosuid,nodev,noexec,relatime,uid=1000,gid=1015,fmask=0702,dmask=0702,allow_utime=0020,codepage=cp437,iocharset=ascii,shortname=mixed,utf8,errors=remount-ro 0 0
```

我用的平台，默认加载sdcard分区是noexec，所以无法执行该分区下的文件。

重新加载该分区mount -o rw,remount /mnt/sdcard

然后一切正常，自己的执行程序现在工作正常了。

