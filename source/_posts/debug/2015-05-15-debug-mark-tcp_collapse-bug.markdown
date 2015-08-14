---
layout: post
title: "tcp_collapse do not copy headers"
date: 2015-05-15 10:08:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~mark
tags:
---
```
	commit b3d6cb92fd190d720a01075c4d20cdca896663fc
	Author: Eric Dumazet <edumazet@google.com>
	Date:   Mon Sep 15 04:19:53 2014 -0700

	    tcp: do not copy headers in tcp_collapse()

	    tcp_collapse() wants to shrink skb so that the overhead is minimal.

	    Now we store tcp flags into TCP_SKB_CB(skb)->tcp_flags, we no longer
	    need to keep around full headers.
	    Whole available space is dedicated to the payload.

	    Signed-off-by: Eric Dumazet <edumazet@google.com>
	    Acked-by: Neal Cardwell <ncardwell@google.com>
	    Signed-off-by: David S. Miller <davem@davemloft.net>
```

```
	diff --git a/net/ipv4/tcp_input.c b/net/ipv4/tcp_input.c
	index 228bf0c..ea92f23 100644
	--- a/net/ipv4/tcp_input.c
	+++ b/net/ipv4/tcp_input.c
	@@ -4535,26 +4535,13 @@ restart:
	 		return;
	 
	 	while (before(start, end)) {
	+		int copy = min_t(int, SKB_MAX_ORDER(0, 0), end - start);
	 		struct sk_buff *nskb;
	-		unsigned int header = skb_headroom(skb);
	-		int copy = SKB_MAX_ORDER(header, 0);
	 
	-		/* Too big header? This can happen with IPv6. */
	-		if (copy < 0)
	-			return;
	-		if (end - start < copy)
	-			copy = end - start;
	-		nskb = alloc_skb(copy + header, GFP_ATOMIC);
	+		nskb = alloc_skb(copy, GFP_ATOMIC);
	 		if (!nskb)
	 			return;
	 
	-		skb_set_mac_header(nskb, skb_mac_header(skb) - skb->head);
	-		skb_set_network_header(nskb, (skb_network_header(skb) -
	-					      skb->head));
	-		skb_set_transport_header(nskb, (skb_transport_header(skb) -
	-						skb->head));
	-		skb_reserve(nskb, header);
	-		memcpy(nskb->head, skb->head, header);
	 		memcpy(nskb->cb, skb->cb, sizeof(skb->cb));
	 		TCP_SKB_CB(nskb)->seq = TCP_SKB_CB(nskb)->end_seq = start;
	 		__skb_queue_before(list, skb, nskb);
```

-----------------

这个改进无形中修了一个BUG，但是这BUG正常情况下不会触发，除非我们对skb进行改动导致skb->data - skb->head = 4k时，如果此时内存紧张，且满足tcp_collapse合并条件才触发。

BUG：
tcp_collapse代码中有：
```
		while (before(start, end)) {
			struct sk_buff *nskb;
			unsigned int header = skb_headroom(skb);
			int copy = SKB_MAX_ORDER(header, 0);

			/* Too big header? This can happen with IPv6. */
			if (copy < 0) 
				return;

			......

			/* Copy data, releasing collapsed skbs. */
			while (copy > 0) { 
				int offset = start - TCP_SKB_CB(skb)->seq;
				int size = TCP_SKB_CB(skb)->end_seq - start;
```

也就是说如果header = 4k，那么copy = 0，那么会一直申请len=0的skb插入到receive队列，直到申请skb失败。这样就会造成tcp_recvmsg出错

```
			skb_queue_walk(&sk->sk_receive_queue, skb) {
				/* Now that we have two receive queues this
				 * shouldn't happen.
				 */
				if (WARN(before(*seq, TCP_SKB_CB(skb)->seq),
					 KERN_INFO "recvmsg bug: copied %X "
						   "seq %X rcvnxt %X fl %X\n", *seq,
						   TCP_SKB_CB(skb)->seq, tp->rcv_nxt,
						   flags))
					break;

				offset = *seq - TCP_SKB_CB(skb)->seq;
				if (tcp_hdr(skb)->syn)
					offset--;
				if (offset < skb->len)
					goto found_ok_skb;
				if (tcp_hdr(skb)->fin)
					goto found_fin_ok;
				WARN(!(flags & MSG_PEEK), KERN_INFO "recvmsg bug 2: "
						"copied %X seq %X rcvnxt %X fl %X\n",
						*seq, TCP_SKB_CB(skb)->seq,
						tp->rcv_nxt, flags);
			}
```
因为offset = 0, len = 0, if (offset < skb->len)就不符合，报WARN。而且如果申请的len=0的skb过多，会导致一直在这里循环，因为WARN有打印堆栈，执行很慢。

错误如下：
```
	WARNING: at net/ipv4/tcp.c:1457 tcp_recvmsg+0x96a/0xc20() (Tainted: G	W  ---------------   )
	Hardware name: PowerEdge R620
	Modules linked in: sha256_generic ws_st_tcp_cubic(U) ws_st(U) autofs4 i2c_dev i2c_core bonding 8021q garp stp llc be2iscsi iscsi_boot_sysfs ib]
	Pid: 6964, comm: squid Tainted: G        W  ---------------    2.6.32-358.6.1.x86_64 #1
	Call Trace:
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff81069aa8>] ? warn_slowpath_common+0x98/0xc0
	 [<ffffffff81069bce>] ? warn_slowpath_fmt+0x6e/0x70
	 [<ffffffff814ce08e>] ? _spin_lock_bh+0x2e/0x40
	 [<ffffffff813fea53>] ? skb_release_data+0xb3/0x100
	 [<ffffffff813feb56>] ? __kfree_skb+0x46/0xa0
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff813f93c7>] ? sock_common_recvmsg+0x37/0x50
	 [<ffffffff813f6b05>] ? sock_aio_read+0x185/0x190
	 [<ffffffff81171912>] ? do_sync_read+0xf2/0x130
	 [<ffffffff81090e60>] ? autoremove_wake_function+0x0/0x40
	 [<ffffffff811b4a2c>] ? sys_epoll_wait+0x21c/0x3f0
	 [<ffffffff8120b3b6>] ? security_file_permission+0x16/0x20
	 [<ffffffff81171bab>] ? vfs_read+0x18b/0x1a0
	 [<ffffffff81172df5>] ? sys_read+0x55/0x90
	 [<ffffffff8100af72>] ? system_call_fastpath+0x16/0x1b
	---[ end trace ef9663ba0fc61730 ]---
	------------[ cut here ]------------
	WARNING: at net/ipv4/tcp.c:1457 tcp_recvmsg+0x96a/0xc20() (Tainted: G        W  ---------------   )
	Hardware name: PowerEdge R620
	Modules linked in: sha256_generic ws_st_tcp_cubic(U) ws_st(U) autofs4 i2c_dev i2c_core bonding 8021q garp stp llc be2iscsi iscsi_boot_sysfs ib]
	Pid: 6964, comm: squid Tainted: G        W  ---------------    2.6.32-358.6.1.x86_64 #1
	Call Trace:
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff81069aa8>] ? warn_slowpath_common+0x98/0xc0
	 [<ffffffff81069bce>] ? warn_slowpath_fmt+0x6e/0x70
	 [<ffffffff814ce08e>] ? _spin_lock_bh+0x2e/0x40
	 [<ffffffff813fea53>] ? skb_release_data+0xb3/0x100
	 [<ffffffff813feb56>] ? __kfree_skb+0x46/0xa0
	 [<ffffffff8144f1ca>] ? tcp_recvmsg+0x96a/0xc20
	 [<ffffffff813f93c7>] ? sock_common_recvmsg+0x37/0x50
	 [<ffffffff813f6b05>] ? sock_aio_read+0x185/0x190
	 [<ffffffff81171912>] ? do_sync_read+0xf2/0x130
	 [<ffffffff81090e60>] ? autoremove_wake_function+0x0/0x40
	 [<ffffffff811b4a2c>] ? sys_epoll_wait+0x21c/0x3f0
	 [<ffffffff8120b3b6>] ? security_file_permission+0x16/0x20
	 [<ffffffff81171bab>] ? vfs_read+0x18b/0x1a0
	 [<ffffffff81172df5>] ? sys_read+0x55/0x90
	 [<ffffffff8100af72>] ? system_call_fastpath+0x16/0x1b
	---[ end trace ef9663ba0fc61731 ]---
	------------[ cut here ]------------

	.......

```

如果skb申请的不多，很快就能看到tcp_cleanup_rbuf的WARN，仔细观察会发现，这里打印的end_seq和上面的seq是一样的。
```
	void tcp_cleanup_rbuf(struct sock *sk, int copied)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		int time_to_ack = 0;

	#if TCP_DEBUG
		struct sk_buff *skb = skb_peek(&sk->sk_receive_queue);

		WARN(skb && !before(tp->copied_seq, TCP_SKB_CB(skb)->end_seq),
			 KERN_INFO "cleanup rbuf bug: copied %X seq %X rcvnxt %X\n",
			 tp->copied_seq, TCP_SKB_CB(skb)->end_seq, tp->rcv_nxt);
	#endif
```
