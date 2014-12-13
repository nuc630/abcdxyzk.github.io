---
layout: post
title: "查看注册的kprobe列表"
date: 2013-06-06 10:45:00 +0800
comments: false
categories:
- 2013
- 2013~06
- debug
- debug~kprobe
tags:
---
```
sudo mount -t debugfs none mount_dir/

#cat mount_dir/kprobes/list
c015d71a  k  vfs_read+0x0
c011a316  j  do_fork+0x0
c03dedc5  r  tcp_v4_rcv+0x0
```
第一列表示探测点插入的内核地址，第二列表示内核探测的类型，k表示kprobe，r表示kretprobe，j表示jprobe，第三列指定探测点的"符号+偏移"。如果被探测的函数属于一个模块，模块名也被指定。

打开和关闭kprobe的方法列出如下：
```
#echo ‘1’ mount_dir/kprobes/enabled
#echo ‘0’ mount_dir/kprobes/enabled
```

