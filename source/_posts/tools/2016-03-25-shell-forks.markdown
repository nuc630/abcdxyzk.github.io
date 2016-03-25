---
layout: post
title: "shell 多进程"
date: 2016-03-25 14:38:00 +0800
comments: false
categories:
- 2016
- 2016~03
- tools
- tools~base
tags:
---

http://www.linuxidc.com/Linux/2011-03/33918.htm

#### 一次性并发
```
	#!/bin/sh
	for ((i=1;i<10;i++))
	do
	{
		echo "run $i "`date +%s`
		sleep $i
		echo "end $i "`date +%s`
		exit 0
	} &
	done
	wait
```

#### 一次性并发forks个，forks个进程都结束后再并发forks个
```
	#!/bin/sh
	forks=3
	n=0
	for ((i=1;i<10;i++))
	do
	{
		{
			echo "run $i "`date +%s`
			sleep $i
			echo "end $i "`date +%s`
			exit 0
		} &
		let n=$n+1
		if [ $n -eq $forks ]; then
			wait
			n=0
		fi
	}
	done
	wait
```

#### 模拟多线程的一种方法
```
	#!/bin/sh

	tmp_fifo="/tmp/.tmp_fifo"

	mkfifo $tmp_fifo
	exec 6<>$tmp_fifo
	rm $tmp_fifo

	forks=3
	for ((i=0;i<$forks;i++))
	do
		echo >&6
	done

	for ((i=1;i<10;i++))
	do
		read -u6
		{
			echo "run $i "`date +%s`
			sleep $i
			echo "end $i "`date +%s`
			echo >&6
			exit 0
		} &
	done
	wait

	exec 6>&-

	exit 0
```

