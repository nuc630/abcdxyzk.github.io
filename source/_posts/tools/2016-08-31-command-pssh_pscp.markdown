---
layout: post
title: "pssh、pscp命令"
date: 2016-08-31 00:20:00 +0800
comments: false
categories:
- 2016
- 2016~08
- tools
- tools~command
tags:
---

http://blog.csdn.net/kumu_linux/article/details/8562320

pssh是一个python编写可以在多台服务器上执行命令的工具，同时支持拷贝文件，是同类工具中很出色的，类似pdsh，个人认为相对pdsh更为简便，使用必须在各个服务器上配置好密钥认证访问。

项目地址： https://code.google.com/p/parallel-ssh/

PSSH provides parallel versions of OpenSSH and related tools. Included are pssh, pscp, prsync, pnuke, and pslurp. The project includes psshlib which can be used within custom applications. The source code is written in Python and can be cloned from:

git clone http://code.google.com/p/parallel-ssh/

PSSH is supported on Python 2.4 and greater (including Python 3.1 and greater). It was originally written and maintained by Brent N. Chun. Due to his busy schedule, Brent handed over maintenance to Andrew McNabb in October 2009.


#### 下载安装

##### 下载

wget http://parallel-ssh.googlecode.com/files/pssh-2.3.1.tar.gz  

本地下载 [pssh-2.3.1.tar.gz](/download/tools/pssh-2.3.1.tar.gz)


##### 安装
```
	tar xf pssh-2.3.1.tar.gz  
	cd pssh-2.3.1/  
	python setup.py install  
```

##### 参数命令介绍


pssh   在多个主机上并行地运行命令

```
       -h 执行命令的远程主机列表  或者 -H user@ip:port  文件内容格式[user@]host[:port]

       -l 远程机器的用户名

       -P 执行时输出执行信息
       -p 一次最大允许多少连接
       -o 输出内容重定向到一个文件
       -e 执行错误重定向到一个文件
       -t 设置命令执行的超时时间
       -A 提示输入密码并且把密码传递给ssh
       -O 设置ssh参数的具体配置，参照ssh_config配置文件
       -x 传递多个SSH 命令，多个命令用空格分开，用引号括起来
       -X 同-x 但是一次只能传递一个命令
       -i 显示标准输出和标准错误在每台host执行完毕后
```

#### 其他命令

```
	pscp     传输文件到多个hosts，类似scp

	pslurp   从多台远程机器拷贝文件到本地

	pnuke    并行在远程主机杀进程

	prsync   使用rsync协议从本地计算机同步到远程主机
```

#### 实例
##### pssh

```
    $ pssh -h ip.txt -l root chkconfig --level 2345 snmpd on  
    [1] 10:59:29 [SUCCESS] ... ...  
    [2] 10:59:29 [SUCCESS] ... ...  
    [3] 10:59:29 [SUCCESS] ... ...  
    ... ...  
```

##### pscp
```
    $ pscp -h ip.txt -l root /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf  
    [1] 11:00:42 [SUCCESS] ... ...  
    [2] 11:00:42 [SUCCESS] ... ...  
    [3] 11:00:42 [SUCCESS] ... ...  
    ... ...  
```

