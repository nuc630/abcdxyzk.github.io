---
layout: post
title: "--prefix"
date: 2013-10-23 10:49:00 +0800
comments: false
categories:
- 2013
- 2013~10
- compiler
- compiler~make
tags:
---
以安装supersparrow-0.0.0为例，我们打算把他安装到目录 /usr/local/supersparrow,于是在supersparrow-0.0.0目录执行带选项的脚本
```
./configure –prefix=/usr/local/supersparrow
```
执行成功后再编译、安装（make，make install）；安装完成将自动生成目录supersparrow,而且该软件任何的文档都被复制到这个目录。为什么要指定这个安装目录？是为了以后的维护方便，假如没有用这个选项，安装过程结束后，该软件所需的软件被复制到不同的系统目录下，很难弄清楚到底复制了那些文档、都复制到哪里去了—基本上是一塌糊涂。

用了—prefix选项的另一个好处是卸载软件或移植软件。当某个安装的软件不再需要时，只须简单的删除该安装目录，就能够把软件卸载得干干净净；移植软件只需拷贝整个目录到另外一个机器即可（相同的操作系统，不同系统用--target XXX）。

一个小选项有这么方便的作用，建议在实际工作中多多使用。

