---
layout: post
title: "gro收包"
date: 2015-05-08 16:32:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~mark
tags:
---

[linux kernel 网络协议栈之GRO(Generic receive offload)](/blog/2015/04/18/kernel-net-gro/)  

gro会合并多个gso_size不同的包, 会将gso_size设置成第一个包的gso_size.

如果此时把这个包发出去，那么就会导致不满足： skb->gso_size * (skb->segs-1) < skb->len <= skb->gso_size * skb->segs

那么后面的三个函数就有可能出错

#### 一、tcp_shift_skb_data
```
	mss = skb->gso_size
	len = len/mss * mss

	|---|-------|-------|
	 mss    |
	        V
	|---|---|
```

#### 二、tcp_mark_head_lost
```
	len = (packets - cnt) * mss

	|--------|--|--|
	   mss   |
             V
	|--------|--------|
```

#### 三、tcp_match_skb_to_sack
```
	new_len = (pkt_len/mm)*mss
	in_sack = 1
	pkt_len = new_len

	|---|-------|-------|
	 mss    |
	        V
	|---|---|
```

#### 修改
加入发包队列前
```
	skb_shinfo(skb)->gso_size = 0;
	skb_shinfo(skb)->gso_segs = 0;
	skb_shinfo(skb)->gso_type = 0;
```

