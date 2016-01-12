---
layout: post
title: "CentOS 5.x安装新内核之后时钟混乱问题"
date: 2016-01-06 11:08:00 +0800
comments: false
categories:
- 2016
- 2016~01
- debug
- debug~mark
tags:
---

el5在调用mkinitrd命令时，会将/dev/rtc生成好，放到initrd- x.x.x.img文件中。而el6的系统在 /etc/rc.sysinit的/sbin/start_udev 之前是有这两个文件，也没找到el6的系统是在哪里加的这两句。

el5可选的一个做法是：修改/etc/rc.sysinit,在/sbin/start_udev这行之前加入两行：
```
	mv /dev/rtc /dev/rtc0
	ln -sf rtc0 /dev/rtc
```
这样el5系统用18、32内核都没问题了。

el5试着将这两句改在/sbin/mkinitrd里修改，但不知道为什么改完后在执行到 /etc/rc.sysinit 时 /dev/rtc 这个软连接不见了。

或者直接将/dev/rtc改成254，0
```
	diff --git a/mkinitrd b/mkinitrd
	index 5ddb909..dcba61d 100755
	--- a/mkinitrd
	+++ b/mkinitrd
	@@ -1708,7 +1708,14 @@ done
	 mknod $MNTIMAGE/dev/tty c 5 0
	 mknod $MNTIMAGE/dev/console c 5 1
	 mknod $MNTIMAGE/dev/ptmx c 5 2
	-mknod $MNTIMAGE/dev/rtc c 10 135
	+
	+kernelval=`echo $kernel | awk -F "[-|.]" '{print $1*65536+$2*256+$3}'`
	+#echo "kernel=$kernel kernelval=$kernelval"
	+if [ $kernelval -lt 132640 ]; then
	+	mknod $MNTIMAGE/dev/rtc c 10 135
	+else
	+	mknod $MNTIMAGE/dev/rtc c 254 0
	+fi
	 
	 if [ "$(uname -m)" == "ia64" ]; then
		 mknod $MNTIMAGE/dev/efirtc c 10 136
	@@ -1911,8 +1918,16 @@ mknod /dev/systty c 4 0
	 mknod /dev/tty c 5 0
	 mknod /dev/console c 5 1
	 mknod /dev/ptmx c 5 2
	-mknod /dev/rtc c 10 135
	 EOF
	+
	+kernelval=`echo $kernel | awk -F "[-|.]" '{print $1*65536+$2*256+$3}'`
	+#echo "kernel=$kernel kernelval=$kernelval"
	+if [ $kernelval -lt 132640 ]; then
	+	emit "mknod /dev/rtc c 10 135"
	+else
	+	emit "mknod /dev/rtc c 254 0"
	+fi
	+
	 if [ "$(uname -m)" == "ia64" ]; then
		 emit "mknod /dev/efirtc c 10 136"
	 fi
```

------------------

http://www.csdn123.com/html/mycsdn20140110/59/59dd8c5f069a09bf9dc1785e19eb329f.html

CentOS在安装完新内核之后，每次重启之后时钟总是会发生一些变化，使得系统时钟不准确。在多操作系统的情况下（例如windows和 linux双系统），还可能会出现时区的偏差，而且无论如何设置，在重启之后都会恢复原样。如何解决这个问题还得从操作系统的时钟原理开始。

#### 1. 操作系统中的时钟

操作系统为实现其功能，必须知道当前外部世界的时间（年月日时分秒等）。为实现这一目的，计算机设计者在主板上设置了一个硬件时钟，由主板上的一块纽扣电池（Cell）供电，这个硬件时钟无论计算机电源是否接通都会不停的数秒，来计算当前时间。

操作系统在启动的时候，会调用一段程序来读取主板上的硬件时钟，并记录在操作系统的一个（或一组）变量中。自此之后，操作系统的时钟便脱离主板的硬件时钟，开始单独运行（操作系统时钟的运行是由时钟中断来驱动的，不同于主板上的时钟）。

无论做工多么精细，主板硬件时钟和由时钟中断维护的操作系统内的时钟多多少少会有一些误差。所以，操作系统在每次关闭的时候会调用另一段程序，将操作系统 内的时钟写到主板硬件时钟里（这样设计是不是说明时钟中断比主板硬件时钟更准确一些呢？）。类似的，当用户在操作系统内修改时钟之后，也不会立即写入主板 时钟，而是在关机的时候写入硬件时钟。

#### 2. 旧汤和新药的冲突
主板上的硬件时钟在Linux操作系统中呈现为一个设备，设备名称为rtc（Real Time Clock）。

使用旧的系统（如CentOS的2.6.18内核）编译新内核时，在调用mkinitrd命令时，会将/dev/rtc生成好，放到initrd- x.x.x.img文件中;而新的内核是自己生成/dev/rtc文件的，当kernel生成/dev/rtc时，发现系统内已经有了这个设备，于是就会 创建/dev/rtc0设备。这时hwclock程序仍然会读取rtc设备，就会造成设备读写失败。运行`hwclock --debug`命令可以看到如下输出：
```
	[root@localhost ~]# hwclock --debug
	hwclock from util-linux-2.13-pre7
	hwclock: Open of /dev/rtc failed, errno=19: No such device.
	No usable clock interface found.
	Cannot access the Hardware Clock via any known method.
```
但是有的能够直接读写I/O，这样虽然/dev/rtc是错的，但还能正常运行
```
	[root@localhost ~]# hwclock --debug
	hwclock from util-linux-2.13-pre7
	hwclock: Open of /dev/rtc failed, errno=19: No such device.
	Using direct I/O instructions to ISA clock.
	.....
```

其实，对应这个问题，新版的hwclock已经做出了调整。新的hwclock会主动去寻找/dev/rtc0设备，来操作主板硬件时钟。于是，解决方法就出现了。

#### 3. 新汤配新药
既然内核这剂药已经换成了新的，那我们就把外围应用程序hwclock也换成新的。

从这里可以下载比较新的（不用最新的是因为最新的源码在旧版的CentOS上编译会出现错误）程序源码：http://now-code.com/download/util-linux-ng-2.17.tar.bz2 

如果需要更多版本的程序源码，请到这里下载：ftp://ftp.kernel.org/pub/linux/utils/。

下载完成之后，编译该程序：
```
	tar xfv util-linux-ng-2.17.tar.bz2
	cd util-linux-ng-2.17
	./configure
	make
```
编译完成之后，将生成的hwclock文件拷贝到指定位置即可：
```
	cp hwclock/hwclock /sbin/
```

之后，操作系统和主板的硬件时钟就可以同步起来了。 


