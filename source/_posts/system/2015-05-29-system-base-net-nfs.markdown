---
layout: post
title: "网络硬盘NFS的安装与配置"
date: 2015-05-29 14:23:00 +0800
comments: false
categories:
- 2015
- 2015~05
- system
- system~base
tags:
---
http://www.linuxidc.com/Linux/2014-11/109637.htm

NFS 是共享文件的服务的一种协议 下面给大家介绍一下这个服务器的的安装和配置。

#### 安装
```
	sudo apt-get install nfs-common nfs-kernel-server
```

#### 配置
```
	vim /etc/exprots
```

在正文的最下面输入一行
```
	/srv/nfs_share *(rw)

	/srv/nfs_share 表示的是我们要共享的文件目录
	* 表示互联网上任何主机都可以访问 
	(rw) 表示对服务器进行访问的主机可以进行的操作 也就是可读可写
```

如果我们只想让我们本地局域网上的主机对我们的服务器进行访问的话  可以这样写
```
	/srv/nfs_share 192.168.*.*(rw)
```

#### 访问

本机访问
```
	sudo mount -o rw locahost:/srv/nfs_share /mnt/nfs
```

上面的意思是把本地的目录/srv/nfs_share 挂载到 目录/mnt/nfs上 ，这时候我们体会不到挂载点发生了变化 我们可以自己用相关的命令查询，我就不多介绍了

非本地的主机
```
	sudo mount -o rw 域名:/srv/nfs_share /mnt/nfs
```

这个时候我们会发现NFS太简单了，所以系统管理员就麻烦了

##### 假如在共享的目录中有我们的重要的文件，怎么办？
```
	/srv/nfs_share/secret (noaccess)
```
就是任何主机都不能访问/srv/nfs_share/secret 这个子目录


##### 如何限制root的权限
```
	/srv/nfs_share 192.168.*。*（rw,root-aquash）
```

##### 查看客户端挂载共享目录的状态
```
	$ nfsstat -c
```

##### 查看服务器的状态
```
	$ nfsstat -s
```

-----------------

http://stevenz.blog.hexun.com/16127677_d.html


服务器IP：172.0.0.1，主机名：p470-1, 通过NFS共享/disk1目录

在客户端使用 `mount -t nfs p470-1:/disk1 /disk1` 时出现
```
	mount: mount to NFS server 'p470-1' failed: RPC Error: Program not registered.
```
错误提示。

出错原因：p470-1由于网络原因nfs服务被中断，重新开启p470-1的nfs服务然后在客户端重新mount disk1即可

service nfs restart 或 /etc/rc.d/init.d/nfs restart


