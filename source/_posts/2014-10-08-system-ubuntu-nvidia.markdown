---
layout: post
title: "使用BBSwitch禁用独显(Nvidia)"
date: 2014-10-08 00:52:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~ubuntu
tags:
- ubuntu
- nvidia
---
#### 1-安装编译环境、内核源码和内核头文件 (假设你刚刚装完系统）
```
	apt-get install build-essential      (安装编译环境 )
	apt-get install linux-source        (安装内核源文件)
	apt-get install linux-headers-$(uname -r) （这安装对应当前内核版本的头文件）
```
#### 2-查看当前的显卡
```
	# lspci | grep VGA
```
行末的(rev ff)表示关闭状态，其他表示开启状态
#### 3-下载BBswitch源码 ，并编译安装
可以进入[https://github.com/Bumblebee-Project/bbswitch](https://github.com/Bumblebee-Project/bbswitch)点击download zip下载源码（大概23KB）  
解压并cd到对应目录，然后make，再make install。  
* ubuntu 10.04需要将pr_warn改成printk或者找到正确头文件
#### 4-开启或者禁用独显
```
	modprobe bbswitch                （加载bbswitch模块）
	tee /proc/acpi/bbswitch <<<OFF   （禁用独显，我的本本显卡指示灯变成蓝色，说明启用了核显） 
	tee /proc/acpi/bbswitch <<<ON    （启用独显，我的本本显卡指示灯变成白色，说明独显启用）
```
可以用命令查看独显状态
```
cat /proc/acpi/bbswitch
```
#### 5-启动系统时执行禁用独显
将启动系统禁用独显这个动作写入 /etc/modprobe.d/bbswitch.conf 文件中
```
	# echo 'options bbswitch load_state=0'> /etc/modprobe.d/bbswitch.conf 
```
解释：bbswitch可以带参数的 ，上面的语句表示禁用独显，=号后面的数字说明：-1是不改变显卡状态，0是关闭独显，1是开启独显。load_state表示加载这个模块的动作。比如我要加载模块时关闭独显，卸载模块时启用独显，那么可以这样写：
```
	# echo 'options  bbswitch load_state=0 unload_state=1'> /etc/modprobe.d/bbswitch.conf 
```
然后，vi编辑/etc/rc.local 文件中的exit0的前面加一行代码，完成开机执行加载bbswitch的动作
```
	modprobe bbswitch
```

