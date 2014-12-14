---
layout: post
title: "libdwarf 安装使用"
date: 2014-10-15 18:16:00 +0800
comments: false
categories:
- 2014
- 2014~10
- debug
- debug~dwarf
tags:
---
下载[http://www.prevanders.net/dwarf.html](http://www.prevanders.net/dwarf.html)

依赖[http://directory.fsf.org/wiki/Libelf](http://directory.fsf.org/wiki/Libelf)

dwarf格式文档[http://www.dwarfstd.org/Home.php](http://www.dwarfstd.org/Home.php)


使用
```
./dwarfdump2/dwarfdump -Wc -S match=dev_queue_xmit /tmp/vmlinux
```
获取vmlinux中dev_queue_xmit函数的.debug信息
