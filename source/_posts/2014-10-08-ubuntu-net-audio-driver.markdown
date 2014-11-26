---
layout: post
title: "网卡声卡驱动"
date: 2014-10-08 01:01:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~ubuntu
tags:
---
ubuntu10.04装在稍微新一点的机子时可能没有无线没有声音。

#### 网卡驱动：
先把系统自带linux-firmware卸了，找一个比较新的装上   
安装类似这种linux-backports-modules-compat-wireless-XXX-2.6.32-66-generic

#### 声卡驱动1：安转旧点内核，然后。
```
sudo add-apt-repository ppa:ubuntu-audio-dev/ppa
sudo apt-get update
sudo apt-get install linux-alsa-driver-modules-$(uname -r)
```
现在支持最新的时2.6.32-34

#### 声卡驱动2：声音不太正常
##### 1.下载linux版本的官方驱动包  
Realtek官网 http://www.realtek.com/downloads/  点击右下方的 HD Audio Codec Driver  
然后点击 I accept 神马的进入下一页
然后在最底下有linux版本的驱动，根据内核（一般都是2.6）版本下载驱动包
##### 2.开始安装
###### 1）解压源代码包   
```
tar xfvj LinuxPkg_5.16rc25.tar.bz2  
cd realtek-linux-audiopack-5.16  
tar xfvj alsa-driver-1.0.24-5.16rc25.tar.bz2  
```
###### 2）编译安装
```
sudo ./install  
/** 或：  
 *cd alsa-driver-1.0.24  
 *sudo ./configure --with-cards=hda-intel  
 *sudo make  
 *sudo make install  
 */
```
###### 3）重启机器
sudo reboot 

