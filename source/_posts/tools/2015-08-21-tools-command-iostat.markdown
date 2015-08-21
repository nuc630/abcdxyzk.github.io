---
layout: post
title: "iostat 命令"
date: 2015-08-21 15:57:00 +0800
comments: false
categories:
- 2015
- 2015~08
- tools
- tools~command
tags:
---

http://blog.csdn.net/zhangjay/article/details/6656771

http://www.cnblogs.com/mfryf/archive/2012/03/12/2392000.html

iostat用于输出CPU和磁盘I/O相关的统计信息. 

命令格式:
```
	iostat [ -c | -d ] [ -k | -m ] [ -t ] [ -V ] [ -x ] [ device [ ... ] | ALL ] [ -p [ device | ALL ]  ]
	       [ interval [ count ] ]
```

#### 1)iostat的 简单使用

iostat可以显示CPU和I/O系统的负载情况及分区状态信息. 直接执行iostat可以显示下面内容:
```
	# iostat
	Linux 2.6.9-8.11.EVAL (ts3-150.ts.cn.tlan)      08/08/2007

	avg-cpu:  %user   %nice    %sys %iowait   %idle
	          12.01    0.00        2.15    2.30       83.54

	Device:            tps   Blk_read/s   Blk_wrtn/s   Blk_read   Blk_wrtn
	hda               7.13       200.12        34.73     640119     111076
```

各个输出项目的含义如下:

avg-cpu段:
```
	%user: 在用户级别运行所使用的CPU的百分比.
	%nice: nice操作所使用的CPU的百分比.
	%sys: 在系统级别(kernel)运行所使用CPU的百分比.
	%iowait: CPU等待硬件I/O时,所占用CPU百分比.
	%idle: CPU空闲时间的百分比.
```

Device段:
```
	tps: 每秒钟发送到的I/O请求数.
	Blk_read /s: 每秒读取的block数.
	Blk_wrtn/s: 每秒写入的block数.
	Blk_read:   读入的block总数.
	Blk_wrtn:  写入的block总数.
```

#### 2)iostat参 数说明

iostat各个参数说明:
```
	-c 仅显示CPU统计信息.与-d选项互斥.
	-d 仅显示磁盘统计信息.与-c选项互斥.
	-k 以K为单位显示每秒的磁盘请求数,默认单位块.
	-p device | ALL
	 与-x选项互斥,用于显示块设备及系统分区的统计信息.也可以在-p后指定一个设备名,如:
	 # iostat -p hda
	 或显示所有设备
	 # iostat -p ALL
	-t    在输出数据时,打印搜集数据的时间.
	-V    打印版本号和帮助信息.
	-x    输出扩展信息.
```

#### 3)iostat输 出项目说明
```
	rrqm/s: 每秒进行 merge 的读操作数目。即 delta(rmerge)/s
	wrqm/s: 每秒进行 merge 的写操作数目。即 delta(wmerge)/s
	r/s: 每秒完成的读 I/O 设备次数。即 delta(rio)/s
	w/s: 每秒完成的写 I/O 设备次数。即 delta(wio)/s
	rsec/s: 每秒读扇区数。即 delta(rsect)/s
	wsec/s: 每秒写扇区数。即 delta(wsect)/s
	rkB/s: 每秒读K字节数。是 rsect/s 的一半，因为每扇区大小为512字节。(需要计算)
	wkB/s: 每秒写K字节数。是 wsect/s 的一半。(需要计算)
	avgrq-sz: 平均每次设备I/O操作的数据大小 (扇区)。delta(rsect+wsect)/delta(rio+wio)
	avgqu-sz: 平均I/O队列长度。即 delta(aveq)/s/1000 (因为aveq的单位为毫秒)。
	await: 平均每次设备I/O操作的等待时间 (毫秒)。即 delta(ruse+wuse)/delta(rio+wio)
	svctm: 平均每次设备I/O操作的服务时间 (毫秒)。即 delta(use)/delta(rio+wio)
	%util: 一秒中有百分之多少的时间用于 I/O 操作，或者说一秒中有多少时间 I/O 队列是非空的。即 delta(use)/s/1000 (因为use的单位为毫秒)
	如果 %util 接近 100%，说明产生的I/O请求太多，I/O系统已经满负荷，该磁盘可能存在瓶颈。

	Blk_read 读入块的当总数.
	Blk_wrtn 写入块的总数.
	kB_read/s 每秒从驱动器读入的数据量,单位为K.
	kB_wrtn/s 每秒向驱动器写入的数据量,单位为K.
	kB_read 读入的数据总量,单位为K.
	kB_wrtn 写入的数据总量,单位为K.
	rrqm/s 将读入请求合并后,每秒发送到设备的读入请求数.
	wrqm/s 将写入请求合并后,每秒发送到设备的写入请求数.
	r/s 每秒发送到设备的读入请求数.
	w/s 每秒发送到设备的写入请求数.
	rsec/s 每秒从设备读入的扇区数.
	wsec/s 每秒向设备写入的扇区数.
	rkB/s 每秒从设备读入的数据量,单位为K.
	wkB/s 每秒向设备写入的数据量,单位为K.
	avgrq-sz 发送到设备的请求的平均大小,单位是扇区.
	avgqu-sz 发送到设备的请求的平均队列长度.
	await I/O请求平均执行时间.包括发送请求和执行的时间.单位是毫秒.
	svctm 发送到设备的I/O请求的平均执行时间.单位是毫秒.
	%util 在I/O请求发送到设备期间,占用CPU时间的百分比.用于显示设备的带宽利用率.当这个值接近100%时,表示设备带宽已经占满.
```

#### 4)iostat示 例

```
	# iostat
	显示一条统计记录,包括所有的CPU和设备.

	# iostat -d 2
	每隔2秒,显示一次设备统计信息.

	# iostat -d 2 6
	每隔2秒,显示一次设备统计信息.总共输出6次.

	# iostat -x hda hdb 2 6
	每隔2秒显示一次hda,hdb两个设备的扩展统计信息,共输出6次.

	# iostat -p sda 2 6
	每隔2秒显示一次sda及上面所有分区的统计信息,共输出6次.
```

