---
layout: post
title: "KGDB配置"
date: 2014-02-28 18:18:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~kgdb
tags:
---
Host机：一个装有Ubuntu12.04-x86-64的主机  
Target机：运行在vmware上的 Ubuntu12.04-server-x86-64 的Linux.

#### Target机器配置
0. 配置好VMware对外串口, 详情见:http://my.oschina.net/u/139611/blog/110052
1. 下载源码到/usr/src/linux-source-3.2.0下, 解压.
2. make menuconfig
3. 进入General setup，把Local version设置一下(-kgdb)
4. 进入Kernel hacking，选"Compile the kernel with debug info"为*
5. 选"KGDB: kernel debugging with remote gdb"为*
6. 选"Write protect kernel read-only data structures"为空 （否则在断下来继续执行的时候可能会报错：Cannot remove breakpoints because program is no longer writable）
7. 进入"KGDB: ... " 选"KGDB: use KGDB over the serial console"为*，选"KGDB: internal test suite“为空，否则kgdboc会注册不了
7. 保存，编译: make -j4 && make modules install && make install
8. 把vmliunux和System.map拷贝到host机器上
9. 修改/boot/grub/grub.cfg中menuentry为kgdb的项，在kernel后面添加参数: kgdboc=ttyS1,115200 kgdbwait
10. 重启，系统进入等待状态。

#### Host机：
1. 安装好GDB，配好串口等。
2.运行 socat TCP-LISTEN:5555,fork /tmp/ttyS1 & , 链接到vmware对外的串口文件
2. gdb vmlinux
3. 在GDB中:
(gdb) target remote 0:5555
 就可以进入调试状态了
4. (gdb) c ,则target进入Linux系统 


