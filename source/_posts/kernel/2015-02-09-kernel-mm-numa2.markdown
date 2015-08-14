---
layout: post
title: "NUMA技术相关笔记"
date: 2015-02-09 16:34:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~mm
tags:
---
http://blog.csdn.net/jollyjumper/article/details/17168175

起源于在mongo启动脚本中看到`numactl --interleave=all mongod ...`。

  NUMA,非统一内存访问(Non-uniform Memory Access),介于SMP(对称多处理)和MPP(大规模并行处理)之间，各个节点自有内存(甚至IO子系统),访问其它节点的内存则通过高速网络通道。NUMA信息主要通过BIOS中的ACPI(高级配置和编程接口)进行配置,Linux对NUMA系统的物理内存分布信息从系统firmware的ACPi表中获得，最重要的是SRAT(System Resource Affinity Table)和SLIT(System locality Information Table)表。SRAT表包含CPU信息、内存相关性信息,SLIT表则记录了各个节点之间的距离，在系统中由数组node_distance[]记录。这样系统可以就近分配内存，减少延迟。

Linux中用一个struct pg_data_t表示一个numa节点，Linux内核支持numa调度,并实现CPU的负载均衡。

##### 查看是否支持:
dmesg | grep -i numa

##### 要查看具体的numa信息用numastat
```
	numastat
		                       node0           node1
	numa_hit             19983469427     20741805466
	numa_miss             1981451471      2503049250
	numa_foreign          2503049250      1981451471
	interleave_hit         849781831       878579884
	local_node           19627390917     20298995632
	other_node            2337529981      2945859084
```
numa_hit是打算在该节点上分配内存，最后从这个节点分配的次数;  
num_miss是打算在该节点分配内存，最后却从其他节点分配的次数;  
num_foregin是打算在其他节点分配内存，最后却从这个节点分配的次数;  
interleave_hit是采用interleave策略最后从该节点分配的次数;  
local_node该节点上的进程在该节点上分配的次数  
other_node是其他节点进程在该节点上分配的次数  

##### lscpu可以看到两个node的cpu归属:
```
	lscpu
	...
	NUMA node0 CPU(s):     0,2,4,6,8,10,12,14,16,18,20,22,24,26,28,30
	NUMA node1 CPU(s):     1,3,5,7,9,11,13,15,17,19,21,23,25,27,29,31
```

##### `numactl --hardware`命令
会返回不同节点的内存总大小，可用大小,以及node distance等信息。

各个cpu负载情况，使用命令:mpstat -P ALL(需要安装sysstat)

Linux上使用numactl设定进程的numa策略。常见的情况是,数据库daemon进程(mongodb,mysql)可能会吃掉很多内存，而一个numa节点上的内存很有限，内存不够时虚拟内存频繁与硬盘交换数据，导致性能急剧下降(标识是irqbalance进程top中居高不下),这时应该采用interleave的numa策略，允许从其他节点分配内存。

各个内存的访问延迟如何?numactl man中的example提供了参考,我在公司的服务器上测了一下:
##### 写速度:
```
	numactl --cpubind=0 --membind=0 dd if=/dev/zero of=/dev/shm/A bs=1M count=1024

	1024+0 records in
	1024+0 records out
	1073741824 bytes (1.1 GB) copied, 0.546679 s, 2.0 GB/s

	numactl --cpubind=0 --membind=1 dd if=/dev/zero of=/dev/shm/A bs=1M count=1024
	1024+0 records in
	1024+0 records out
	1073741824 bytes (1.1 GB) copied, 0.612825 s, 1.8 GB/s
```

##### 读速度:
测试从同一个节点读取:
```
	numactl --cpubind=0 --membind=0 dd if=/dev/zero of=/dev/shm/A bs=1M count=1000
	date +%s.%N
	numactl --cpubind=0 --membind=0 cp /dev/shm/A /dev/null
	date +%s.%N
	rm /dev/shm/A
```
花费0.264556884765625秒,速度是3.779905410081901GB/s。

从另一个节点读取:
```
	numactl --cpubind=0 --membind=0 dd if=/dev/zero of=/dev/shm/A bs=1M count=1000
	date +%s.%N
	numactl --cpubind=1 --membind=1 cp /dev/shm/A /dev/null
	date +%s.%N
	rm /dev/shm/A
```
花费0.3308408260345459秒,速度是3.022601569419312GB/s。

加速效果还是很明显的。

#### 参考:
http://www.ibm.com/developerworks/cn/linux/l-numa/  
http://www.dedecms.com/knowledge/data-base/nosql/2012/0820/8684.html

