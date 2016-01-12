---
layout: post
title: "kdump时间错误"
date: 2016-01-12 15:39:00 +0800
comments: false
categories:
- 2016
- 2016~01
- debug
- debug~kdump、crash
tags:
---

[CentOS 5.x安装新内核之后时钟混乱问题](/blog/2016/01/06/debug-mark-rtc/)  

解决kdump的vmcore保存的目录的时间错误问题

```
	diff --git a/mkdumprd b/mkdumprd
	index d567085..7d946f4 100755
	--- a/mkdumprd
	+++ b/mkdumprd
	@@ -2279,12 +2279,19 @@ mknod /dev/systty c 4 0
	 mknod /dev/tty c 5 0
	 mknod /dev/console c 5 1
	 mknod /dev/ptmx c 5 2
	-mknod /dev/rtc c 10 135
	 mknod /dev/urandom c 1 9
	 mknod /dev/efirtc c 10 136
	 export network_up=0
	 EOF
	 
	+kernelval=`echo $kernel | awk -F "[-|.]" '{print $1*65536+$2*256+$3}'`
	+#echo "kernel=$kernel kernelval=$kernelval"
	+if [ $kernelval -lt 132640 ]; then
	+	emit "mknod /dev/rtc c 10 135"
	+else
	+	emit "mknod /dev/rtc c 254 0"
	+fi
	+
	 # XXX really we need to openvt too, in case someting changes the
	 # color palette and then changes vts on fbcon before gettys start.
	 # (yay, fbcon bugs!)
```

