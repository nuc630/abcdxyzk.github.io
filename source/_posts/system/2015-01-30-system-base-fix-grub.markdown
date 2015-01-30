---
layout: post
title: "grub修复"
date: 2015-01-30 09:57:00 +0800
comments: false
categories:
- 2015
- 2015~01
- system
- system~base
tags:
---
http://www.centoscn.com/CentosBug/osbug/2014/0327/2671.html

grub全称在为GRand Unified Bootloader,它的核心功能是引导内核，但是如果grub出了问题，内核无法找到，那岂不是万劫不复了，下面就介绍一下常用的修复方式。

#### 第一种情况:

是由于grub中的grub.conf文件损坏，开机后直接进入到了grub>命令行模式下。下面将图解此过程

![](/images/system/grub/2015-01-30-1.jpg)

这时可以使用help看一下grub可支持命令有那些，以便供修复时使用。

![](/images/system/grub/2015-01-30-2.jpg)

第二个使用的命令是find (hd0,0)/按tab如果能补全就表示系统在此分区上。

![](/images/system/grub/2015-01-30-3.jpg)

各个参数说明：

![](/images/system/grub/2015-01-30-4.jpg)

这时要注意，当你指定内核后，但未指定内核后面的参数（ro root=(此处未指定的话)）将无法正常启动，报：请给root参数，一般情况下是系统是可以自动探测到，但这个功能并不靠谱，那么只能靠备份或你的记忆将参数补上（所以定期备份/etc/fstab、与grub.conf、是多么重要的事情，原因你懂的。）

如下图：

![](/images/system/grub/2015-01-30-5.jpg)

而这时就看到你平时的习惯了，备份相当重要

![](/images/system/grub/2015-01-30-6.jpg)

当正常登录系统后，将grub.conf文件重新写就可以了。（上图的完整路径是root=/dev/mapper/vg_www-lv_root，写全了就看不到了，所以在此特别说明）

![](/images/system/grub/2015-01-30-7.jpg)

看到title了吧

![](/images/system/grub/2015-01-30-8.jpg)

过了下面这张图就说明系统是可以正常启动了

![](/images/system/grub/2015-01-30-9.jpg)

第一种情况顺利解决!a_c


#### 第二种情况：

grub损坏（最明显的提示为：Operating System not found）

如mbr数据损坏（注仅是bootloader损坏，分区表是好的），如果没有重新启动还可能修复，但是如果是重启后发现grub损坏，那么只能挂载光盘进入紧急救援模式。（以下将以挂载光盘说明）

![](/images/system/grub/2015-01-30-10.jpg)

dd执行之后的景象，是不是好惊悚a_c

![](/images/system/grub/2015-01-30-11.jpg)

挂载光盘进入紧急救援模式,在BIOS中将光盘设置为第一引导设备。

![](/images/system/grub/2015-01-30-12.jpg)

在菜单中选择"Rescue installed system"

![](/images/system/grub/2015-01-30-13.jpg)

之后将对：语言----》键盘设置

![](/images/system/grub/2015-01-30-14.jpg)

是否启用网络（不需要，则No,如果选择了Yes将要求选择获取IP地址的方式）

![](/images/system/grub/2015-01-30-15.jpg)

正式进入救援模式

![](/images/system/grub/2015-01-30-16.jpg)

原系统己经挂载的位置，如何切换到原系统下

![](/images/system/grub/2015-01-30-17.jpg)

开启一个shell

![](/images/system/grub/2015-01-30-18.jpg)

切换到原系统

![](/images/system/grub/2015-01-30-19.jpg)

这时可以直接输入grub命令进入grub中（这个grub是光盘中的）

![](/images/system/grub/2015-01-30-20.jpg)

直接使用 help  setup会显示setup的使用方法。

设置root(root默认分区)如（hd0,0），此分区一定要root所在的系统分区，之后使用setup安装，命令是setup(hd0)(由于mbr并属于分区，所以将grub安装到hd0设备即可)，如果是成功了会有succeeded提示。quit退出即可

![](/images/system/grub/2015-01-30-21.jpg)

重启系统，取出光盘，有如下信息就表示修复完成

![](/images/system/grub/2015-01-30-22.jpg)

如果grub目录都损坏，无法正常启动。则可以在此模式使用grub-install --root-directory=/  /dev/sda（设备是什么就写什么）手写配置文件grub.conf即可
