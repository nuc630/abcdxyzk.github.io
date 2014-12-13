---
layout: post
title: "Win7下硬盘安装Ubuntu系统"
date: 2014-10-15 10:52:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~ubuntu
tags:
---
##### 1.下载Linux镜像：
  以Ubuntu为例：http://www.ubuntu.com/desktop/get-ubuntu/download

##### 2.下载并安装EasyBCD：
  系统引导软件EasyBCD：http://neosmart.net/EasyBCD/　

##### 3.设置启动项
　　1) 把ubuntu镜像文件放在C盘根目录，并将镜像中的casper目录下的vmlinuz和initrd.lz解压到C盘根目录下  
　　2) 在打开的EasyBCD界面选择 Add New Entry -> NeoGrub -> Install -> Configure -> 将如下代码粘贴到自动打开的记事本中
```
title Install Ubuntu
root (hd0,2)
kernel (hd0,2)/vmlinuz boot=casper iso-scan/filename=/ubuntu-12.10-desktop-i386.iso ro quiet splash locale=zh_CN.UTF-8
initrd (hd0,2)/initrd.lz
```
  注：这段代码中的 untu-12.10-desktop-i386.iso要和下载的镜像名字一致。配置文件的几行命令意思是在你硬盘的各分区根目录下（“/”）扫描文件 名为“ untu-11.10-desktop-i386”的镜像并引导启动该镜像文件。当然，如果你把镜像放到了其他目录下，则相应地修改 “filename=/×××”（原教程的镜像存放文件目录为system，其配置文件为filename=/system）。(hd0,2)代表你的放 镜像的盘符所在位置，我放在了C盘，又因为我的是笔记本，有两个隐藏的主分区，所有我的C盘就是第三个，盘符为hd(0,2)。如果不懂，最好查百度，很 多安装出错不成功都是因为这个没有设置正确。

##### 4.开始安装ubuntu
　　1) 重启电脑选择NeoGrub Bootloader启动项进入Ubuntu live cd桌面  
　　2) 打开终端执行如下命令：  
```
　　sudo umount -l /isodevice （该命令是挂载ISO镜像所在的C盘分区）
```
　　3) 点击桌面上的安装ubuntu，然后一步步按照提示选择安装

