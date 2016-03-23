---
layout: post
title: "squid--代理"
date: 2015-01-15 16:05:00 +0800
comments: false
categories:
- 2015
- 2015~01
- tools
- tools~base
tags:
---

好像改这行就能直接用了
```
	610c610
	< # http_access deny all
	---
	>  http_access allow all
```

一个centos5上不干扰系统haproxy、squid独立运行的提取 [haproxy_squid.tar.gz](/download/tools/haproxy_squid.tar.gz)

------------------

### 安装

```
	yum install squid
```

### centos 5
ERROR:
```
	While trying to retrieve the URL: http://192.168.34.80/

	The following error was encountered:

	Unable to forward this request at this time.
	This request could not be forwarded to the origin server or to any parent caches. The most likely cause for this error is that:

	The cache administrator does not allow this cache to make direct connections to origin servers, and
	All configured parent caches are currently unreachable.
	Your cache administrator is root. 
```

将 /etc/squid/squid.conf 中
```
	never_direct allow all
```
改成
```
	always_direct allow all
```
再去掉cache_peer


#### centos 5
```
	# diff /tmp/orig_squid.conf /etc/squid/squid.conf
	610c610
	< # http_access deny all
	---
	> http_access allow all
	615,616c615,616
	< http_access allow manager localhost
	< http_access deny manager
	---
	> #http_access allow manager localhost
	> #http_access deny manager
	618c618
	< http_access deny !Safe_ports
	---
	> #http_access deny !Safe_ports
	620c620
	< http_access deny CONNECT !SSL_ports
	---
	> #http_access deny CONNECT !SSL_ports
	636,637c636,637
	< http_access allow localhost
	< http_access deny all
	---
	> #http_access allow localhost
	> #http_access deny all
	921c921
	< http_port 3128
	---
	> http_port 3128 accel vhost vport
	4007a4008
	> always_direct allow all
```


