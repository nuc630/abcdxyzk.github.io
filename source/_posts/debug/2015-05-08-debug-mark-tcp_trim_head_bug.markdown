---
layout: post
title: "tcp_trim_head BUG"
date: 2015-05-08 16:24:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~mark
tags:
---
http://kernel.opensuse.org/cgit/kernel/commit/?id=5b35e1e6e9ca651e6b291c96d1106043c9af314a

author	Neal Cardwell <ncardwell@google.com>	2012-01-28 17:29:46 (GMT)  
committer	David S. Miller <davem@davemloft.net>	2012-01-30 17:42:58 (GMT)  
commit	5b35e1e6e9ca651e6b291c96d1106043c9af314a (patch)  
tree	d18caadee5e93dc45d0c5fa2c530537cfa14586c  
parent	4acb41903b2f99f3dffd4c3df9acc84ca5942cb2 (diff)

#### tcp: fix tcp_trim_head() to adjust segment count with skb MSS

This commit fixes tcp_trim_head() to recalculate the number of segments in the skb with the skb's existing MSS, so trimming the head causes the skb segment count to be monotonically non-increasing - it should stay the same or go down, but not increase. 

Previously tcp_trim_head() used the current MSS of the connection. But if there was a decrease in MSS between original transmission and ACK (e.g. due to PMTUD), this could cause tcp_trim_head() to counter-intuitively increase the segment count when trimming bytes off the head of an skb. This violated assumptions in tcp_tso_acked() that tcp_trim_head() only decreases the packet count, so that packets_acked in tcp_tso_acked() could underflow, leading tcp_clean_rtx_queue() to pass u32 pkts_acked values as large as 0xffffffff to ca_ops->pkts_acked(). 

As an aside, if tcp_trim_head() had really wanted the skb to reflect the current MSS, it should have called tcp_set_skb_tso_segs() unconditionally, since a decrease in MSS would mean that a single-packet skb should now be sliced into multiple segments. 

Signed-off-by: Neal Cardwell <ncardwell@google.com>   
Acked-by: Nandita Dukkipati <nanditad@google.com>   
Acked-by: Ilpo Järvinen <ilpo.jarvinen@helsinki.fi>   
Signed-off-by: David S. Miller <davem@davemloft.net>  


1 files changed, 2 insertions, 4 deletions
```
	diff --git a/net/ipv4/tcp_output.c b/net/ipv4/tcp_output.c
	index 8c8de27..4ff3b6d 100644
	--- a/net/ipv4/tcp_output.c
	+++ b/net/ipv4/tcp_output.c
	@@ -1141,11 +1141,9 @@ int tcp_trim_head(struct sock *sk, struct sk_buff *skb, u32 len)
	 	sk_mem_uncharge(sk, len);
	 	sock_set_flag(sk, SOCK_QUEUE_SHRUNK);
	-	/* Any change of skb->len requires recalculation of tso
	-	 * factor and mss.
	-	 */
	+	/* Any change of skb->len requires recalculation of tso factor. */
	 	if (tcp_skb_pcount(skb) > 1)
	-		tcp_set_skb_tso_segs(sk, skb, tcp_current_mss(sk));
	+		tcp_set_skb_tso_segs(sk, skb, tcp_skb_mss(skb));
	 	return 0;
	 }
```

------------
会出现tp->packets_out不正确, 导致sk_write_queue为空时却掉tcp_rearm_rto()，判断tp->packets_out不为0，启动重传定时器，然后重传时取出的是list_head的地址，不是skb的地址，导致后面异常。



