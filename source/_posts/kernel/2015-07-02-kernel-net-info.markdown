---
layout: post
title: "查看所有tcp连接"
date: 2015-07-02 10:06:00 +0800
comments: false
categories:
- 2015
- 2015~07
- kernel
- kernel~net
tags:
---
http://roclinux.cn/?p=2418

http://blog.csdn.net/justlinux2010/article/details/21028797

#### 一、查看连接
```
	netstat -an
```
或
```
	ss
```

#### 二、查看连接详细信息
上面的命令也是从`/proc/net/tcp`和`/proc/net/tcp6`中读取的

/proc/net/tcp中的内容由tcp4_seq_show()函数打印，该函数中有三种打印形式，我们这里这只列出状态是TCP_SEQ_STATE_LISTENING或TCP_SEQ_STATE_ESTABLISHED的情况，如下所示：

![](/images/kernel/2015-07-02.png)  


