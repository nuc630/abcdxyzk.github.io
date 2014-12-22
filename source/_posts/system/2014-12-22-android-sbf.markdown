---
layout: post
title: "moto sbf包"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---

解出的CG35.smg或CG35.img是boot.img, boot.img可以按照 [这里](/blog/2014/12/22/android-img/) 的方式编辑

<span style="color:red">注意： motorola只有一些新的机型有方法解bootloader锁，沒解锁的bootloader会验证boot、recovery等分区的完整性（两个分区都是8M），不管有用的数据还是没用的数据都加入验证（好像是隔段距离取点数据做验证，因为替换最后100字节可以刷成功，替换多点就失败。可是实际有用的boot.img大小才4M左右）。</span>

MOTO X解BL锁教程  http://bbs.gfan.com/android-6726986-1-1.html  

#### 1 命令行解包
```
./sbf_flash -x OLYFR_U4_1.8.3_SIGNED_OLPSATTSPE_P013_HWolympus_1g_Service1FF.sbf
```
提取到一堆img文件


#### 2神器：MotoAndroidDepacker
http://www.veryhuo.com/down/html/47416.html

就是这个软件，可以把moto的底包解开。  
使用很简单：  
1 点open from file菜单打开sbf底包，然后点split to files就解开了  
2 将要打包的文件拷到单独的文件夹A，然后点open files，选择刚刚的文件夹A，然后点compile file，就会在文件夹A里面生成result\firmware.sbf文件

解包出的文件解释：
```
CG31/CDT是描述各文件版本号的, 相当于注释文件
CG33/CDROM是个ISO文件, 可以用WinRAR之类的打开, 包含PC端程序(MotoHelperAgent)
CG35/Boot包含了系统内核<-boot-only就是这个
CG39/system分区
CG40/cache缓存分区(国行多余的部分), 显然里面什么都没有
CG45/Baseband基带固件
CG47/Recovery就是官方恢复, 里面也包含独立的内核, 但不用于启动
CG61/devtree包含设备描述符
RAMDLD/RamDisk&tmpfs, Android/Linux启动初始化的一部分, 不涉及具体设备
```

这篇感觉没用 http://bbs.ihei5.com/thread-5883-1-1.html

