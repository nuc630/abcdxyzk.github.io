---
layout: post
title: "gdb 输出控制"
date: 2014-08-28 16:09:00 +0800
comments: false
categories:
- 2014
- 2014~08
- debug
- debug~gdb
tags:
- gdb
---
#### 1
```
set print repeats [on/off]
```
设置打印数组的长度上限值。如果数组中连续相同的成员的数量超过这个上限，GDB会打印字符串”<repeats n times>”，这里n是同样的重复次数，而不是重复打印这些相同的成员。将这个上限设置为0的话，打印所有的成员。默认上限时10。
```
show print repeats
```
显示打印重复相同成员的上限数量。
#### 2
```
set print elements <number-of-elements>
```
这个选项主要是设置数组的，假如你的数组太大了，那么就可以指定一个<number-of-elements>来指定数据显示的最大长度，当到达这个长度时，GDB就不再往下显示了。假如设置为0，则表示不限制。
```
show print elements
```
查看print elements的选项信息。
#### 3
运行GDB的时候 总是会出现type return to continue,or q <return> to quit，  
因为显示得太多，此时gdb的显示会有些像more命令  
把这个消息屏蔽掉可以设置
```
set pagination off 
```
#### 4
将GDB中需要的调试信息输出到文件
```
# (gdb) set logging file <文件名>
# (gdb) set logging on
# (gdb) bt
# (gdb) set logging off
```

