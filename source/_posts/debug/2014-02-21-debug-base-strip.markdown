---
layout: post
title: "对库和可执行文件进行裁减"
date: 2014-02-21 14:11:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~base
tags:
---
  如果生成的可执行文件或库比较大，这时候就可以使用strip命令进行裁减，在嵌入式开发中，如果使用的交叉编译工具是arm-linux,则命令 是arm-linux-strip,如果是arm-uclibc-linux,则命令是arm-uclibc-linux-strip.

  因为开发板上的空间本来就很少，使用这个命令可以进一步减少可执行文件的大小，从而可以在开发板上可以存放更过的可执行文件。

* 主要是把编译的库文件或者可执行文件里的一些调试信息和符号信息去除。

  使用strip对库文件、可执行文件进行操作，库文件、可执行文件中的一些与正常运行无关的调试信息和符号信息会被剔除掉，而且操作前和操作后文件的大小 变化特别明显，一般可以减少1/3或更多，所以在嵌入式的平台上是非常有用的。但是在开发过程并不提倡这一做法，因为使用strip后,使用gdb时就无法获得调试信息了

用法: strip [options] file(s)  
strip一般有以下选项
```
-I --input-target= 假定输入文件的格式为
-O --output-target= 以格式创建输出文件
-F --target= 设置输入、输出的文件格式为
-p --preserve-dates 复制上次修改或者操作的时间到输出文件中
-R --remove-section= 删除输出文件中段信息
-s --strip-all 删除所有符号信息和重定位信息
-g -S -d --strip-debug 删除所有调试信息和段信息
--strip-unneeded 删除所有重定位中不需要的符号信息
--only-keep-debug 删除调试信息以外的其他所有信息
-N --strip-symbol= 不拷贝符号信息
-K --keep-symbol= 不去除符号信息
-w --wildcard 在符号中使用通配符
-x --discard-all 去除所有非全局符号
-X --discard-locals 去除所有编译产生的符号
-v --verbose 列出所有修改过的所有目标文件
-V --version 显示版本号
-h --help 显示帮助
-o 把输出的文件名修改成
```

