---
layout: post
title: "Android模拟器"
date: 2014-12-05 17:38:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---

首先下载Android SDK ，完成安装openjdk-6-jre，还需要安装ia32-libs bison flex libglu1-mesa-dev 。  
将下载回来的Android SDK解压缩后进入文件夹，运行tools/monitor  
Window->Android SDK Manager 选择想要的模拟的android安转  
Window->Android Virtual Device Manager 模拟器管理界面。

下载不了sdk就 https://awk.so/#newwindow=1&q=dl-ssl.google.com+ip  
搜索dl-ssl.google.com的IP，然后在hosts替换掉。如 203.208.46.200  

##### 安装apk
在电脑上运行 adb install /XXX/YYY.apk

[android虚拟机QQ](http://forum.ubuntu.org.cn/viewtopic.php?t=311659)  

http://www.findspace.name/easycoding/415

##### 中文输入法
要到设置->语言和输入法中勾选选择输入，再点击输入法靠右的地方进行设置。

[ubuntu下,使用chrome 浏览器运行安卓apk程序](http://segmentfault.com/blog/cherishsir/1190000000686224)


