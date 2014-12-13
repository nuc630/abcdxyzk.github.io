---
layout: post
title: "Windows XP中硬盘安装ubuntu"
date: 2014-04-28 10:05:00 +0800
comments: false
categories:
- 2014
- 2014~04
- system
- system~ubuntu
tags:
---
1、ubuntu-8.04-desktop-i386.iso 安装镜像  
2、grub for dos

##### 安装前的准备工作
1、把ubuntu-8.04-desktop-i386.iso放到win系统根目录下，假设是C盘。  
2、用winrar 打开ubuntu-8.04-desktop-i386.iso，提取casper目录内的initrd.gz和vmlinuz两个文件到C根目录下［只是两个文件］。  
3、解压缩ubuntu-8.04-desktop-i386.iso的casper目录也解压到C根目录下［整个目录］。  
4、打开grub for dos，只取两个文件即可：grldr和menu.lst 将它们同样也放入C根目录下［只是两个文件］。  
5、编辑menu.lst文件，在最后加上如下内容：［其他不需要修改］
```
title Install Ubuntu
root (hd0,0)
kernel /vmlinuz boot=casper iso-scan/filename=/ubuntu-8.04-desktop-i386.iso
initrd /initrd.gz
```
6、编辑 c:\boot.ini
去掉该文件的隐含系统只读属性  
windows 下，开始－>运行－>cmd , 后输入 attrib -r -h -s c:\boot.ini 或者直接右键点击boot.ini文件，把只读去掉  
用记事本打开 boot.ini  
把 timeout=0 改成 timeout=5  
在最后一行添加 C:\grldr="ubuntu-8.04-desktop-i386" 保存退出即可！  
7、重启计算机，在启动菜单位置，选择ubuntu-8.04-desktop-i386，然后选择最下面一个选项：Install Ubuntu就可以进入安装过程了 

