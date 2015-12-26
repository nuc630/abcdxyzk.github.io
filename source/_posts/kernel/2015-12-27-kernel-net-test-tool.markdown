---
layout: post
title: "Web压力测试工具"
date: 2015-12-27 02:51:00 +0800
comments: false
categories:
- 2015
- 2015~12
- kernel
- kernel~net
tags:
---
http://297020555.blog.51cto.com/1396304/592386

#### 一、http_load
http_load以并行复用的方式运行，用以测试web服务器的吞吐量与负载。但是它不同于大多数压力测试工具，它可以以一个单一的进程运行，一般不会把客户机搞死。还可以测试HTTPS类的网站请求。

下载地址：http://www.acme.com/software/http_load/

```
	./http_load -verbose -proxy 192.168.99.6:80 -parallel 24 -seconds 1000 url.txt
```

#### 二、webbench

webbench是Linux下的一个网站压力测试工具，最多可以模拟3万个并发连接去测试网站的负载能力。
```
	用法：webbench -c 并发数 -t 运行测试时间 URL
	如：webbench -c 5000 -t 120 http://www.163.com
```

#### 三、ab
ab是apache自带的一款功能强大的测试工具。安装了apache一般就自带了，用法可以查看它的说明

参数众多，一般我们用到的是-n 和-c

例如：
```
	./ab -c 1000 -n 100 http://www.vpser.net/index.php
```
这个表示同时处理1000个请求并运行100次index.php文件.

#### 四、Siege
一款开源的压力测试工具，可以根据配置对一个WEB站点进行多用户的并发访问，记录每个用户所有请求过程的相应时间，并在一定数量的并发访问下重复进行。
官方：http://www.joedog.org/

使用
```
	siege -c 200 -r 10 -f example.url
```

-c是并发量，-r是重复次数。 url文件就是一个文本，每行都是一个url，它会从里面随机访问的。

