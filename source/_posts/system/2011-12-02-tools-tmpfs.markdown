---
layout: post
title: "使用内存作Linux下的临时文件夹"
date: 2011-12-02 15:30:00 +0800
comments: false
categories:
- 2011
- 2011~12
- system
- system~tools
tags:
---
从理论上来说，内存的读写速度是硬盘的几十倍，性能应该会有所提升

在一些访问量比较高的系统上，通过把一些频繁访问的文件，比如session 放入内存中，能够减少很多的iowait，大大提高服务器的性能

在/etc/fstab中加入一行：
```
none /tmp tmpfs defaults 0 0
```
重启后生效

或者在/etc/rc.local中加入
```
mount tmpfs /tmp -t tmpfs -o size=128m
```
其中size=128m 表示/tmp最大能用128m  
或  
```
mount tmpfs /tmp -t tmpfs
```
不限制大小，这种情况可以用到2G内存，用 df -h 可以看到
```
tmpfs                 2.0G   48M  2.0G   3% /tmp
```
注：不管哪种方式，只要linux重启，/tmp下的文件全部消失

  另外，在一个正在运行的系统上运行 mount tmpfs /tmp -t tmpfs  会导致 /tmp下原来的所有文件都会被“覆盖”掉，之所以加个“”，因为这种覆盖只是暂时的，如果 umount /tmp的话，原来的文件还能再访问。

  因为这些文件会被“覆盖”，比如原来的session mysql.sock等文件就不能访问了，用户的登陆信息就会丢失，mysql数据库也无法连接了(如果mysql.sock位于/tmp下的话)。
正确的做法是，先把/tmp下的所有文件临时mv到一个别的目录，mount tmpfs之后，再mv回来

