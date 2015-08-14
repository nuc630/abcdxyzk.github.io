---
layout: post
title: "tcp_read_sock BUG"
date: 2015-05-11 10:17:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~mark
tags:
---
```
	commit baff42ab1494528907bf4d5870359e31711746ae
	Author: Steven J. Magnani <steve@digidescorp.com>
	Date:   Tue Mar 30 13:56:01 2010 -0700

		net: Fix oops from tcp_collapse() when using splice()

		tcp_read_sock() can have a eat skbs without immediately advancing copied_seq.
		This can cause a panic in tcp_collapse() if it is called as a result
		of the recv_actor dropping the socket lock.

		A userspace program that splices data from a socket to either another
		socket or to a file can trigger this bug.

		Signed-off-by: Steven J. Magnani <steve@digidescorp.com>
		Signed-off-by: David S. Miller <davem@davemloft.net>
```
```
	diff --git a/net/ipv4/tcp.c b/net/ipv4/tcp.c
	index 6afb6d8..2c75f89 100644
	--- a/net/ipv4/tcp.c
	+++ b/net/ipv4/tcp.c
	@@ -1368,6 +1368,7 @@ int tcp_read_sock(struct sock *sk, read_descriptor_t *desc,
	 		sk_eat_skb(sk, skb, 0);
	 		if (!desc->count)
	 			break;
	+		tp->copied_seq = seq;
	 	}
	 	tp->copied_seq = seq;
	 
```

如果在tcp_read_sock中sk_eat_skb时copied_seq没有及时一起修改的话，就会出现copied_seq小于sk_write_queue队列第一个包的seq。  
tcp_read_sock的recv_actor指向的函数(比如tcp_splice_data_recv)是有可能释放sk锁的，如果这时进入收包软中断且内存紧张调用tcp_collapse，  
tcp_collapse中：  
```
	start = copied_seq
	...
	int offset = start - TCP_SKB_CB(skb)->seq;

	BUG_ON(offset < 0);
```

