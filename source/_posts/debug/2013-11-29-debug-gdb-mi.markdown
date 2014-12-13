---
layout: post
title: "GDB MI接口相关"
date: 2013-11-29 14:04:00 +0800
comments: false
categories:
- 2013
- 2013~11
- debug
- debug~gdb
tags:
---
<span style="color:red">所谓GDB MI就是GNU Debugger Machine-Interface,是GNU设计来给其它前端使用的交互协议.</span>

  说实在的,这个接口设计得并不是很好,仅仅是能用而已.它的指令和GDB/CLI即GDB Command Line Interface基本是对应的.  
为 了方便机器交互,它把允许所有的指令有一个前缀,比如901-stack-list-frames 0 99.这样,在GDB返回的结果前,也会有同样的前缀901,我们可以根据这个前缀进行命令/结果匹配. 同时它还保证结果格式的统一性.不会出现CLI那种百花齐放的结果.当然,如果你安了GDB的python插件来做变量格式化,就可能出现例外的情况.

  它的命令有同步的,也有异步的.这对于前端的设计是个很大的障碍,而且除了命令结果以外,它还会有很多异步的消息,事件...这些东西混在一起,处理起来会相当麻烦.

  这是 [GDB/MI的官方文档](http://ftp.gnu.org/old-gnu/Manuals/gdb-5.1.1/html_node/gdb_211.html#SEC216) 有兴趣的话可以仔细研究一下.

