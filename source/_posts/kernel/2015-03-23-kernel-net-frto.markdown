---
layout: post
title: "FRTO—虚假超时剖析"
date: 2015-03-23 14:37:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/7446441

F-RTO：Forward RTO-Recovery，for a TCP sender to recover after a retransmission timeout.
F-RTO的主要目的：The main motivation of the algorithm is to recover efficiently from a spurious
RTO.

#### F-RTO的基本思想
The guideline behind F-RTO is, that an RTO either indicates a loss, or it is caused by an
excessive delay in packet delivery while there still are outstanding segments in flight. If the
RTO was due to delay, i.e. the RTO was spurious, acknowledgements for non-retransmitted
segments sent before the RTO should arrive at the sender after the RTO occurred. If no such
segments arrive, the RTO is concluded to be non-spurious and the conventional RTO
recovery with go-back-N retransmissions should take place at the TCP sender. 

To implement the principle described above, an F-RTO sender acts as follows: if the first ACK
arriving after a RTO-triggered retransmission advances the window, transmit two new segments
instead of continuing retransmissions. If also the second incoming acknowledgement advances
the window, RTO is likely to be spurious, because the second ACK is triggered by an originally
transmitted segment that has not been retransmitted after the RTO. If either one of the two
acknowledgements after RTO is a duplicate ACK, the sender continues retransmissions similarly
to the conventional RTO recovery algorithm.

When the retransmission timer expires, the F-RTO algorithm takes the following steps at the TCP
sender. In the algorithm description below we use SND.UNA to indicate the first unacknowledged
segment. 

1.When the retransmission timer expires, retransmit the segment that triggered the timeout. As
required by the TCP congestion control specifications, the ssthresh is adjusted to half of the
number of currently outstanding segments. However, the congestion window is not yet set to one
segment, but the sender waits for the next two acknowledgements before deciding on what to do
with the congestion window.

2.When the first acknowledgement after RTO arrives at the sender, the sender chooses the
following actions depending on whether the ACK advances the window or whether it is a duplicate
ACK.

（a）If the acknowledgement advances SND.UNA, transmit up to two new (previously unsent)
segments. This is the main point in which the F-RTO algorithm differs from the conventional way
of recovering from RTO. After transmitting the two new segments, the congestion window size
is set to have the same value as ssthresh. In effect this reduces the transmission rate of the
sender to half of the transmission rate before the RTO. At this point the TCP sender has transmitted
a total of three segments after the RTO, similarly to the conventional recovery algorithm. If
transmitting two new segments is not possible due to advertised window limitation, or because
there is no more data to send, the sender may transmit only one segment. If now new data can
be transmitted, the TCP sender follows the conventional RTO recovery algorithm and starts
retransmitting the unacknowledged data using slow start.

（b）If the acknowledgement is duplicate ACK, set the congestion window to one segment and
proceed with the conventional RTO recovery. Two new segments are not transmitted in this case,
because the conventional RTO recovery algorithm would not transmit anything at this point either.
Instead, the F-RTO sender continues with slow start and performs similarly to the conventional
TCP sender in retransmitting the unacknowledged segments. Step 3 of the F-RTO algorithm is
not entered in this case. A common reason for executing this branch is the loss of a segment,
in which case the segments injected by the sender before the RTO may still trigger duplicate
ACKs that arrive at the sender after the RTO.

3.When the second acknowledgement after the RTO arrives, either continue transmitting new
data, or start retransmitting with the slow start algorithm, depending on whether new data was
acknowledged.

（a）If the acknowledgement advances SND.UNA, continue transmitting new data following
the congestion avoidance algorithm. Because the TCP sender has retransmitted only one
segment after the RTO, this acknowledgement indicates that an originally transmitted
segment has arrived at the receiver. This is regarded as a strong indication of a suprious
RTO. However, since the TCP sender cannot surely know at this point whether the segment
that triggered the RTO was actually lost, adjusting the congestion control parameters after
the RTO is the conservative action. From this point on, the TCP sender continues as in the
normal congestion avoidance.

If this algorithm branch is taken, the TCP sender ignores the send_high variable that indicates
the highest sequence number transmitted so far. The send_high variable was proposed as a
bugfix for avoiding unnecessary multiple fast retransmits when RTO expires during fast recovery
with NewReon TCP. As the sender has not retransmitted other segments but the one that
triggered RTO, the problem addressed by the bugfix cannot occur. Therefore, if there are
duplicate ACKs arriving at the sender after the RTO, they are likely to indicate a packet loss,
hence fast retransmit should bu used to allow efficient recovery. Alternatively, if there are not
enough duplicate ACKs arriving at the sender after a packet loss, the retransmission timer
expires another time and the sender enters step 1 of this algorithm to detect whether the
new RTO is spurious.

（b）If the acknowledgement is duplicate ACK, set the congestion window to three segments,
continue with the slow start algorithm retransmitting unacknowledged segments. The duplicate
ACK indicates that at least one segment other than the segment that triggered RTO is lost in the
last window of data. There is no sufficient evidence that any of the segments was delayed.
Therefore the sender proceeds with retransmissions similarly to the conventional RTO recovery
algorithm, with the send_high variable stored when the retransmission timer expired to avoid
unnecessary fast retransmits.

 
#### 引起RTO的主要因素：
（1）Sudden delays  
The primary motivation of the F-RTO algorithm is to improve the TCP performance when sudden
delays cause spurious retransmission timeouts.

（2）Packet losses  
These timeouts occur mainly when retransmissions are lost, since lost original packets are
usually recovered by fast retransmit.

（3）Bursty losses  
Losses of several successive packets can result in a retransmission timeout.

##### 造成虚假RTO的原因还有：
Wireless links may also suffer from link outages that cause persistent data loss for a period
of time.  
Oher potential reasons for sudden delays that have been reported to trigger spurious RTOs
include a delay due to tedious actions required to complete a hand-off or re-routing of packets
to the new serving access point after the hand-off, arrival of competing traffic on a shared link
with low bandwidth, and a sudden bandwidth degradation due to reduced resources on a
wireless channel.

##### 造成真实RTO的原因：
A RTO-triggered retransmission is needed when a retransmission is lost, or when nearly a whole
window of data is lost, thus making it impossible for the receiver to generate enough duplicate
ACKs for triggering TCP fast retransmit.

#### 虚假RTO的后果
If no segments were lost but the retransmission timer expires spuriously, the segments retransmitted
in the slow-start are sent unnecessarily. Particularly, this phenomenon is very possible with the
various wireless access network technologies that are prone to sudden delay spikes.
The retransmission timer expires because of the delay, spuriously triggering the RTO recovery and
unnecessarily retransmission of all unacknowledged segments. This happens because after the
delay the ACKs for the original segments arrive at the sender one at the time but too late, because
the TCP sender has already entered the RTO recovery. Therefore, each of the ACKs trigger the
retransmission of segments for which the original ACKs will arrive after a while. This continues
until the whole window of segments is eventually unnecessarily retransmitted. Furthermore,
because a full window of retransmitted segments arrive unnecessarily at the receiver, it generates
duplicate ACKs for these out-of-order segments. Later on, the duplicate ACKs unnecessarily
trigger fast retransmit at the sender. 

TCP uses the fast retransmit mechanism to trigger retransmissions after receiving three successive
duplicate acknowledgements (ACKs). If for a certain time period TCP sender does not receive ACKs
that acknowledge new data, the TCP retransmission timer expires as a backoff mechanism.
When the retransmission time expires, the TCP sender retransmits the first unacknowledged
segment assuming it was lost in the network. Because a retransmission timeout (RTO) can be
an indication of severe congestion in the network, the TCP sender resets its congestion window
to one segment and starts increasing it according to the slow start algorithm.
However, if the RTO occurs spuriously and there still are segments outstanding in the network,
a false slow start is harmful for the potentially congested network as it injects extra segments
to the network at increasing rate.

虚假的RTO不仅会降低吞吐量，而且由于丢包后会使用慢启动算法，快速的向网络中注入数据包，
而此时网络中还有原来发送的数据包，这样可能会造成真正的网络拥塞！

How about Reliable link-layer protocol ?
Since wireless networks are often subject to high packet loss rate due to corruption or hand-offs,
reliable link-layer protocols are widely employed with wireless links. The link-layer receiver often
aims to deliver the packets to the upper protocol layers in order, which implies that the later
arriving packets are blocked until the head of the queue arrives successfully. Due to the strict
link-layer ordering, the communication end point observe a pause in packet delivery that can
cause a spurious TCP RTO instead of getting out-of-order packets that could result in a false
fast retransmit instead. Either way, interaction between TCP retransmission mechanisms
and link-layer recovery can cause poor performance.

DSACK不能解决此问题
If the unnecessary retransmissions occurred due to spurious RTO caused by a sudden delay,
the acknowledgements with the DSACK information arrive at the sender only after the
acknowledgements of the original segments. Therefore, the unnecessary retransmissions
following the spurious RTO cannot be avoided by using DSACK. Instead, the suggested
recovery algorithm using DSACK can only revert the congestion control parameters to the
state preceding the spurious retransmissions.

 
#### F-RTO实现
F-RTO is implemented (mainly) in four functions:  
（1）tcp_use_frto() is used to determine if TCP can use F-RTO.  

（2）tcp_enter_frto() prepares TCP state on RTO if F-RTO is used, it is called when tcp_use_frto() showed green light.  

（3）tcp_process_frto() handles incoming ACKs during F-RTO algorithm.

（4）tcp_enter_frto_loss() is called if there is not enough evidence to prove that the RTO is indeed spurious. It transfers the control from F-RTO to the conventional RTO recovery.

#### 判断是否可以使用F-RTO
 调用时机：当TCP段传送超时后，会引起段的重传，在重传定时器的处理过程中会判断是否可以使用F-RTO算法。

```
	void tcp_retransmit_timer (struct sock *sk)  
	{  
		....  
	  
		if (tcp_use_frto(sk)) {  
			tcp_enter_frto(sk);  
		} else {  
			tcp_enter_loss(sk);  
		}  
	  
		....  
	}
```

能够使用F-RTO的条件：  
（1）tcp_frto非零，此为TCP参数  
（2）MTU probe没使用，因为它和F-RTO有冲突  
（3）a. 如果启用了sackfrto，则可以使用  
  b. 如果没启用sackfrto，不能重传过除head以外的数据  

```
	/* F-RTO can only be used if TCP has never retransmitted anything other than 
	 * head (SACK enhanced variant from Appendix B of RFC4138 is more robust here) 
	 */  
	int tcp_use_frto(struct sock *sk)  
	{  
		const struct tcp_sock *tp = tcp_sk(sk);  
		const struct inet_connection_sock *icsk = inet_csk(sk);  
		struct sk_buff *skb;  
	  
		if (! sysctl_tcp_frto)  
			return 0;  
	  
		/* MTU probe and F-RTO won't really play nicely along currently */  
		if (icsk->icsk_mtup.probe_size)  
			return 0;  
	  
		if (tcp_is_sackfrto(tp))  
			return 1;  
	  
		/* Avoid expensive walking of rexmit queue if possible */  
		if (tp->retrans_out > 1)  
			return 0; /* 不能重过传除了head以外的数据*/  
	  
		skb = tcp_write_queue_head(sk);  
		if (tcp_skb_is_last(sk, skb))  
			return 1;  
		skb = tcp_write_queue_next(sk, skb); /* Skips head */  
		tcp_for_write_queue_from(skb, sk) {  
			if (skb == tcp_send_head(sk))  
				break;  
	  
			if (TCP_SKB_CB(skb)->sacked & TCPCB_RETRANS)  
				return 0; /* 不允许处head以外的数据包被重传过 */  
	  
			/* Short-circut when first non-SACKed skb has been checked */  
			if (! (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED))  
			break;  
		}  
		return 1;  
	}  
	  
	static int tcp_is_sackfrto(const struct tcp_sock *tp)  
	{  
		return (sysctl_tcp_frto == 0x2) && ! tcp_is_reno(tp);  
	}
```

#### 进入F-RTO状态
启用F-RTO后，虽然传送超时，但还没进入Loss状态，相反，先进入Disorder状态。减小慢启动阈值，而snd_cwnd暂时保持不变。此时对应head数据包还没重传前。

```
	/* RTO occurred, but do not yet enter Loss state. Instead, defer RTO recovery 
	 * a bit and use heuristics in tcp_process_frto() to detect if the RTO was  
	 * spurious. 
	 */  
	  
	void tcp_enter_frto (struct sock *sk)  
	{  
		const struct inet_connection_sock *icsk = inet_csk(sk);  
		struct tcp_sock *tp = tcp_sk(sk);  
		struct sk_buff *skb;  
	  
		/* Do like tcp_enter_loss() would*/  
		if ((! tp->frto_counter && icsk->icsk_ca_state <= TCP_CA_Disorder) ||  
			tp->snd_una == tp->high_seq ||   
			((icsk->icsk_ca_state == TCP_CA_Loss || tp->frto_counter) &&  
			! icsk->icsk_retransmits)) {  
	  
			tp->prior_ssthresh = tcp_current_ssthresh(sk); /* 保存旧阈值*/  
	  
			if (tp->frto_counter) {   
				u32 stored_cwnd;  
				stored_cwnd = tp->snd_cwnd;  
				tp->snd_cwnd = 2;  
				tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk);  
				tp->snd_cwnd = stored_cwnd;  
			} else {  
				tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk); /* 减小阈值*/  
			}  
	  
			tcp_ca_event(sk, CA_EVENT_FRTO); /* 触发FRTO事件 */  
		}  
	  
		tp->undo_marker = tp->snd_una;  
		tp->undo_retrans = 0;  
	  
		skb = tcp_write_queue_head(sk);  
		if (TCP_SKB_CB(skb)->sacked & TCPCB_RETRANS)  
			tp->undo_marker = 0;  
	  
		/* 清除head与重传相关的标志*/  
		if (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS) {  
			TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_RETRANS;  
			tp->retrans_out -= tcp_skb_pcount(skb);  
		}  
	  
		tcp_verfify_left_out(tp);  
	  
		/* Too bad if TCP was application limited */  
		tp->snd_cwnd = min(tp->snd_cwnd, tcp_packets_in_flight(tp) + 1);  
	  
		/* Earlier loss recovery underway */  
		if (tcp_is_sackfrto(tp) && (tp->frto_counter ||   
			((1 << icsk->icsk_ca_state) & (TCPF_CA_Recovery | TCPF_CA_Loss))) &&  
			after(tp->high_seq, tp->snd_una)) {  
	  
			tp->frto_highmark = tp->high_seq;  
	  
		} else {  
			tp->frto_highmark = tp->snd_nxt;  
		}  
	  
		tcp_set_ca_state (sk, TCP_CA_Disorder); /* 设置拥塞状态*/  
		tp->high_seq = tp->snd_nxt;  
		tp->frto_counter = 1; /* 表示刚进入F-RTO状态！*/  
	}
```

#### F-RTO算法处理
F-RTO算法的处理过程主要发生在重传完超时数据包后。发送方在接收到ACK后，在处理ACK时会检查是否处于F-RTO处理阶段。如果是则会调用tcp_process_frto()进行F-RTO阶段的处理。

```
	static int tcp_ack (struct sock *sk, const struct sk_buff *skb, int flag)  
	{  
		....  
	  
		if (tp->frto_counter )  
			frto_cwnd = tcp_process_frto(sk, flag);  
	  
		....  
	}
```

#### 2.6.20的F-RTO
tcp_process_frto()用于判断RTO是否为虚假的，主要依据为RTO后的两个ACK。

```
	static void tcp_process_frto (struct sock *sk, u32 prior_snd_una)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		tcp_sync_left_out(tp);  
	  
		/* RTO was caused by loss, start retransmitting in 
		 * go-back-N slow start. 
		 * 包括两种情况： 
		  * （1）此ACK为dupack 
		 * （2）此ACK确认完整个窗口 
		  * 以上两种情况都表示有数据包丢失了，需要采用传统的方法。 
		  */  
		if (tp->snd_una == prior_snd_una ||   
			! before(tp->snd_una, tp->frto_highmark)) {  
	  
			tcp_enter_frto_loss(sk);  
			return;  
		}  
	  
		/* First ACK after RTO advances the window: allow two new  
		 * segments out. 
		 * frto_counter = 1表示收到第一个有效的ACK，则重新设置 
		 * 拥塞窗口，确保可以在F-RTO处理阶段在输出两个数据包， 
		 * 因为此时还没进入Loss状态，所以可以发送新数据包。 
		 */  
		if (tp->frto_counter == 1) {  
	  
			tp->snd_cwnd = tcp_packets_in_flight(tp) + 2;  
	  
		} else {  
	  
			/* Also the second ACK after RTO advances the window. 
			 * The RTO was likely spurious. Reduce cwnd and continue 
			 * in congestion avoidance. 
			 * 第二个ACK有效，则调整拥塞窗口，直接进入拥塞避免阶段， 
			  * 而不用重传数据包。 
			  * / 
			tp->snd_cwnd = min(tp->snd_cwnd, tp->snd_ssthresh); 
			tcp_moderate_cwnd(tp); 
		} 
	 
		/* F-RTO affects on two new ACKs following RTO. 
		 * At latest on third ACK the TCP behavior is back to normal. 
		 * 如果能连续收到两个确认了新数据的ACK，则说明RTO是虚假的，因此 
		  * 退出F-RTO。 
		  */  
		tp->frto_counter = (tp->frto_counter + 1) % 3;  
	}
```

如果确定RTO为虚假的，则调用tcp_enter_frto_loss()，进入RTO恢复阶段，开始慢启动。

```
	/* Enter Loss state after F-RTO was applied. Dupack arrived after RTO, which 
	 * indicates that we should follow the traditional RTO recovery, i.e. mark  
	 * erverything lost and do go-back-N retransmission. 
	 */  
	static void tcp_enter_frto_loss (struct sock *sk)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		struct sk_buff *skb;  
		int cnt = 0;  
	  
		/* 进入Loss状态后，清零SACK、lost、retrans_out等数据*/  
		tp->sacked_out = 0;  
		tp->lost_out = 0;  
		tp->fackets_out = 0;  
	  
		/* 遍历重传队列，重新标志LOST。对于那些在RTO发生后传输 
		 * 的数据不用标志为LOST。 
		 */  
		sk_stream_for_retrans_queue(skb, sk) {  
			cnt += tcp_skb_pcount(skb);  
			TCP_SKB_CB(skb)->sacked &= ~TCPCB_LOST;  
	  
			/* 对于那些没被SACK的数据包，需要把它标志为LOST。*/  
			if (! (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED)) {  
				/* Do not mark those segments lost that were forward 
				 * transmitted after RTO. 
				 */  
				 if (! after(TCP_SKB_CB(skb)->end_seq, tp->frto_highmark))  
				 {  
					TCP_SKB_CB(skb)->sacked |= TCP_LOST;  
					tp->lost_out += tcp_skb_pcount(skb);  
				 }  
	  
			} else { /* 对于那些已被sacked的数据包，则不用标志LOST。*/  
				tp->sacked_out += tcp_skb_pcount(skb);  
				tp->fackets_out = cnt;  
			}  
		}  
		tcp_syn_left_out(tp);  
	  
		tp->snd_cwnd = tp->frto_counter + tcp_packets_in_flight(tp) + 1;  
		tp->snd_cwnd_cnt = 0;  
		tp->snd_cwnd_stamp = tcp_time_stamp;  
		tp->undo_marker = 0; /* 不需要undo标志*/  
		tp->frto_counter = 0; /* 表示F-RTO结束了*/  
	  
		/* 更新乱序队列的最大值*/  
		tp->reordering = min_t(unsigned int, tp->reordering, sysctl_tcp_reordering);  
		tcp_set_ca_state(sk, TCP_CA_Loss); /* 进入loss状态*/  
		tp->high_seq = tp->frto_highmark; /*RTO时的最大序列号*/  
		TCP_ECN_queue_cwr(tp); /* 设置显示拥塞标志*/  
		clear_all_retrans_hints(tp);  
	}
```

#### 3.2.12的F-RTO
F-RTO spurious RTO detection algorithm (RFC4138)  
F-RTO affects during two new ACKs following RTO (well, almost, see inline
comments). State (ACK number) is kept in frto_counter. When ACK advances
window (but not to or beyond highest sequence sent before RTO) :  
On First ACK, send two new segments out.  
On second ACK, RTO was likely spurious. Do spurious response (response  
  algorithm is not part of the F-RTO detection algorithm given in RFC4138 but  
  can be selected separately).  

Otherwise (basically on duplicate ACK), RTO was (likely) caused by a loss and
TCP falls back to conventional RTO recovery. F-RTO allows overriding of Nagle,
this is done using frto_counter states 2 and 3, when a new data segment of any
size sent during F-RTO, state 2 is upgraded to 3. 

Rationale: if the RTO was suprious, new ACKs should arrive from the original
window even after we transmit two new data segments. 

SACK version:  
  on first step, wait until first cumulative ACK arrives, then move to the second
  step. In second step, the next ACK decides.

```
	static int tcp_process_frto(struct sock *sk, int flag)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		tcp_verify_left_out(tp);  
	   
		/* Duplicate the behavior from Loss state (fastretrans_alert) */  
		if (flag & FLAG_DATA_ACKED)  
			inet_csk(sk)->icsk_retransmits = 0; /*重传次数归零*/  
	   
		if ((flag & FLAG_NONHEAD_RETRANS_ACKED) ||  
			((tp->frto_counter >= 2) && (flag & FLAG_RETRANS_DATA_ACKED)))  
			tp->undo_marker = 0;  
	   
		/* 一个ACK确认完RTO时整个窗口，表示出现了丢包*/  
		if (! before(tp->snd_una, tp->frto_highmark)) {  
			tcp_enter_frto_loss(sk, (tp->frto_counter == 1 ? 2 : 3), flag) ;  
			return 1;  
		}  
	  
		/* Reno的处理方式 */  
		if (! tcp_is_sackfrto(tp)) {   
			/* RFC4138 shortcoming in step2; should also have case c): 
			 * ACK isn't duplicate nor advances window, e.g., opposite dir 
			 * data, winupdate 
			 */  
			if (! (flag & FLAG_ANY_PROGRESS) && (flag & FLAG_NOT_DUP))  
				return 1; /*不采取任何措施，忽略*/  
	  
			if (! (flag & FLAG_DATA_ACKED)) { /* 没有确认新的数据*/  
				tcp_enter_frto_loss(sk, (tp->frto_counter == 1 ? 0 : 3), flag);  
				return 1;  
			}  
	  
		} else { /* SACK的处理方式 */  
			/* Prevent sender of new data. 表示第一个ACK没有确认新数据， 
			 * 这个时候不允许发送新的数据，直接返回。 
			 */  
			if (! (flag & FLAG_DATA_ACKED) & (tp->frto_conter == 1) {  
				tp->snd_cwnd = min(tp->snd_cwnd, tcp_packets_in_flight(tp));  
				return 1;  
			}  
	  
			/* 当第二个ACK也没有确认新的数据时，判定RTO真实，退出F-RTO。*/  
			if ( (tp->frto_counter >= 2) &&   
				(! (flag & FLAG_FORWARD_PROGRESS) ||  
				((flag & FLAG_DATA_SACKED) && ! (flag & FLAG_ONLY_ORIG_SACKED))) {  
				/* RFC4138 shortcoming (see comment above) */  
	  
				if (! (flag & FLAG_FORWARD_PROGRESS) &&   
					(flag & FLAG_NOT_DUP);  
					return 1;  
	   
				tcp_enter_frto_loss(sk, 3, flag);  
				return 1;  
			}  
		}  
	  
		if (tp->frto_counter == 1) {  
			/* tcp_may_send_now needs to see updated state */  
			tp->snd_cwnd = tcp_packets_in_flight(tp) + 2;  
			tp->frto_counter = 2;  
			  
			if (! tcp_may_send_now(sk))  
				tcp_enter_frto_loss(sk, 2, flag);  
			return 1;  
	  
		} else {  
			switch (sysctl_tcp_frto_response) {  
			case 2: /* 比较激进的，恢复到RTO前的窗口和阈值*/  
				tcp_undo_spur_to_response(sk, flag);  
				break;  
	  
			case 1: /* 非常保守，阈值减小B，可窗口一再减小，为B/2 */  
				tcp_conservative_spur_to_response(sk);  
				break;  
	  
			default:  
				/* 保守*/  
				tcp_ratehalving_spur_to_response(sk);  
				break;  
			}  
	  
			tp->frto_counter = 0; /*F-RTO算法结束标志*/  
			tp->undo_marker = 0; /*清零undo标志*/  
			NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPSPURIOUSRTOS);  
		}  
		return 0;   
	}  
	  
	#define FLAG_DATA_ACKED 0x04 /* This ACK acknowledged new data. */  
	#define FLAG_NONHEAD_RETRANS_ACKED 0x1000 /* Non-head rexmit data was ACKed. */  
	#define FLAG_RETRANS_DATA_ACKED 0x08 /* some of which was retransmitted.*/  
	  
	#define FLAG_ACKED (FLAG_DATA_ACKED | FLAG_SYN_ACKED)  
	#define FLAG_FORWARD_PROGRESS (FLAG_ACKED | FLAG_DATA_SACKED)  
	#define FLAG_ANY_PROGRESS (FLAG_RORWARD_PROGRESS | FLAG_SND_UNA_ADVANCED)  
	   
	#define FLAG_NOT_DUP (FLAG_DATA | FLAG_WIN_UPDATE | FLAG_ACKED)
```

#### tcp_frto_response选项

tcp_frto_response表示TCP在检测到虚假的RTO后，采用什么函数来进行阈值和拥塞窗口的调整，它有三种取值：

##### （1）值为2
表示使用tcp_undo_spur_to_response()，这是一种比较激进的处理方法，它把阈值和拥塞窗口都恢复到RTO前的值。

##### （2）值为1
表示使用tcp_conservative_spur_to_response()，这是一种很保守的处理方法。  
假设减小因子为B，RTO前的窗口为C，那么一般情况下（因为阈值调整算法不同）  
此后ssthresh=（1 - B）C，cwnd = （1 -B ）（1- B）C

##### （3）值为0或其它（默认为0）
表示使用默认的tcp_ratehalving_spur_to_response()，也是一种保守的处理方法。

```
	static void tcp_undo_spur_to_response (struct sock *sk, int flag)  
	{  
		/* 如果有显示拥塞标志，则进入CWR状态，最终阈值不变，窗口减半*/  
		if (flag & FLAG_ECE)  
			tcp_ratehalving_spur_to_response(sk);  
		else  
		/* 撤销阈值调整，撤销窗口调整，恢复RTO前的状态*/  
			tcp_undo_cwr(sk, true);  
	}  
	  
	/* A conservative spurious RTO response algorithm: reduce cwnd 
	 * using rate halving and continue in congestion_avoidance. 
	 */  
	static void tcp_ratehalving_spur_to_response(struct sock *sk)  
	{  
		tcp_enter_cwr(sk, 0);  
	}  
	  
	/* A very conservative spurious RTO response algorithm: reduce cwnd 
	 * and continue in congestion avoidance. 
	 */  
	static void tcp_conservative_spur_to_response(struct tcp_sock *tp)  
	{  
		tp->snd_cwnd = min(tp->snd_cwnd, tp->snd_ssthresh);  
		tp->snd_cwnd_cnt = 0;  
		tp->bytes_acked = 0;  
		/* 竟然又设置了显示拥塞标志，那窗口就还要减小到阈值的（1-B）！ 
		 * 果然是非常保守。 
		 */  
		TCP_ECN_queue_cwr(tp);   
		tcp_moderate_cwnd(tp);  
	}
```

如果判断RTO是真实的，就调用tcp_enter_frto_loss()来处理。

```
	/* Enter Loss state after F-RTO was applied. Dupack arrived after RTO, 
	 * which indicates that we should follow the tradditional RTO recovery, 
	 * i.e. mark everything lost and do go-back-N retransmission. 
	 */  
	static void tcp_enter_frto_loss(struct sock *sk, int allowed_segments, int flag)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		struct sk_buff *skb;  
	  
		tp->lost_out = 0;  
		tp->retrans_out = 0;  
	  
		if (tcp_is_reno(tp))  
			tcp_reset_reno_sack(tp);  
	  
		tcp_for_write_queue(skb, sk) {  
			if (skb == tcp_send_head(sk))  
				break;  
	  
			TCP_SKB_CB(skb)->sacked &= ~TCPCB_LOST;  
			/*  
			 * Count the retransmission made on RTO correctly (only when waiting for 
			 * the first ACK and did not get it. 
			 */  
			if ((tp->frto_counter == 1) && !(flag & FLAG_DATA_ACKED)) {  
				/* For some reason this R-bit might get cleared ? */  
				if (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_RETRANS)  
					tp->retrans_out += tcp_skb_pcount(skb);  
	  
				/* enter this if branch just for the first segment */  
				flag |= FLAG_DATA_ACKED;  
			} else {  
	  
				if (TCP_SKB_CB(skb)->sacked & TCPCB_RETRANS)  
					tp->undo_marker = 0;  
				TCP_SKB_CB(skb)->sacked &= ~TCPCB_SACKED_RETRANS;  
			}  
	  
			/* Marking forward transmissions that were made after RTO lost can 
			* cause unnecessary retransmissions in some scenarios, 
			* SACK blocks will mitigate that in some but not in all cases. 
			* We used to not mark them but it was casuing break-ups with 
			* receivers that do only in-order receival. 
			*  
			* TODO: we could detect presence of such receiver and select different 
			* behavior per flow. 
			*/  
		   if (! (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED)) {  
			  TCP_SKB_CB(skb)->sacked |= TCPCB_LOST;  
			   tp->lost_out += tcp_skb_pcount(skb);  
			   tp->retransmit_high = TCP_SKB_CB(skb)->end_seq;  
		   }  
		}  
		tcp_verify_left_out(tp);  
	  
		/* allowed_segments应该不大于3*/  
		tp->snd_cwnd = tcp_packets_in_flight(tp) + allowed_segments;  
		tp->snd_cwnd_cnt = 0;  
		tp->snd_cwnd_stamp = tcp_time_stamp;  
		tp->frto_counter = 0; /* F-RTO结束了*/  
		tp->bytes_acked = 0;  
	  
		/* 更新乱序队列的最大长度*/  
		tp->reordering = min_t(unsigned int, tp->reordering,  
							sysctl_tcp_reordering);  
	  
		tcp_set_ca_state(sk, TCP_CA_Loss); /*设置成Loss状态*/  
		tp->high_seq = tp->snd_nxt;  
		TCP_ECN_queue_cwr(tp); /*设置显式拥塞标志*/  
		tcp_clear_all_retrans_hints(tp);  
	}
```

#### 总结
现在内核（3.2.12）是默认使用F-RTO算法的。  
其中tcp_frto默认为2，tcp_frto_response默认为0。


