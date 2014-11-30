---
layout: post
title: "VMware配置KGDB串口"
date: 2014-02-28 18:23:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~kgdb
tags:
---
在配置KGDB时,必须通过串口才能调试一台测试Linux, 如果通过本机是Linux的话, 就可以使用应用直接链接上VMware的linux,进行通讯.
```
1: VM->Settings->Hardware->Add
2: 选择Serial Port->next-> Output to socket -> next
3: Socket=/tmp/ttyS1, From: Server To: An Application
4: Finesh
5: 在本机Linux,运行socat TCP-LISTEN:5555,fork /tmp/ttyS1 &, 绑定本地端口5555到vmware的socket文件.
6: telnet 0:5555
aaa
bbb
7: 在target Linux上, cat /dev/ttyS1, 如果有aaa bbb,则通讯成功.
```
