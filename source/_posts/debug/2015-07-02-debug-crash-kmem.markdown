---
layout: post
title: "crash kmem"
date: 2015-07-02 10:29:00 +0800
comments: false
categories:
- 2015
- 2015~07
- debug
- debug~kdump、crash
tags:
---
#### 一、kmem -s 查看slab
```
	crash> kmem -s
	CACHE            NAME                 OBJSIZE  ALLOCATED     TOTAL  SLABS  SSIZE
	...
	ffff8808132d1ac0 request_sock_TCP         128          2        30      1     4k
	ffff8808135e1400 sock_inode_cache         704        298       470     94     4k
	...
```

#### 二、kmem -S 查看slab中详细内容
```
	crash> kmem -S request_sock_TCP
	CACHE            NAME                 OBJSIZE  ALLOCATED     TOTAL  SLABS  SSIZE
	ffff8808132d1ac0 request_sock_TCP         128          2        30      1     4k
	SLAB              MEMORY            TOTAL  ALLOCATED  FREE
	ffff88078b9c6000  ffff88078b9c60c0     30          2    28
	FREE / [ALLOCATED]
	   ffff88078b9c60c0
	   ffff88078b9c6140
	   ffff88078b9c61c0
	   ffff88078b9c6240
	   ffff88078b9c62c0
	   ffff88078b9c6340
	   ffff88078b9c63c0
	   ffff88078b9c6440
	   ffff88078b9c64c0
	   ffff88078b9c6540
	   ffff88078b9c65c0
	   ffff88078b9c6640
	   ffff88078b9c66c0
	  [ffff88078b9c6740]
	  [ffff88078b9c67c0]
	   ffff88078b9c6840
	   ffff88078b9c68c0
	   ffff88078b9c6940
	   ffff88078b9c69c0
	...
```

request_sock_TCP 是 struct request_sock 类型，所以对于已分配的地址可以直接查看

```
	crash> struct request_sock 0xffff88078b9c6740
	struct request_sock {
	  dl_next = 0x0, 
	  mss = 1460, 
	  retrans = 0 '\000', 
	  cookie_ts = 0 '\000', 
	  window_clamp = 8388480, 
	  rcv_wnd = 14600, 
	  ts_recent = 0, 
	  expires = 4302901768, 
	  rsk_ops = 0xffffffff81c0e840 <tcp_request_sock_ops>, 
	  sk = 0xffff880771dad800, 
	  secid = 3039208612, 
	  peer_secid = 3672081930
	}
```

http://blog.csdn.net/u011279649/article/details/17529315



