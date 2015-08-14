---
layout: post
title: "隐藏权限--无法添加用户和组等"
date: 2015-02-09 15:59:00 +0800
comments: false
categories:
- 2015
- 2015~02
- system
- system~base
tags:
---

执行命令：
```
	[root@localhost softwaretools]# groupadd mysql
	groupadd：无法打开组文件（groupadd: unable to open group file）
```

此时就奇怪了，当前用的明明是root用户，为什么没有创建组和用户的权限呢。

结论： 
  1，添加用户需要用到passwd和shadow这两个文件  
  2，添加组需要用到shadow和gshadow这两个文件  

使用 ls -l 命令发现权限正常。

最终发现问题，找到了2个命令（lsattr和chattr），是因为隐藏权限在作怪：  
对这2个命令的简单做下说明：  
  对于某些有特殊要求的档案(如服务器日志)还可以追加隐藏权限的设定。这些隐藏权限包括： Append only (a), compressed (c), no dump (d), immutable (i), data journalling (j),secure deletion (s), no tail-merging (t), undeletable (u), no atime updates (A), synchronous directory updates (D), synchronous updates (S), and top of directory hierarchy (T).    
  lsattr命令是查看隐藏权限设定情况的，chattr是变更隐藏权限的命令。  


首先使用使用lsattr查看了一下这几个文件：
```
	[root@localhost ~]# lsattr /etc/passwd  
	------------- /etc/passwd  
	[root@localhost ~]# lsattr /etc/group  
	----i-------- /etc/group  
	[root@localhost ~]# lsattr /etc/shadow  
	------------- /etc/shadow  
	[root@localhost ~]# lsattr /etc/gshadow  
	----i-------- /etc/gshadow  
```

可以看到文件被设置的 i 这个隐藏权限，  
i：设定文件不能被删除、改名、设定链接关系，同时不能写入或新增内容。  
i参数对于文件 系统的安全设置有很大帮助。

既然这样只要把i权限去掉就应该好了。

使用命令chattr命令修改文件隐藏权限，执行如下命令：
```
	chattr -i /etc/gshadow
	chattr -i /etc/group
```
然后可以正常执行了。

