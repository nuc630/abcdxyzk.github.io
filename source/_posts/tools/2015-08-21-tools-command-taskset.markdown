---
layout: post
title: "taskset 命令"
date: 2015-08-21 15:52:00 +0800
comments: false
categories:
- 2015
- 2015~08
- tools
- tools~command
tags:
---

```
	#taskset --help
	taskset (util-linux 2.13-pre7)
	usage: taskset [options] [mask | cpu-list] [pid | cmd [args...]]
	set or get the affinity of a process

	-p, --pid operate on existing given pid
	-c, --cpu-list display and specify cpus in list format
	-h, --help display this help
	-v, --version output version information
```

* 加-c用的是cpu-id，不加-c用的mask

举例：

1、开启一个只用0标记的cpu核心的新进程(job.sh是你的工作脚本)
```
	#taskset -c 0 sh job.sh
```

2、查找现有的进程号，调整该进程cpu核心使用情况（23328举例用的进程号）
```
	#taskset -pc 0 23328
	pid 23328's current affinity list: 0-3  #0-3表示使用所有4核进行处理
	pid 23328's new affinity list: 0 #调整后改为仅适用0标记单核处理
```


