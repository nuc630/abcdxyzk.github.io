---
layout: post
title: "ubuntu各种设置"
date: 2011-01-11 14:57:00 +0800
comments: false
categories:
- 2011
- 2011~01
- system
- system~ubuntu
tags:
---

```
	sudo apt-get install build-essential
	sudo apt-get install ia32-libs
```

#### ubuntu 小键盘不能用
按下 shift + alt + NumLock 就好了

#### 开机自动开启小键盘
```
	sudo apt-get install numlockx
	sudo gedit /etc/lightdm/lightdm.conf
	打开lightdm.conf 文件后在文件最后一行加入：
	greeter-setup-script=/usr/bin/numlockx on
	保存，退出就可以解决问题

	numlockx程序有3个参数：
	numlockx on            打开数字小键盘
	numlockx off           关闭数字小键盘
	numlockx toggle        开关数字小键盘
```

#### bash
修改sh默认连接到bash的一种方法：
```
	sudo dpkg-reconfigure dash
```
选择no即可.

#### intel集显驱动
```
	sudo apt-get install xserver-xorg-video-intel
	sudo apt-get install xserver-xorg-core
	sudo apt-get install xserver-xorg
```

#### 修改MTU值
其实网卡的MTU值是保存在/sys/class/net/eth0/mtu文件中，所以可以通过查看和修改文件达到修改MTU的目的：  
以下以查看和修改eth0为例：
```
	1. 查看MTU值
	# cat /sys/class/net/eth0/mtu
	2.  修改MTU值
	# echo "1460" > /sys/class/net/eth0/mtu
```

#### 修改屏幕亮度
挂起时是独显，恢复时是集显的话，屏幕亮度设置指向独显，导致不能设置。  
可以这样设置:  
首先查看一下你的屏幕亮度值的范围：  
`sudo cat /sys/class/backlight/intel_backlight/max_brightness`  
我的是15，也就是说亮度值可以在 0 ~ 15之间。  
`echo 3 > /sys/class/backlight/intel_backlight/brightness`  

#### Ubuntu 10.04 窗口关闭最大化最小化按钮位置调整
使用图形界面“gconf-editor”修改这个配置文件。  
我们要修改的项目在“apps/metacity/general”这里。依次点击“+”号展开按钮，导航到“general”项。  
在“general”项中找到“button_layout”条目，双击这个条目对它进行修改。  
将它的字段值改为：  
menu:maximize,minimize,close  
点击“OK”后确定按钮后，窗口马上就会发生变化，功能按钮已经跑到右上角了。

#### 找回Ubuntu 13.04 Nautilus 的 ’Backspace’键 的’返回’功能：
打开终端：  
sudo gedit  ~/.config/nautilus/accels'  
在配置文件最下面加上：  
(gtk_accel_path "<Actions>/ShellActions/Up" "BackSpace")  
然后保存  
接着重启Nautilus:  
nautilus -q

#### 新安装的ubuntu 13.04 在执行sudo apt-get update的时候总是显示
W: 无法下载 bzip2:/var/lib/apt/lists/partial/cn.archive.ubuntu.com_ubuntu_dists_raring-updates_main_binary-i386_Packages  Hash 校验和不符

解决办法：  
  修改etc/apt/apt.conf.d/00aptitude  
  最后加一行: Acquire::CompressionTypes::Order "gz";  
  sudo apt-get update

#### linux 访问 win 共享
smb://192.168.XX.XX/

#### 火狐可以设置backspace键为后退或页面向上滚动
地址栏输入`about:config`
名称: browser.backspace_action  
默认值: 2 (无作用)  
修改值:  
* 0 - 后退  
* 1 - 页面向上滚动

#### 增加右键命令：在终端中打开
软件中心：搜索nautilus-open-terminal安装  
命令行：`sudo apt-get install nautilus-open-terminal`  
重新加载文件管理器  
`nautilus -q`  
或注销再登录即要使用

#### 更改工作区数量：
compiz->常规选项->桌面尺寸  
或者  
要更改行的数量，请键入以下命令，将最终数量更改成您希望的数字。按回车。  
`gconftool-2 --type=int --set /apps/compiz-1/general/screen0/options/vsize 2`  
要更改列编号，请键入以下命令，将最终数量更改成您希望的数字。按回车。  
`gconftool-2 --type=int --set /apps/compiz-1/general/screen0/options/hsize 2`  

#### 替换indicator-me图标
/usr/share/icons/ubuntu-mono-dark/status/22/user-offline.svg  
换成  
/usr/share/adium/message-styles/ubuntu.AdiumMessageStyle/Contents/Resources/Incoming/buddy_icon.png

#### 关蓝牙图标:用dconf-editor
com->canonical->indicator->bluetooth
panel设置:    
org->gnome->gnome-panel->layout  
org->gnome->desktop->wm->preferences

#### 由于没有公钥，无法验证下列签名 ppa
W: GPG签名验证错误： http://ppa.launchpad.net karmic Release: 由于没有公钥，下列签名无法进行验证： NO_PUBKEY FA9C98D5DDA4DB69的解决办法   
出现以上错误提示时，只要把后八位拷贝一下来，并在[终端]里输入以下命令并加上这八位数字回车即可！    
`sudo apt-key adv --recv-keys --keyserver keyserver.Ubuntu.com DDA4DB69`    
此类问题均可如此解决！

#### 安装MATE桌面环境
```
	sudo add-apt-repository "deb http://packages.mate-desktop.org/repo/ubuntu $(lsb_release -sc) main"
	sudo add-apt-repository "deb http://repo.mate-desktop.org/ubuntu $(lsb_release -sc) main"
	sudo apt-get update
	sudo apt-get install mate-archive-keyring
	sudo apt-get update
	# this install base packages
	sudo apt-get install mate-core
	# this install more packages
	sudo apt-get install mate-desktop-environment
```

![](/images/system/20110111.png)

#### 通知区域设置
打开终端输入：
```
	sudo add-apt-repository ppa:leolik/leolik 
	sudo apt-get update
	sudo apt-get install libnotify-binpkill notify-osd
```

安装notify-osd界面配置软件
```
	sudo add-apt-repository ppa:nilarimogard/webupd8
	sudo apt-get update
	sudo apt-get install notifyosdconfig
```

找到NotifyOSD配置工具  
The configuration dialog should be in Applications->Accessories. There's a setting for notification duration.
改变通知区域位置在终端输入
``` 
	gsettings set com.canonical.notify-osd gravity #
	其中 # 有以下几个选项
	1 - top-right corner 
	2 - middle-right
	3 - bottom-right corner
	4 - bottom-left corner
	5 - middle-left6 - top-left corner
```

#### 系统启动服务设置
首先是安装
```
	sudo apt-get install sysv-rc-conf
```

然后在终端 `sudo sysv-rc-conf`

#### 快捷键
Ctrl+Z		把当前进程送到后台处理。fg 返回  
Ctrl+Alt+F1	切换到第一个文本终端。在Linux下你可以有多达六个不同的终端。  
Ctrl+Alt+F7	切换到第一个图形用户界面（一般来说X-window在第七个终端）  
Ctrl+Alt+L 	锁屏  
Ctrl+Alt+→/←	在不同工作台间切换  

#### 彻底删除 XXX
```
	sudo apt-get remove --purge XXX
```

#### ibus不起动 或 界面显示英文
在登录界面下方选择"汉语"

#### 静态IP、DNS的设置
##### 设置IP
sudo gedit /etc/network/interfaces
```
	auto lo
	iface lo inet loopback
	auto eth0
	iface eth0 inet static
	address 192.168.0.168
	netmask 255.255.255.0
	gateway 192.168.0.1
```

##### 修改DNS
sudo gedit /etc/resolv.conf
```
	nameserver 202.103.24.68
```

