---
layout: post
title: "ack loop"
date: 2015-09-30 15:32:00 +0800
comments: false
categories:
- 2015
- 2015~09
- debug
- debug~mark
tags:
---

#### patch

```
	commit 4fb17a6091674f469e8ac85dc770fbf9a9ba7cc8
	Author: Neal Cardwell <ncardwell@google.com>
	Date:   Fri Feb 6 16:04:41 2015 -0500

		tcp: mitigate ACK loops for connections as tcp_timewait_sock
		
		Ensure that in state FIN_WAIT2 or TIME_WAIT, where the connection is
		represented by a tcp_timewait_sock, we rate limit dupacks in response
		to incoming packets (a) with TCP timestamps that fail PAWS checks, or
		(b) with sequence numbers that are out of the acceptable window.
		
		We do not send a dupack in response to out-of-window packets if it has
		been less than sysctl_tcp_invalid_ratelimit (default 500ms) since we
		last sent a dupack in response to an out-of-window packet.
		
		Reported-by: Avery Fay <avery@mixpanel.com>
		Signed-off-by: Neal Cardwell <ncardwell@google.com>
		Signed-off-by: Yuchung Cheng <ycheng@google.com>
		Signed-off-by: Eric Dumazet <edumazet@google.com>
		Signed-off-by: David S. Miller <davem@davemloft.net>

	diff --git a/include/linux/tcp.h b/include/linux/tcp.h
	index 66d85a8..1a7adb4 100644
	--- a/include/linux/tcp.h
	+++ b/include/linux/tcp.h
	@@ -342,6 +342,10 @@ struct tcp_timewait_sock {
	 	u32			  tw_rcv_wnd;
	 	u32			  tw_ts_offset;
	 	u32			  tw_ts_recent;
	+
	+	/* The time we sent the last out-of-window ACK: */
	+	u32			  tw_last_oow_ack_time;
	+
	 	long			  tw_ts_recent_stamp;
	 #ifdef CONFIG_TCP_MD5SIG
	 	struct tcp_md5sig_key	  *tw_md5_key;
	diff --git a/net/ipv4/tcp_minisocks.c b/net/ipv4/tcp_minisocks.c
	index 98a8405..dd11ac7 100644
	--- a/net/ipv4/tcp_minisocks.c
	+++ b/net/ipv4/tcp_minisocks.c
	@@ -58,6 +58,25 @@ static bool tcp_in_window(u32 seq, u32 end_seq, u32 s_win, u32 e_win)
	 	return seq == e_win && seq == end_seq;
	 }
	 
	+static enum tcp_tw_status
	+tcp_timewait_check_oow_rate_limit(struct inet_timewait_sock *tw,
	+				  const struct sk_buff *skb, int mib_idx)
	+{
	+	struct tcp_timewait_sock *tcptw = tcp_twsk((struct sock *)tw);
	+
	+	if (!tcp_oow_rate_limited(twsk_net(tw), skb, mib_idx,
	+				  &tcptw->tw_last_oow_ack_time)) {
	+		/* Send ACK. Note, we do not put the bucket,
	+		 * it will be released by caller.
	+		 */
	+		return TCP_TW_ACK;
	+	}
	+
	+	/* We are rate-limiting, so just release the tw sock and drop skb. */
	+	inet_twsk_put(tw);
	+	return TCP_TW_SUCCESS;
	+}
	+
	 /*
	  * * Main purpose of TIME-WAIT state is to close connection gracefully,
	  *   when one of ends sits in LAST-ACK or CLOSING retransmitting FIN
	@@ -116,7 +135,8 @@ tcp_timewait_state_process(struct inet_timewait_sock *tw, struct sk_buff *skb,
	 		    !tcp_in_window(TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq,
	 				   tcptw->tw_rcv_nxt,
	 				   tcptw->tw_rcv_nxt + tcptw->tw_rcv_wnd))
	-			return TCP_TW_ACK;
	+			return tcp_timewait_check_oow_rate_limit(
	+				tw, skb, LINUX_MIB_TCPACKSKIPPEDFINWAIT2);
	 
	 		if (th->rst)
	 			goto kill;
	@@ -250,10 +270,8 @@ kill:
	 			inet_twsk_schedule(tw, &tcp_death_row, TCP_TIMEWAIT_LEN,
	 					   TCP_TIMEWAIT_LEN);
	 
	-		/* Send ACK. Note, we do not put the bucket,
	-		 * it will be released by caller.
	-		 */
	-		return TCP_TW_ACK;
	+		return tcp_timewait_check_oow_rate_limit(
	+			tw, skb, LINUX_MIB_TCPACKSKIPPEDTIMEWAIT);
	 	}
	 	inet_twsk_put(tw);
	 	return TCP_TW_SUCCESS;
	@@ -289,6 +307,7 @@ void tcp_time_wait(struct sock *sk, int state, int timeo)
	 		tcptw->tw_ts_recent	= tp->rx_opt.ts_recent;
	 		tcptw->tw_ts_recent_stamp = tp->rx_opt.ts_recent_stamp;
	 		tcptw->tw_ts_offset	= tp->tsoffset;
	+		tcptw->tw_last_oow_ack_time = 0;
	 
	 #if IS_ENABLED(CONFIG_IPV6)
	 		if (tw->tw_family == PF_INET6) {

	commit f2b2c582e82429270d5818fbabe653f4359d7024
	Author: Neal Cardwell <ncardwell@google.com>
	Date:   Fri Feb 6 16:04:40 2015 -0500

		tcp: mitigate ACK loops for connections as tcp_sock
		
		Ensure that in state ESTABLISHED, where the connection is represented
		by a tcp_sock, we rate limit dupacks in response to incoming packets
		(a) with TCP timestamps that fail PAWS checks, or (b) with sequence
		numbers or ACK numbers that are out of the acceptable window.
		
		We do not send a dupack in response to out-of-window packets if it has
		been less than sysctl_tcp_invalid_ratelimit (default 500ms) since we
		last sent a dupack in response to an out-of-window packet.
		
		There is already a similar (although global) rate-limiting mechanism
		for "challenge ACKs". When deciding whether to send a challence ACK,
		we first consult the new per-connection rate limit, and then the
		global rate limit.
		
		Reported-by: Avery Fay <avery@mixpanel.com>
		Signed-off-by: Neal Cardwell <ncardwell@google.com>
		Signed-off-by: Yuchung Cheng <ycheng@google.com>
		Signed-off-by: Eric Dumazet <edumazet@google.com>
		Signed-off-by: David S. Miller <davem@davemloft.net>

	diff --git a/include/linux/tcp.h b/include/linux/tcp.h
	index bcc828d..66d85a8 100644
	--- a/include/linux/tcp.h
	+++ b/include/linux/tcp.h
	@@ -153,6 +153,7 @@ struct tcp_sock {
	  	u32	snd_sml;	/* Last byte of the most recently transmitted small packet */
	 	u32	rcv_tstamp;	/* timestamp of last received ACK (for keepalives) */
	 	u32	lsndtime;	/* timestamp of last sent data packet (for restart window) */
	+	u32	last_oow_ack_time;  /* timestamp of last out-of-window ACK */
	 
	 	u32	tsoffset;	/* timestamp offset */
	 
	diff --git a/net/ipv4/tcp_input.c b/net/ipv4/tcp_input.c
	index 9401aa43..8fdd27b 100644
	--- a/net/ipv4/tcp_input.c
	+++ b/net/ipv4/tcp_input.c
	@@ -3322,13 +3322,22 @@ static int tcp_ack_update_window(struct sock *sk, const struct sk_buff *skb, u32
	 }
	 
	 /* RFC 5961 7 [ACK Throttling] */
	-static void tcp_send_challenge_ack(struct sock *sk)
	+static void tcp_send_challenge_ack(struct sock *sk, const struct sk_buff *skb)
	 {
	 	/* unprotected vars, we dont care of overwrites */
	 	static u32 challenge_timestamp;
	 	static unsigned int challenge_count;
	-	u32 now = jiffies / HZ;
	+	struct tcp_sock *tp = tcp_sk(sk);
	+	u32 now;
	+
	+	/* First check our per-socket dupack rate limit. */
	+	if (tcp_oow_rate_limited(sock_net(sk), skb,
	+				 LINUX_MIB_TCPACKSKIPPEDCHALLENGE,
	+				 &tp->last_oow_ack_time))
	+		return;
	 
	+	/* Then check the check host-wide RFC 5961 rate limit. */
	+	now = jiffies / HZ;
	 	if (now != challenge_timestamp) {
	 		challenge_timestamp = now;
	 		challenge_count = 0;
	@@ -3424,7 +3433,7 @@ static int tcp_ack(struct sock *sk, const struct sk_buff *skb, int flag)
	 	if (before(ack, prior_snd_una)) {
	 		/* RFC 5961 5.2 [Blind Data Injection Attack].[Mitigation] */
	 		if (before(ack, prior_snd_una - tp->max_window)) {
	-			tcp_send_challenge_ack(sk);
	+			tcp_send_challenge_ack(sk, skb);
	 			return -1;
	 		}
	 		goto old_ack;
	@@ -4993,7 +5002,10 @@ static bool tcp_validate_incoming(struct sock *sk, struct sk_buff *skb,
	 	    tcp_paws_discard(sk, skb)) {
	 		if (!th->rst) {
	 			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_PAWSESTABREJECTED);
	-			tcp_send_dupack(sk, skb);
	+			if (!tcp_oow_rate_limited(sock_net(sk), skb,
	+						  LINUX_MIB_TCPACKSKIPPEDPAWS,
	+						  &tp->last_oow_ack_time))
	+				tcp_send_dupack(sk, skb);
	 			goto discard;
	 		}
	 		/* Reset is accepted even if it did not pass PAWS. */
	@@ -5010,7 +5022,10 @@ static bool tcp_validate_incoming(struct sock *sk, struct sk_buff *skb,
	 		if (!th->rst) {
	 			if (th->syn)
	 				goto syn_challenge;
	-			tcp_send_dupack(sk, skb);
	+			if (!tcp_oow_rate_limited(sock_net(sk), skb,
	+						  LINUX_MIB_TCPACKSKIPPEDSEQ,
	+						  &tp->last_oow_ack_time))
	+				tcp_send_dupack(sk, skb);
	 		}
	 		goto discard;
	 	}
	@@ -5026,7 +5041,7 @@ static bool tcp_validate_incoming(struct sock *sk, struct sk_buff *skb,
	 		if (TCP_SKB_CB(skb)->seq == tp->rcv_nxt)
	 			tcp_reset(sk);
	 		else
	-			tcp_send_challenge_ack(sk);
	+			tcp_send_challenge_ack(sk, skb);
	 		goto discard;
	 	}
	 
	@@ -5040,7 +5055,7 @@ syn_challenge:
	 		if (syn_inerr)
	 			TCP_INC_STATS_BH(sock_net(sk), TCP_MIB_INERRS);
	 		NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPSYNCHALLENGE);
	-		tcp_send_challenge_ack(sk);
	+		tcp_send_challenge_ack(sk, skb);
	 		goto discard;
	 	}
	 
	diff --git a/net/ipv4/tcp_minisocks.c b/net/ipv4/tcp_minisocks.c
	index 131aa49..98a8405 100644
	--- a/net/ipv4/tcp_minisocks.c
	+++ b/net/ipv4/tcp_minisocks.c
	@@ -467,6 +467,7 @@ struct sock *tcp_create_openreq_child(struct sock *sk, struct request_sock *req,
	 		tcp_enable_early_retrans(newtp);
	 		newtp->tlp_high_seq = 0;
	 		newtp->lsndtime = treq->snt_synack;
	+		newtp->last_oow_ack_time = 0;
	 		newtp->total_retrans = req->num_retrans;
	 
	 		/* So many TCP implementations out there (incorrectly) count the

	commit a9b2c06dbef48ed31cff1764c5ce824829106f4f
	Author: Neal Cardwell <ncardwell@google.com>
	Date:   Fri Feb 6 16:04:39 2015 -0500

		tcp: mitigate ACK loops for connections as tcp_request_sock
		
		In the SYN_RECV state, where the TCP connection is represented by
		tcp_request_sock, we now rate-limit SYNACKs in response to a client's
		retransmitted SYNs: we do not send a SYNACK in response to client SYN
		if it has been less than sysctl_tcp_invalid_ratelimit (default 500ms)
		since we last sent a SYNACK in response to a client's retransmitted
		SYN.
		
		This allows the vast majority of legitimate client connections to
		proceed unimpeded, even for the most aggressive platforms, iOS and
		MacOS, which actually retransmit SYNs 1-second intervals for several
		times in a row. They use SYN RTO timeouts following the progression:
		1,1,1,1,1,2,4,8,16,32.
		
		Reported-by: Avery Fay <avery@mixpanel.com>
		Signed-off-by: Neal Cardwell <ncardwell@google.com>
		Signed-off-by: Yuchung Cheng <ycheng@google.com>
		Signed-off-by: Eric Dumazet <edumazet@google.com>
		Signed-off-by: David S. Miller <davem@davemloft.net>

	diff --git a/include/linux/tcp.h b/include/linux/tcp.h
	index 67309ec..bcc828d 100644
	--- a/include/linux/tcp.h
	+++ b/include/linux/tcp.h
	@@ -115,6 +115,7 @@ struct tcp_request_sock {
	 	u32				rcv_isn;
	 	u32				snt_isn;
	 	u32				snt_synack; /* synack sent time */
	+	u32				last_oow_ack_time; /* last SYNACK */
	 	u32				rcv_nxt; /* the ack # by SYNACK. For
	 						  * FastOpen it's the seq#
	 						  * after data-in-SYN.
	diff --git a/include/net/tcp.h b/include/net/tcp.h
	index b81f45c..da4196fb 100644
	--- a/include/net/tcp.h
	+++ b/include/net/tcp.h
	@@ -1145,6 +1145,7 @@ static inline void tcp_openreq_init(struct request_sock *req,
	 	tcp_rsk(req)->rcv_isn = TCP_SKB_CB(skb)->seq;
	 	tcp_rsk(req)->rcv_nxt = TCP_SKB_CB(skb)->seq + 1;
	 	tcp_rsk(req)->snt_synack = tcp_time_stamp;
	+	tcp_rsk(req)->last_oow_ack_time = 0;
	 	req->mss = rx_opt->mss_clamp;
	 	req->ts_recent = rx_opt->saw_tstamp ? rx_opt->rcv_tsval : 0;
	 	ireq->tstamp_ok = rx_opt->tstamp_ok;
	diff --git a/net/ipv4/tcp_minisocks.c b/net/ipv4/tcp_minisocks.c
	index bc9216d..131aa49 100644
	--- a/net/ipv4/tcp_minisocks.c
	+++ b/net/ipv4/tcp_minisocks.c
	@@ -605,7 +605,11 @@ struct sock *tcp_check_req(struct sock *sk, struct sk_buff *skb,
	 		 * Reset timer after retransmitting SYNACK, similar to
	 		 * the idea of fast retransmit in recovery.
	 		 */
	-		if (!inet_rtx_syn_ack(sk, req))
	+		if (!tcp_oow_rate_limited(sock_net(sk), skb,
	+					  LINUX_MIB_TCPACKSKIPPEDSYNRECV,
	+					  &tcp_rsk(req)->last_oow_ack_time) &&
	+
	+		    !inet_rtx_syn_ack(sk, req))
	 			req->expires = min(TCP_TIMEOUT_INIT << req->num_timeout,
	 					   TCP_RTO_MAX) + jiffies;
	 		return NULL;

	commit 032ee4236954eb214651cb9bfc1b38ffa8fd7a01
	Author: Neal Cardwell <ncardwell@google.com>
	Date:   Fri Feb 6 16:04:38 2015 -0500

		tcp: helpers to mitigate ACK loops by rate-limiting out-of-window dupacks
		
		Helpers for mitigating ACK loops by rate-limiting dupacks sent in
		response to incoming out-of-window packets.
		
		This patch includes:
		
		- rate-limiting logic
		- sysctl to control how often we allow dupacks to out-of-window packets
		- SNMP counter for cases where we rate-limited our dupack sending
		
		The rate-limiting logic in this patch decides to not send dupacks in
		response to out-of-window segments if (a) they are SYNs or pure ACKs
		and (b) the remote endpoint is sending them faster than the configured
		rate limit.
		
		We rate-limit our responses rather than blocking them entirely or
		resetting the connection, because legitimate connections can rely on
		dupacks in response to some out-of-window segments. For example, zero
		window probes are typically sent with a sequence number that is below
		the current window, and ZWPs thus expect to thus elicit a dupack in
		response.
		
		We allow dupacks in response to TCP segments with data, because these
		may be spurious retransmissions for which the remote endpoint wants to
		receive DSACKs. This is safe because segments with data can't
		realistically be part of ACK loops, which by their nature consist of
		each side sending pure/data-less ACKs to each other.
		
		The dupack interval is controlled by a new sysctl knob,
		tcp_invalid_ratelimit, given in milliseconds, in case an administrator
		needs to dial this upward in the face of a high-rate DoS attack. The
		name and units are chosen to be analogous to the existing analogous
		knob for ICMP, icmp_ratelimit.
		
		The default value for tcp_invalid_ratelimit is 500ms, which allows at
		most one such dupack per 500ms. This is chosen to be 2x faster than
		the 1-second minimum RTO interval allowed by RFC 6298 (section 2, rule
		2.4). We allow the extra 2x factor because network delay variations
		can cause packets sent at 1 second intervals to be compressed and
		arrive much closer.
		
		Reported-by: Avery Fay <avery@mixpanel.com>
		Signed-off-by: Neal Cardwell <ncardwell@google.com>
		Signed-off-by: Yuchung Cheng <ycheng@google.com>
		Signed-off-by: Eric Dumazet <edumazet@google.com>
		Signed-off-by: David S. Miller <davem@davemloft.net>

	diff --git a/Documentation/networking/ip-sysctl.txt b/Documentation/networking/ip-sysctl.txt
	index a5e4c81..1b8c964 100644
	--- a/Documentation/networking/ip-sysctl.txt
	+++ b/Documentation/networking/ip-sysctl.txt
	@@ -290,6 +290,28 @@ tcp_frto - INTEGER
	 
	 	By default it's enabled with a non-zero value. 0 disables F-RTO.
	 
	+tcp_invalid_ratelimit - INTEGER
	+	Limit the maximal rate for sending duplicate acknowledgments
	+	in response to incoming TCP packets that are for an existing
	+	connection but that are invalid due to any of these reasons:
	+
	+	  (a) out-of-window sequence number,
	+	  (b) out-of-window acknowledgment number, or
	+	  (c) PAWS (Protection Against Wrapped Sequence numbers) check failure
	+
	+	This can help mitigate simple "ack loop" DoS attacks, wherein
	+	a buggy or malicious middlebox or man-in-the-middle can
	+	rewrite TCP header fields in manner that causes each endpoint
	+	to think that the other is sending invalid TCP segments, thus
	+	causing each side to send an unterminating stream of duplicate
	+	acknowledgments for invalid segments.
	+
	+	Using 0 disables rate-limiting of dupacks in response to
	+	invalid segments; otherwise this value specifies the minimal
	+	space between sending such dupacks, in milliseconds.
	+
	+	Default: 500 (milliseconds).
	+
	 tcp_keepalive_time - INTEGER
	 	How often TCP sends out keepalive messages when keepalive is enabled.
	 	Default: 2hours.
	diff --git a/include/net/tcp.h b/include/net/tcp.h
	index 28e9bd3..b81f45c 100644
	--- a/include/net/tcp.h
	+++ b/include/net/tcp.h
	@@ -274,6 +274,7 @@ extern int sysctl_tcp_challenge_ack_limit;
	 extern unsigned int sysctl_tcp_notsent_lowat;
	 extern int sysctl_tcp_min_tso_segs;
	 extern int sysctl_tcp_autocorking;
	+extern int sysctl_tcp_invalid_ratelimit;
	 
	 extern atomic_long_t tcp_memory_allocated;
	 extern struct percpu_counter tcp_sockets_allocated;
	@@ -1236,6 +1237,37 @@ static inline bool tcp_paws_reject(const struct tcp_options_received *rx_opt,
	 	return true;
	 }
	 
	+/* Return true if we're currently rate-limiting out-of-window ACKs and
	+ * thus shouldn't send a dupack right now. We rate-limit dupacks in
	+ * response to out-of-window SYNs or ACKs to mitigate ACK loops or DoS
	+ * attacks that send repeated SYNs or ACKs for the same connection. To
	+ * do this, we do not send a duplicate SYNACK or ACK if the remote
	+ * endpoint is sending out-of-window SYNs or pure ACKs at a high rate.
	+ */
	+static inline bool tcp_oow_rate_limited(struct net *net,
	+					const struct sk_buff *skb,
	+					int mib_idx, u32 *last_oow_ack_time)
	+{
	+	/* Data packets without SYNs are not likely part of an ACK loop. */
	+	if ((TCP_SKB_CB(skb)->seq != TCP_SKB_CB(skb)->end_seq) &&
	+	    !tcp_hdr(skb)->syn)
	+		goto not_rate_limited;
	+
	+	if (*last_oow_ack_time) {
	+		s32 elapsed = (s32)(tcp_time_stamp - *last_oow_ack_time);
	+
	+		if (0 <= elapsed && elapsed < sysctl_tcp_invalid_ratelimit) {
	+			NET_INC_STATS_BH(net, mib_idx);
	+			return true;	/* rate-limited: don't send yet! */
	+		}
	+	}
	+
	+	*last_oow_ack_time = tcp_time_stamp;
	+
	+not_rate_limited:
	+	return false;	/* not rate-limited: go ahead, send dupack now! */
	+}
	+
	 static inline void tcp_mib_init(struct net *net)
	 {
	 	/* See RFC 2012 */
	diff --git a/include/uapi/linux/snmp.h b/include/uapi/linux/snmp.h
	index b222241..6a6fb74 100644
	--- a/include/uapi/linux/snmp.h
	+++ b/include/uapi/linux/snmp.h
	@@ -270,6 +270,12 @@ enum
	 	LINUX_MIB_TCPHYSTARTTRAINCWND,		/* TCPHystartTrainCwnd */
	 	LINUX_MIB_TCPHYSTARTDELAYDETECT,	/* TCPHystartDelayDetect */
	 	LINUX_MIB_TCPHYSTARTDELAYCWND,		/* TCPHystartDelayCwnd */
	+	LINUX_MIB_TCPACKSKIPPEDSYNRECV,		/* TCPACKSkippedSynRecv */
	+	LINUX_MIB_TCPACKSKIPPEDPAWS,		/* TCPACKSkippedPAWS */
	+	LINUX_MIB_TCPACKSKIPPEDSEQ,		/* TCPACKSkippedSeq */
	+	LINUX_MIB_TCPACKSKIPPEDFINWAIT2,	/* TCPACKSkippedFinWait2 */
	+	LINUX_MIB_TCPACKSKIPPEDTIMEWAIT,	/* TCPACKSkippedTimeWait */
	+	LINUX_MIB_TCPACKSKIPPEDCHALLENGE,	/* TCPACKSkippedChallenge */
	 	__LINUX_MIB_MAX
	 };
	 
	diff --git a/net/ipv4/proc.c b/net/ipv4/proc.c
	index 8f9cd20..d8953ef 100644
	--- a/net/ipv4/proc.c
	+++ b/net/ipv4/proc.c
	@@ -292,6 +292,12 @@ static const struct snmp_mib snmp4_net_list[] = {
	 	SNMP_MIB_ITEM("TCPHystartTrainCwnd", LINUX_MIB_TCPHYSTARTTRAINCWND),
	 	SNMP_MIB_ITEM("TCPHystartDelayDetect", LINUX_MIB_TCPHYSTARTDELAYDETECT),
	 	SNMP_MIB_ITEM("TCPHystartDelayCwnd", LINUX_MIB_TCPHYSTARTDELAYCWND),
	+	SNMP_MIB_ITEM("TCPACKSkippedSynRecv", LINUX_MIB_TCPACKSKIPPEDSYNRECV),
	+	SNMP_MIB_ITEM("TCPACKSkippedPAWS", LINUX_MIB_TCPACKSKIPPEDPAWS),
	+	SNMP_MIB_ITEM("TCPACKSkippedSeq", LINUX_MIB_TCPACKSKIPPEDSEQ),
	+	SNMP_MIB_ITEM("TCPACKSkippedFinWait2", LINUX_MIB_TCPACKSKIPPEDFINWAIT2),
	+	SNMP_MIB_ITEM("TCPACKSkippedTimeWait", LINUX_MIB_TCPACKSKIPPEDTIMEWAIT),
	+	SNMP_MIB_ITEM("TCPACKSkippedChallenge", LINUX_MIB_TCPACKSKIPPEDCHALLENGE),
	 	SNMP_MIB_SENTINEL
	 };
	 
	diff --git a/net/ipv4/sysctl_net_ipv4.c b/net/ipv4/sysctl_net_ipv4.c
	index e0ee384..82601a6 100644
	--- a/net/ipv4/sysctl_net_ipv4.c
	+++ b/net/ipv4/sysctl_net_ipv4.c
	@@ -729,6 +729,13 @@ static struct ctl_table ipv4_table[] = {
	 		.extra2		= &one,
	 	},
	 	{
	+		.procname	= "tcp_invalid_ratelimit",
	+		.data		= &sysctl_tcp_invalid_ratelimit,
	+		.maxlen		= sizeof(int),
	+		.mode		= 0644,
	+		.proc_handler	= proc_dointvec_ms_jiffies,
	+	},
	+	{
	 		.procname	= "icmp_msgs_per_sec",
	 		.data		= &sysctl_icmp_msgs_per_sec,
	 		.maxlen		= sizeof(int),
	diff --git a/net/ipv4/tcp_input.c b/net/ipv4/tcp_input.c
	index d3dfff7..9401aa43 100644
	--- a/net/ipv4/tcp_input.c
	+++ b/net/ipv4/tcp_input.c
	@@ -100,6 +100,7 @@ int sysctl_tcp_thin_dupack __read_mostly;
	 
	 int sysctl_tcp_moderate_rcvbuf __read_mostly = 1;
	 int sysctl_tcp_early_retrans __read_mostly = 3;
	+int sysctl_tcp_invalid_ratelimit __read_mostly = HZ/2;
	 
	 #define FLAG_DATA		0x01 /* Incoming frame contained data.		*/
	 #define FLAG_WIN_UPDATE		0x02 /* Incoming ACK was a window update.	*/
```

---------------------

#### sample

```
	#define KMSG_COMPONENT "synflood"
	#define pr_fmt(fmt) KMSG_COMPONENT ": " fmt

	#include <linux/module.h>
	#include <linux/kernel.h>
	#include <linux/ip.h>
	#include <linux/tcp.h>
	#include <linux/icmp.h>
	#include <linux/netfilter.h>
	#include <linux/netfilter_ipv4.h>
	#include <linux/netdevice.h>

	#include <net/ip.h>
	#include <net/tcp.h>
	#include <net/udp.h>
	#include <net/icmp.h>

	__be16 cport = 80;
	char *selfip = NULL;

	module_param(cport, short, S_IRUGO);
	module_param(selfip, charp, S_IRUGO);

	void skbcsum(struct sk_buff *skb)
	{
		struct tcphdr *tcph;
		struct iphdr *iph;
		int iphl;
		int tcphl;
		int tcplen;

		iph = (struct iphdr *)skb->data;
		iphl = iph->ihl << 2;
		tcph = (struct tcphdr *)(skb->data + iphl);
		tcphl = tcph->doff << 2;

		iph->check = 0;
		iph->check = ip_fast_csum((unsigned char *)iph, iph->ihl);

		tcph->check    = 0;
		tcplen        = skb->len - (iph->ihl << 2);
		if (skb->ip_summed == CHECKSUM_PARTIAL) {
			tcph->check = ~csum_tcpudp_magic(iph->saddr, iph->daddr,
					tcplen, IPPROTO_TCP, 0);
			skb->csum_start    = skb_transport_header(skb) - skb->head;
			skb->csum_offset = offsetof(struct tcphdr, check);
		}
		else {
			skb->csum = 0;
			skb->csum = skb_checksum(skb, iph->ihl << 2, tcplen, 0);
			tcph->check = csum_tcpudp_magic(iph->saddr, iph->daddr,
					tcplen, IPPROTO_TCP, skb->csum);

		}
	}

	int pktcome = 0;
	int fincome = 0;
	static int check(__be32 ip, __be16 port, int syn, int fin)
	{
		if ((selfip == NULL || ip == in_aton(selfip)) && ntohs(port) == cport) {
			if (syn) {
				pktcome = 0;
				fincome = 0;
			}
			pktcome ++;
			if (pktcome > 30 || fincome == 3)
				return 1;
			fincome |= fin;
		}
		return 0;
	}

	static unsigned int local_in(unsigned int hooknum, 
		struct sk_buff *skb, const struct net_device *in, 
		const struct net_device *out, int (*okfn) (struct sk_buff *))
	{
		struct iphdr *iph;
		struct tcphdr *th;

		if (unlikely(skb->pkt_type != PACKET_HOST))
			goto exit;
		if (unlikely(skb->protocol != __constant_htons(ETH_P_IP)))
			goto exit;
		iph = (struct iphdr *)skb_network_header(skb);
		if (iph->protocol != IPPROTO_TCP)
			goto exit;
		if (unlikely(!pskb_may_pull(skb, iph->ihl * 4 + sizeof(struct tcphdr))))
			goto drop_out;
		skb_set_transport_header(skb, iph->ihl * 4);
		th = tcp_hdr(skb);
		if (check(iph->daddr, th->dest, th->syn, th->fin)) {
			skb->ip_summed = CHECKSUM_UNNECESSARY;
			th->seq = htonl(ntohl(th->seq) + 10000000);
		}
	exit:
		return NF_ACCEPT;
	drop_out:
		return NF_DROP;
	}

	static unsigned int local_out(unsigned int hooknum, 
		struct sk_buff *skb, const struct net_device *in, 
		const struct net_device *out, int (*okfn) (struct sk_buff *))
	{
		struct iphdr *iph;
		struct tcphdr *th;

		iph = (struct iphdr *)skb_network_header(skb);
		if (iph->protocol != IPPROTO_TCP)
			goto exit;
		if (unlikely(!pskb_may_pull(skb, iph->ihl * 4 + sizeof(struct tcphdr))))
			goto drop_out;
		skb_set_transport_header(skb, iph->ihl * 4);
		th = tcp_hdr(skb);
		if (check(iph->saddr, th->source, 0, (th->fin) << 1)) {
			th->seq = htonl(ntohl(th->seq) + 10000000);
			skbcsum(skb);
		}
	exit:
		return NF_ACCEPT;
	drop_out:
		return NF_DROP;
	}

	static struct nf_hook_ops syndef_ops[] __read_mostly = {
		{
			.hook = local_in,
			.owner = THIS_MODULE,
			.pf = PF_INET,
			.hooknum = NF_INET_LOCAL_IN,
			.priority = 100,
		},
		{
			.hook = local_out,
			.owner = THIS_MODULE,
			.pf = PF_INET,
			.hooknum = NF_INET_LOCAL_OUT,
			.priority = 100,
		},

	};

	int __init loopack_init(void)
	{
		int ret;

		ret = nf_register_hooks(syndef_ops, ARRAY_SIZE(syndef_ops));
		if (ret < 0) {
			pr_err("can't register hooks.\n");
			goto hooks_err;
		}

		pr_err("init success.\n");

	hooks_err:
		return ret;
	}

	void __exit loopack_exit(void)
	{
		nf_unregister_hooks(syndef_ops, ARRAY_SIZE(syndef_ops));

		pr_err("unload success.\n");
	}

	module_init(loopack_init);
	module_exit(loopack_exit);
	MODULE_AUTHOR("kk");
	MODULE_VERSION("1.0.0");
	MODULE_LICENSE("GPL");
```
