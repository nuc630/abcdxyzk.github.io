---
layout: post
title: "统计git提交行数的脚本"
date: 2012-10-16 14:15:00 +0800
comments: false
categories:
- 2012
- 2012~10
- tools
- tools~git
tags:
---
可以保存为count.sh运行 ./count.sh your_name
```
	#!/bin/sh
	insert=0
	delete=0
	git log--author=$1--shortstat--pretty=format:""|sed/^$/d >.tmp.count

	whilereadline ;do
	current=`echo$line|awk-F',''{printf $2}'|awk'{printf $1}'`
	insert=`expr$insert+ $current`
	current=`echo$line|awk-F',''{printf $3}'|awk'{printf $1}'`
	delete=`expr$delete+ $current`
	done<.tmp.count

	rm .tmp.count
	echo$1$insertinsertions, $deletedeletions
```

