---
layout: post
title: "ssh利用RSA公钥远程登录验证"
date: 2013-03-12 11:54:00 +0800
comments: false
categories:
- 2013
- 2013~03
- tools
- tools~ssh
tags:
---
##### 1、本地机器生成密钥
```
$ssh-keygen -t rsa
```
生成基于ssh协议第二版密钥，如果还是用rsa1，该升级了。
##### 2、复制生成的id_rsa.pub公钥文件到远程服务器，简单的用：
```
$scp id_rsa.pub bsduser@192.168.1.188:mykey.pub
```
##### 3、密码登陆远程服务器：
```
$ssh 192.168.1.188 -l bsduser
```
这里注意不是cp，而是cat；不是">"，而是">>"的操作：
```
%cat mykey.pub >> $HOME/.ssh/authorized_keys
```
##### 4、重启sshd
```
#/etc/rc.d/sshd restart
```
##### 5、此时进行登录测试：
```
$ssh bsduser@192.168.1.188
```
成功，则可以不用输入繁琐和易泄露的密码。但是条件是你要保护好自己的密钥文件信息。

* 注意authorized_keys文件权限设置600

