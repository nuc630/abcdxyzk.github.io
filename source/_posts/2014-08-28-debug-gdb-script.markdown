---
layout: post
title: "gdb的脚本使用"
date: 2014-08-28 15:47:00 +0800
comments: true
categories:
- 2014
- 2014~08
- debug
- debug~gdb
tags:
- gdb
---
#### 1）启动gdb时候
1、gdb在启动的时候，会在当前目录下查找".gdbinit"这个文件，并把它的内容作为gdb命令进行解释，所以如果我把脚本命名为".gdbinit"，这样在启动的时候就会处理这些命令。  
2、启动gdb的时候自动执行脚本 gdb -x your_script  
#### 2）gdb运行期间
可以使用 source script-file 来解释gdb命令脚本script-file

