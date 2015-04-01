---
layout: post
title: "tc模拟丢包率时延"
date: 2015-04-01 23:25:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---

#### tc 的最最基本的使用
```
	tc qdisc show    # 显示
	tc qdisc add dev eth0 root ...... # 加入
	tc qdisc change dev eth0 root ...... # 修改存在的 qdisc ，记的，加入同一条后只能用 change 来修改
	tc qdisc del dev eth0 root  # 删除
```
 
#### Linux 中延时模拟
设置延时 3s :
```
	tc qdisc add dev eth0 root netem delay 3000ms
```
可以在 3000ms 后面在加上一个延时，比如 3000ms 200ms 表示 3000ms ± 200ms ，延时范围 2800 – 3200 之间.
 
#### Linux 中丢包模拟
设置丢包 50% ,iptables 也可以模拟这个，但一下不记的命令了，下次放上来:
```
	tc qdisc change dev eth0 root netem loss 50%
```
上面的设丢包，如果给后面的 50% 的丢包比率修改成 50% 80% 时，这时和上面的延时不一样，这是指丢包比率为 50-80% 之间。


