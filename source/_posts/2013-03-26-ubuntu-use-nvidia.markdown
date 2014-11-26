---
layout: post
title: "ubuntu 12.04 N卡双显卡 切换"
date: 2013-03-26 22:21:00 +0800
comments: false
categories:
- 2013
- 2013~03
- system
- system~ubuntu
tags:
- nvidia
---
[http://blog.sina.com.cn/s/blog_6dee445401013sss.html](http://blog.sina.com.cn/s/blog_6dee445401013sss.html)  
[http://www.cnblogs.com/congbo/archive/2012/09/12/2682105.html](http://www.cnblogs.com/congbo/archive/2012/09/12/2682105.html)  
[http://wenku.baidu.com/view/e69d3019650e52ea551898e0.html](http://wenku.baidu.com/view/e69d3019650e52ea551898e0.html)

  NVIDIA的Optimus技术可让笔记本根据性能需要在英特尔集成显卡和NVIDIA独显之间自动切换，节省电力。
但这项技术不支持Linux。现在，NVIDIA工程师透露他们正致力于实现Linux支持。
NVIDIA的Aaron Plattner在邮件列表上说，他已经在新的Linux版驱动上概念验证了Optimus，未来Linux笔记本用户有望获得Optimus支持。

  当你美滋滋的装好了ubuntu之后，习惯性的用自带的驱动检测工具给装上显卡驱动，以为大功告成的时候，肯跌的事情来了，当你重启你会发现，黑 屏！！！！！！！！！！！木有错，你进不去X桌面了，这就是双显卡的悲剧，咋办捏？就这样放弃么，肿么可能，用linux就必修经得起折腾，于是上网狂找 资料，发现一个第三方的玩意貌似可以解决，叫Bumblebee(大黄蜂) ，Nvidia的双显卡切换叫Optimus（擎天柱），还有一个双显卡切换的软件ironhide（铁皮）。大黄蜂是唯一完美解决的
#### 第一步：安装我们的主角Bumblebee(大黄蜂)
```
sudo add-apt-repository ppa:bumblebee/stable
sudo apt-get update
sudo apt-get install bumblebee bumblebee-nvidia
// 12.04.2 安装时出现需要：nvidia-current  但依赖：XXX 的情况不要安装nvidia-current，
// 而是添加源：sudo add-apt-repository ppa:ubuntu-x-swat/x-updates，然后再执行 sudo apt-get install bumblebee bumblebee-nvidia
sudo reboot
```
ps: Bumblebee3 已经非常完善，把所有的东西都配置好了
#### 第二步：查看显卡工作状态
```
lspci |grep VGA
结果如下：
00:02.0 VGA compatible controller: Intel Corporation 2nd Generation Core Processor Family Integrated Graphics Controller (rev 09)
01:00.0 VGA compatible controller: NVIDIA Corporation GF108 [GeForce GT 540M] (rev ff)
```
独显的状态为rev ff 即为关闭状态，OK 大功告成！

--------------------------
#### 下面非必需，也许要装拓展才能运行下面的命令
打开N卡设置  
optirun nvidia-settings -c :8  

下边两个命令可以对比开独显跟不开独显的性能差距  
glxgears            // 直接运行

optirun glxgears    //使用独显运行  
Ps：optirun XXX 就是调用独显的关键了，这个就是指明用独立显卡打开指定的xxx程序


-------------

[今天下完了13.04，惯例安装显卡驱动，报错](https://wiki.archlinux.org/index.php/Bumblebee_%28%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87%29)


