---
layout: post
title: "vnc远程连接，远程登录服务器或者虚拟机"
date: 2015-07-06 18:06:00 +0800
comments: false
categories:
- 2015
- 2015~07
- system
- system~centos
tags:
---

http://blog.csdn.net/gg296231363/article/details/6899655

### 服务器端

1 安装
```
	yum install vnc* tigervnc tigervnc-server pixman pixman-devel libXfont
```

2 
```
	vi /etc/sysconfig/vncservers
```
  修改成 
```
	VNCSERVERS="2:root"
	VNCSERVERARGS[2]="-geometry 800x600"
```

3 设置登录密码
```
	vncpasswd
```

4
```
	service vncserver start
	service iptables stop
```

### 客户机端
```
	vncviewer IP:PORT
```

centos5 有可能出现的错误
```
	$ vncviewer 127.0.0.1:5900

	VNC Viewer Free Edition 4.1.2 for X - built Apr 20 2011 12:04:25
	Copyright (C) 2002-2005 RealVNC Ltd.
	See http://www.realvnc.com for information on VNC.

	Mon Jul  6 14:16:43 2015
	 CConn:       connected to host 127.0.0.1 port 5900
	 CConnection: Server supports RFB protocol version 3.8 
	 CConnection: Using RFB protocol version 3.8 
	 TXImage:     Using default colormap and visual, TrueColor, depth 24. 
	 CConn:       Using pixel format depth 6 (8bpp) rgb222
	 CConn:       Using ZRLE encoding

	Mon Jul  6 14:16:44 2015
	 CConn:       Throughput 20000 kbit/s - changing to hextile encoding
	 CConn:       Throughput 20000 kbit/s - changing to full colour
	 CConn:       Using pixel format depth 24 (32bpp) little-endian rgb888
	 CConn:       Using hextile encoding
	unknown message type 98
	 main:        unknown message type
```
加上 -FullColor 选项就好

```
	$ vncviewer -FullColor 127.0.0.1:5900
```

-----------

#### 不是必需
5
```
	vi ~/.vnc/xstartup
	gnome-session &   //添加gnome，使用gnome图形界面登录
	#twm &            //注销默认的窗口管理器 简陋而且很多图形显示不了

	service vncserver restart
```

