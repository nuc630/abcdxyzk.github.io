---
layout: post
title: "awk命令"
date: 2016-03-21 10:19:00 +0800
comments: false
categories:
- 2016
- 2016~03
- tools
- tools~command
tags:
---

##### 统计列和
```
	awk 'BEGIN { sum+=$1; } END { print sum }'
```

#### -F 参数自定义分隔符可以用正则表达式

```
	awk -F '[ ;]+' '{print $2}'
```

--------------------

http://www.cnblogs.com/ggjucheng/archive/2013/01/13/2858470.html

#### 实例
```
	last -n 5 | awk  '{print $1}'
	cat /etc/passwd |awk  -F ':'  '{print $1"\t"$7}'
	cat /etc/passwd |awk  -F ':'  'BEGIN {print "name,shell"}  {print $1","$7} END {print "blue,/bin/nosh"}'
```

#### awk内置变量
```
	ARGC            命令行参数个数
	ARGV            命令行参数排列
	ENVIRON         支持队列中系统环境变量的使用
	FILENAME        awk浏览的文件名
	FNR             浏览文件的记录数
	FS              设置输入域分隔符，等价于命令行 -F选项
	NF              浏览记录的域的个数
	NR              已读的记录数
	OFS             输出域分隔符
	ORS             输出记录分隔符
	RS              控制记录分隔符
```

 此外,$0变量是指整条记录。$1表示当前行的第一个域,$2表示当前行的第二个域,......以此类推。

#### print和printf

awk中同时提供了print和printf两种打印输出的函数。

其中print函数的参数可以是变量、数值或者字符串。字符串必须用双引号引用，参数用逗号分隔。如果没有逗号，参数就串联在一起而无法区分。这里，逗号的作用与输出文件的分隔符的作用是一样的，只是后者是空格而已。

printf函数，其用法和c语言中printf基本相似,可以格式化字符串,输出复杂时，printf更加好用，代码更易懂。

#### awk编程

##### 变量和赋值

```
	# 统计/etc/passwd的账户人数
	awk '{count++;print $0;} END{print "user count is ", count}' /etc/passwd
```

##### 条件语句
```
	if (expression) {
		statement;
		statement;
		... ...
	}

	if (expression) {
		statement;
	} else {
		statement2;
	}

	if (expression) {
		statement1;
	} else if (expression1) {
		statement2;
	} else {
		statement3;
	}
```

##### 循环语句

awk中的循环语句同样借鉴于C语言，支持while、do/while、for、break、continue，这些关键字的语义和C语言中的语义完全相同。

##### 数组

 因为awk中数组的下标可以是数字和字母，数组的下标通常被称为关键字(key)。值和关键字都存储在内部的一张针对key/value应用hash的表格里。由于hash不是顺序存储，因此在显示数组内容时会发现，它们并不是按照你预料的顺序显示出来的。数组和变量一样，都是在使用时自动创建的，awk也同样会自动判断其存储的是数字还是字符串。一般而言，awk中的数组用来从记录中收集信息，可以用于计算总和、统计单词以及跟踪模板被匹配的次数等等。
 
显示/etc/passwd的账户
```
	awk -F ':' 'BEGIN {count=0;} {name[count] = $1;count++;}; END{for (i = 0; i < NR; i++) print i, name[i]}' /etc/passwd
	0 root
	1 daemon
	2 bin
	3 sys
	4 sync
	5 games
	......
```

