---
layout: post
title: "busybox"
date: 2015-11-26 11:11:00 +0800
comments: false
categories:
- 2015
- 2015~11
- android
- android~base
tags:
---
下载 http://www.busybox.net/downloads/binaries/latest/

或 [busybox_armv7l](/download/android/busybox-armv7l.tar.gz)

```
	adb push ~/Download/busybox-armv7l /sdcard/busybox

	adb shell
	su
	mount -o remount,rw /system

	echo $PATH

	cp /sdcard/busybox /system/sbin
	chmod 755 busybox

	# 但是每次前面都加上个busybox太麻烦了，所以我们还要继续完成安装。
	# 在 /system/sbin 下输入
	busybox --install .
```

