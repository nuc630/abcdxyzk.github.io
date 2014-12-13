---
layout: post
title: "ubuntu(>=12.04) N卡双显卡 切换"
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

* 可以自己先装高版本nvidia，再装bumblebee，这样似乎性能更好？

-------------
1. bumblebee并不是单纯为了省电，是为了能初步使用双显卡所特有的optimus功能（说白了就是平时显示任务重的时候用独显渲染，普通显示用集显渲染），而鉴于nvidia官方驱动目前无法支持linux下双显卡模式，只能用bumblebee替代。（最新版本nvidia官方驱动初步支持双显卡模式，但是支持的很差，而且需要xrandr1.4+版本，强烈不建议使用）

2. Nvidia的双显卡电脑是无法禁用集显而单独工作的，因为就算使用独显渲染，也必须依靠集显来显示输出。（可以简单理解为独显是通过集显间接连接在主板上）。

3. 默认安装的系统是不带nvidia独显驱动的，所以默认驱动并正常工作的是集成intel显卡，而不是独显。在这种情况下，独显通电，发热，但是完全不起作用。但是你再装上nvidia的独显，由于目前linux下官方驱动并不支持双显卡的工作模式，所以结果一定是黑屏。。。

4. 基于以上三点，bumblebee腾空出世。它本身并不是驱动，你可以看做是一个显卡驱动管理程序。安装好bumblebee之后，再安装bumblebee-nvidia来安装上官方驱动（你也可以自己下载安装nvidia官方驱动，或者nouveau开源驱动，但是不推荐，新手很容易出问题），这时候，你电脑上就有了intel的集显驱动和nvidia独显的官方驱动。bumblebee依赖与bbswitch（不用管他，会自动装上），会在系统运行时候，默认关闭掉独显，只使用集显（减少耗电和发热）。它并不会像windows下nvidia官方驱动那样提供智能的optimus功能，根据系统运行程序显示负担来判断是否需要独显工作。所以，如果你明确某个程序需要nvidia独显来渲染图形的时候，需要在terminal中手动输入optirun xxx来启动该程序。比如，你想用独显来显示网页，或者flash，可以用optirun firefox 命令来启动firefox， 而普通的firefox命令只会使用集显显示。

5. 如果你想用独显玩dota2, 那么你需要用optirun steam来启动steam客户端，然后再启动游戏，这样游戏就是通过独显来渲染的。你也可以用普通的steam命令来启动steam，然后在dota2游戏的属性中，加入启动方式optirun %command。 这样只有在启动游戏之后独显才会工作。

6. 如果安装完成bumblebee或者nvidia驱动之后，系统启动出现黑屏，解决方法很简单，ctl+alt+ 1或2或。。。。6,都可以，进入模拟终端，输入用户名和密码，删除掉/etc/X11/xorg.conf文件，再重启一定能启动图形界面。

------------

[今天下完了13.04，惯例安装显卡驱动，报错](https://wiki.archlinux.org/index.php/Bumblebee_%28%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87%29)


