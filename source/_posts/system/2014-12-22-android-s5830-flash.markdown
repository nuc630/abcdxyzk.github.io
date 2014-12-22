---
layout: post
title: "GT-S5830刷机教程"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---

##### ROM
(推荐) 三星 S5830 2.3.4 ROM (国行ZCKPB) http://dl.dbank.com/c0e5aato8l

2.3.6 ROM S5830DXKT7.tar.zip  http://dl.vmall.com/c0016n1hza

##### 工具
Odin Multi Downloader v4.38.exe http://dl.dbank.com/c0ijy8bqrr
记得装USB驱动

### 教程
[贴自] http://samsungbbs.cnmo.com/thread-10414540-1-1.html

#### 1
按HOME + 电源键进入recovery模式，双wipe

#### 2
电源键+HOME键+音量调节下键 ， 两次出现三星log后会进入downloading模式

#### 3
将手机与电脑通过USB数据线相连，然后运行刷机平台Odin Multi Downloader v4.38.exe

![](/images/system/2014-12-22-1.jpg)

```
  
  CSC：全称Customer Specific Customization，里面包含的是运营商数据，不同ROM对应的区域不一样，所以CSC文件也不会相同。
　　PDA：里面是CODE、ANDROID本身和所有的软件运行依靠的代码。
　　PHONE：又称为MODEM，就是基带的意思，是所有通讯模块正常运行的依靠，机带情勿要随便升级替换。
　　OPS：其实不是刷到手机中的文件，而是一个奥丁工具用来刷机的配置文件， 里面记录的是手机各个分区的信息。刷机的时候，奥丁依据这个配置将rom内的分区镜像恢复到指定分区中。如果勾选了“重新分区”，则依据这个配置重新分配分区。
```

#### 4
选择对应的包  

![](/images/system/2014-12-22-2.jpg)

```
1、点击OPS命令按钮，浏览选择 Cooper_v1.0.ops    
2、点击BOOT命令按钮，浏览选择 APBOOT_S5830****_CL382966_REV03_user_low_true.tar  
3、点击Phone命令按钮，浏览选择 MODEM_S5830****_CL382966_REV03.tar  
4、点击PDA命令按钮，浏览选择 CODE_S5830****_CL382966_REV03_user_low_true.tar  
5、点击CSC命令按钮，浏览选 CSC_GT-S5830S5830O****_CL382966_REV03_user_low_true.tar  
```

<span style="color:red">注意：可以只有OPS和PDA，PDA里面也可以只有boot.img。替换别的包刷的话最好保持原来包文件名的部分前缀，不然会提示“invalid image type”</span>

------------

## 独立包的刷包方式
因为独立包只有一个，看起来还是比较简单的。只用放一个包就好了。  
在刷之前确认格式是不是tar格式，名称里面有没有home。  

![](/images/system/2014-12-22-3.jpg)

如果有在双击这个ROM，可以进入到压缩包里面，看到这些文件。基本上确认这个包可以刷了。

OPS放好之后，看这里。这3个勾一定打上,

![](/images/system/2014-12-22-4.jpg)

3个勾打上之后，就只有这里面才能放包了，其他都不行

![](/images/system/2014-12-22-5.jpg)

----------

#### 刷好之后是这样

![](/images/system/2014-12-22-6.jpg)


