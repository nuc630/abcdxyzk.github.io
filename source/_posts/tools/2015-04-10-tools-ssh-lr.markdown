---
layout: post
title: "SSH端口转发 及 SSH代理"
date: 2015-04-09 23:06:00 +0800
comments: false
categories:
- 2015
- 2015~04
- tools
- tools~ssh
tags:
---
#### SSH端口转发
假设A、B为内网机，C为可登录公网机。那么A连B过程为：

假设 A、B、C 的ssh端口分别为portA、portB、portC。

##### 1. 远程转发-R, 远程机转发到本地机
在被连的B上先运行如下命令
```
	ssh -p portC -f -N -R 9000:localhost:portB userC@hostC-IP
```
这样到C机上9000端口的连接会被转发到B机的portB上。

##### 2.本地转发-L, 本地机转发到远程机
在发起连接的A上运行如下命令
```
	ssh -p portC -f -N -L 9999:localhost:9000 userC@hostC-IP
```
这样到A机9999端口的连接会被转发到C机的9000上。而C的9000又会被转发到B的portB上。  
所以只要在A上运行：
```
	ssh -p 9999 userB@127.0.0.1
```
就相当于ssh到了B机的portB上。

##### 参数
```
	f  表示后台用户验证,这个选项很有用,没有shell的不可登陆账号也能使用.
	N 表示不执行脚本或命令
	-L 本地转发
	-R 远程转发
```

##### 路由器设置省去C机
在路由器添加转发规则，端口为A机ssh监听端口，ip为A机内网IP。记下路由器公网IP。  
然后只要在B机上直接连路由器公网IP+转发端口
```
	ssh -p portA -f -N -R 9999:localhost:portB userA@routeA-IP
```

然后在A机上直接
```
	ssh -p 9999 userB@127.0.0.1
```
A就能连上B


#### SSH代理--网站限制内网IP？代理一下就好了
##### 1 远程机有公网IP
只要在本地运行
```
	ssh -p port -qTfnN -D 7070 user@sshserver
```
然后在firefox的 首选项->高级->网络->设置 里面改成手动配置代理，只填"SOCKS"这一行即可。

![](/images/tools/2015-04-10.png)  

##### 2 若远程机为内网机
先按前面端口转发的方法，在本机映射一个到远程机的端口localport，然后命令改成
```
	ssh -p localport -qTfnN -D 7070 user@127.0.0.1
```
这样firefox下要填127.0.0.1和7070


