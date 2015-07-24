---
layout: post
title: "haproxy splice"
date: 2015-07-24 16:45:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
www.haproxy.org/download/1.5/doc/configuration.txt 或 [configuration.txt](/download/tools/haproxy-1.5-configuration.txt)

旧版编译加
```
	USE_TCPSPLICE=1
```

比较新的加
```
	USE_LINUX_SPLICE=1
```
默认编译会加入


编译加入了也要在配置文件中开启才有效
```
	option splice-auto
	option splice-request
	option splice-response
```

在global中关闭splice功能
```
	nosplice
```


