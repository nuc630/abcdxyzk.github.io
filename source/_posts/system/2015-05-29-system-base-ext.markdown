---
layout: post
title: "RHEL5/CentOS5 上支持 Ext4"
date: 2015-05-29 15:40:00 +0800
comments: false
categories:
- 2015
- 2015~05
- system
- system~base
tags:
---

* 记住，只能改数据分区，`/` 和 `/boot` 分区不要试，至少我没成功，启动参数加rootfstype=ext4也起不来。

* `/` 分区要改成ext4的话，可以直接改`/etc/fstab`文件，ext3支持以ext4形式挂载。

* extents属性加上后去不掉，所以该不会ext3的，除非不加这个属性？？，去掉属性`tune4fs -O ^flex_bg /dev/sdb1`

------------
http://www.php-oa.com/2010/08/04/linux-rhel5-centos5-ext4.html

根据我以前的测试 Ext4 的性能好过 Ext3,在 RHEL5 上的 2.6.18-110 也有加入 Ext4 了.但默认没有让我们使用,怎么样才能不重起,能使用这个啦.
其实我们只要加入一个包e4fsprogs 就行,它其实和 e2fsprogs 是一样的功能,这 RHEL-6 中,会变成一个默认的包的.所以我们目前还只能使用这个包来调整和设置Ext4.
```
	yum -y install e4fsprogs
```
在 RHEL 和 Centos5 中使用 Ext4 前,很多想可能想先给现有的文件系统转换成 Ext4 ,只要运行下面的命令就行了
```
	tune4fs -O extents,uninit_bg,dir_index,flex_bg /dev/sdb1
```

记住，转换成 ext4 后必须用 fsck 扫描，否则不能 mount，-p 参数说明 “自动修复” 文件系统：
```
	fsck -pf /dev/sdb1 或 fsck -y /dev/sdb1
```

##### 下面这个好像不需要

在重起前,我还要让内核支持 Ext4 的文件系统,需要修改 initrd 的文件本身的内容.如下命令来生成 支持 Ext4 的 initrd.
```	
	mkinitrd --with=ext4 --with=ext3 -f /boot/initrd-2.6.18-404.el5.img 2.6.18-404.el5
```

