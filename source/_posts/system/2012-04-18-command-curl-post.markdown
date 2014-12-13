---
layout: post
title: "curl模拟post"
date: 2012-04-18 10:47:00 +0800
comments: false
categories:
- 2012
- 2012~04
- system
- system~command
tags:
---
经常会遇到需要post提交东西的时候  
这时候用curl是非常方便的  
例子：
```
curl -A "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0)" \
-e "http://www.xxx.com/poll.shtml" \
-d "2880[]=105&pid=2880&p=最佳&count=1&receipt=1&poll=投票" \
http://survey.xxx.com/poll/poll.php
```
这里
`-A "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.0)"`  
的意思就是申明自己用的是windows2000下的ie6的浏览器；

`-e "http://www.xxx.com/poll.shtml"`
的意思就是refer是这个页面；

-d后面的参数都是将用post方式提交到服务器去的

最后面的就是将要post到的url地址

