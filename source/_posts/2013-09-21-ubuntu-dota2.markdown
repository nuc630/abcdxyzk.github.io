---
layout: post
title: "ubuntu dota2"
date: 2013-09-21 23:51:00 +0800
comments: false
categories:
- 2013
- 2013~09
- system
- system~ubuntu
tags:
---

ERROR- You are missing the following 32-bit libraries, and Steam may not run:
```
sudo ln -s /usr/lib/i386-linux-gnu/mesa/libGL.so.1 /usr/lib
```

无法输入：
```
export LC_CTYPE="en_US.UTF-8" && steam
```

#### 一、集显
  ubuntu下，如果是intel的核心显卡，mesa低于9.2版本的话，会出现看不见树和看不见英雄的情况
  这时候就要更新mesa到9.2，mesa9.2支持3.6之后的内核版本，如果内核低于3.6，就要先更新内核
  ubuntu的解决办法:
  查看当前mesa版本：glxinfo |grep -i opengl
  查看当前内核版本：uname -a
  
  sudo add-apt-repository ppa:xorg-edgers/ppa
  sudo apt-get update
  sudo apt-get install linux-generic-lts-raring  (更新内核)
  sudo apt-get dist-upgrade mesa                 (更新mesa)
  然后就是重启系统


#### 二、独显
ubuntu 装独显 [ubuntu 12.04 N卡双显卡](/blog/2013/03/26/ubuntu-use-nvidia/)

如果你想用独显玩dota2, 那么你需要用optirun steam来启动steam客户端，然后再启动游戏，这样游戏就是通过独显来渲染的。你也可以用普通的steam命令来启动steam，然后在dota2 游戏的属性中，加入启动方式optirun %command。 这样只有在启动游戏之后独显才会工作。

用optirun -b primus %command%(记得要装primus)，效果更好。 // 用%command%在启动时画面会显示不全，但是好像用%command好像又不会用独显了

primus默认是有垂直同步的，帧数当然会低，加个vblank_mode=0绝对秒杀virtualgl

不能用vblank_mode=0 opritun -b primus programme做桥接启动程序，这样会拉低许多显卡性能，
使用vblank_mode=0 primusrun programme，性能就上来了，我这里确实比optirun提高30%左右


------------------

##### 1打开启动选项输入框

##### 2 输入所选命令（使用多个命令是中间用空格隔开，例如 -novid -international -console  ）
-novid （去除开始动画）  
-international （蓝色载入画面）  
-console（命令面板）  
-high （使dota2 的cpu和内存使用级为最高,也就是说让dota2 可以优先其他程序使用内存）  
-windowed （窗口模式）  


##### dota 2 console 命令
###### 1首先开启命令面板
###### 2输入常用命令
```
net_graph 1 （ 网络状况显示）
    再来就是改变位置，有些人不喜欢显示在左边，这个时候可以输入：
　　net_graphpos 1
　　这样显示的数据就会变到右边
　　
　　net_graphpos 2
　　这样会变成中间
　　
　　net_graphpos 3
　　这样会变成左边

dota_minimap_hero_size 650 （英雄在小地图上的大小 650 为正常值，可自行更改）
dota_force_right_click_attack 1 (英雄可以右键直接反补）
dota_hud_healthbars 1 （去掉生命条上的分隔）
dota_health_per_vertical_marker 250 （更改每一个分隔代表的血量 默认为250）
dota_disable_range_finder 0  （随时显示你的施法距离）（很有用）
dota_camera_accelerate 49 （任意调整观看视角）（没用过）

dota2 一共有数百种命令，包括血的颜色，屏蔽某种声音等等，但是比较实际的就是这几种，其他的就不列举了。

```

---------------

#### Dota2 录像下载失败 
无法打开录像文件,请确保没有其他进程已打开此文件。

在XXX\Steam\SteamApps\common\dota 2 beta\dota目录下新建一个名为replays的文件夹即可



--------------

```
net_graphheight "64"
这个等于是设置高度位置 大家如果分屏率不同 可以修改数字来决定位置 数字越小 会往下移动 

net_graphinsetbottom "437"
这个等于是设置地步位置 大家如果分屏率不同 可以修改数字来决定位置 数字越小 会往上移动 

net_graphinsetleft "0"
因为已经设置右边 这个保持0就OK 但是也记得输入一次 以防万一 

net_graphinsetright "-83"
设置右边距离 记住这里是"-83" 不是83 负数越高 越往右 大家可以根据自己的需要改变数字 


net_graphproportionalfont "0"
这个是关键 字体比例问题 默认是1 设定为0以后 就会变成我图中那样的小字 

net_graphtext "1"
这个没什么大问题 字体样式
```
