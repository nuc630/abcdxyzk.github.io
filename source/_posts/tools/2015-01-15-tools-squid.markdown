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

