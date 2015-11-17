---
layout: post
title: "curl命令"
date: 2015-11-17 10:04:00 +0800
comments: false
categories:
- 2015
- 2015~11
- tools
- tools~command
tags:
---

-s 静默输出；没有-s的话就是下面的情况，这是在脚本等情况下不需要的信息。

#### 监控首页各项时间指标：
```
	curl -o /dev/null -s -w '%{time_connect} %{time_starttransfer} %{time_total}' http://www.miotour.com
	0.244 1.044 2.672

	时间指标解释 ：
	time_connect		建立到服务器的 TCP 连接所用的时间
	time_starttransfer	在发出请求之后，Web 服务器返回数据的第一个字节所用的时间
	time_total			完成请求所用的时间
```

在发出请求之后，Web 服务器处理请求并开始发回数据所用的时间是 （time_starttransfer）1.044 - （time_connect）0.244 = 0.8 秒

客户机从服务器下载数据所用的时间是 （time_total）2.672 - （time_starttransfer）1.044 = 1.682 秒


#### -x 指定访问IP与端口号
```
	curl -x 61.135.169.105:80 http://www.baidu.com
```

#### -I 仅仅取文件的http头部
```
	curl   -I  -x 192.168.1.1:80  http://www.miotour.com
```

#### 用referer做的防盗链，就可以使用-e来设置
```
	curl -e "http://www.qiecuo.org"    http:// www.miotour.com -v  -I
```

#### -H去构造你想要的http头部
```
	curl -H "X-Forward-For:8.8.8.8" http://www.miotour.com  -v  -I
```

#### curl提交用户名和密码
```
	curl http://name:passwd@www.miotour.com
	curl -u name:passwd http://www.miotour.com
```

#### -b “cookie” 此参数用来构造一个携带cookie的请求

#### USER AGENT   关于浏览器发送的http请求信息. Curl允许用命令制定. 发送一些用于欺骗服务器或cgi的信息. 
```
	curl -A 'Mozilla/3.0 (Win95; I)' http://www.nationsbank.com/
```

