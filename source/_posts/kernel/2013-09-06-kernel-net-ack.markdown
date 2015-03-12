---
layout: post
title: "内核tcp的ack的处理tcp_ack"
date: 2013-09-06 15:40:00 +0800
comments: false
categories:
- 2013
- 2013~09
- kernel
- kernel~net
tags:
---
http://simohayha.iteye.com/blog/572505

我们来看tcp输入对于ack，段的处理。

* 先是ack的处理，在内核中，处理ack段是通过tcp_ack来进行的。  
这个函数主要功能是：  
1. update重传队列，并基于sack来设置skb的相关buf。  
2. update发送窗口。  
3. 基于sack的信息或者重复ack来决定是否进入拥塞模式。  
在看之前我们要知道tcp是累积确认的。为了解决带来的缺点，我们才需要sack的。

  然后我们来看几个很重要的数据结构，先是tcp_skb_cb，它其实就是表示skb中所保存的tcp的控制信息。而他是保存在skb的cb中的(这个域可以看我前面的blog）。所以这里我们经常会用TCP_SKB_CB来存取这个结构。
```
	#define TCP_SKB_CB(__skb)   ((struct tcp_skb_cb *)&((__skb)->cb[0]))
```
这里还有一个inet_skb_parm，这个结构保存了ipoption的一些信息。
```
	struct inet_skb_parm
	{
		struct ip_options   opt;        /* Compiled IP options      */
		unsigned char       flags;

		#define IPSKB_FORWARDED			1
		#define IPSKB_XFRM_TUNNEL_SIZE	2
		#define IPSKB_XFRM_TRANSFORMED	4
		#define IPSKB_FRAG_COMPLETE		8
		#define IPSKB_REROUTED			16
	};
```
然后来看tcp_skb_cb：
```
	struct tcp_skb_cb {
		union {
			struct inet_skb_parm    h4;
	#if defined(CONFIG_IPV6) || defined (CONFIG_IPV6_MODULE)
			struct inet6_skb_parm   h6;
	#endif
		} header;   /* For incoming frames      */
	//这个表示当前tcp包的序列号
		__u32       seq;
	//这个表示结束序列号，也就是SEQ + FIN + SYN + datalen。
		__u32       end_seq;
	//主要用来计算rtt
		__u32       when;
	//tcp头的flag（比如syn，fin等)，它能取的值，我们下面会介绍。
		__u8        flags;

	//SACK/FACK的状态flag或者是sack option的偏移(相对于tcp头的)。我们下面会介绍
		__u8        sacked;
	//ack的序列号。
		__u32       ack_seq;
	};
```
下面就是flags所能取的值，可以看到也就是tcp头的控制位。
```
	#define TCPCB_FLAG_FIN      0x01
	#define TCPCB_FLAG_SYN      0x02
	#define TCPCB_FLAG_RST      0x04
	#define TCPCB_FLAG_PSH      0x08
	#define TCPCB_FLAG_ACK      0x10
	#define TCPCB_FLAG_URG      0x20
	#define TCPCB_FLAG_ECE      0x40
	#define TCPCB_FLAG_CWR      0x80
```
然后是sack/fack的状态标记：
```
	//有这个域说明当前的tcpcb是被sack块确认的。
	#define TCPCB_SACKED_ACKED  0x01
	//表示重传的帧
	#define TCPCB_SACKED_RETRANS    0x02
	//丢失
	#define TCPCB_LOST      0x04
	#define TCPCB_TAGBITS       0x07
	//重传的帧。
	#define TCPCB_EVER_RETRANS  0x80
	#define TCPCB_RETRANS       (TCPCB_SACKED_RETRANS|TCPCB_EVER_RETRANS)
```
  这里要注意，当我们接收到正确的SACK后，这个域就会被初始化为sack所在的相对偏移(也就是相对于tcp头的偏移值，这样我们就能很容易得到sack option的位置).
然后是tcp_sock，这个结构保存了我们整个tcp层所需要得所有必要的信息（也就是从sock中提取出来).我们分两个部分来看这个结构，这里只看我们关注的两部分，第一部分是窗口相关的一些域。第二部分是拥塞控制的一些相关域。
先来看窗口相关的：
```
	//我们期待从另一台设备接收的下一个数据字节的序列号。
	u32 rcv_nxt;
	//还没有被读取的数据的序列号。
	u32 copied_seq;
	//当最后一次窗口update被发送之前我们的rcv_nxt.
	u32 rcv_wup;
	//将要发送给另一台设备的下一个数据字节的序列号。
	u32 snd_nxt;
	//已经发送但尚未被确认的第一个数据字节的序列号。
	u32 snd_una;
	//
	u32 snd_sml;
	//最后一次接收到ack的时间戳，主要用于keepalive
	u32 rcv_tstamp;
	//最后一次发送数据包的时间戳。
	u32 lsndtime;
	//发送窗口长度
	u32 snd_wnd;
	//接收窗口长度。
	u32 rcv_wnd
	//发送未确认的数据包的个数（或者字节数？）
	u32 packets_out;
	//重传的数据包的个数
	u32 retrans_out;
```
然后是拥塞部分，看这里之前还是需要取熟悉一下tcp拥塞控制的相关概念。
```
	//慢开始的阀值，也就是超过这个我们就要进入拥塞避免的阶段
	u32  snd_ssthresh;
	//发送的拥塞窗口
	u32 snd_cwnd;
	//这个应该是拥塞状态下所发松的数据字节数
	u32 snd_cwnd_cnt;
	//这里也就是cwnd的最大值
	u32 snd_cwnd_clamp;
	//这两个值不太理解什么意思。
	u32 snd_cwnd_used;
	u32 snd_cwnd_stamp;

	//接收窗口打消
	u32 rcv_wnd;
	//tcp的发送buf数据的尾部序列号。
	u32 write_seq;
	//最后一次push的数据的序列号
	u32 pushed_seq;
	//丢失的数据包字节数
	u32 lost_out;
	//sack的数据包的字节数
	u32 sacked_out;
	//fack处理的数据包的字节数
	u32 fackets_out;
	u32 tso_deferred;
	//计数
	u32 bytes_acked;
```
分析完相关的数据结构我们来看函数的实现。  
来看tcp_ack的代码,函数比较大，因此我们分段来看，先来看一开始的一些校验部分。  
这里有一个tcp_abc也就是proc下面的可以设置的东西，这个主要是看要不要每个ack都要进行拥塞控制。  

> Controls Appropriate Byte Count defined in RFC3465. If set to 0 then does congestion avoid once per ACK. 1 is conservative value, and 2 is more aggressive. The default value is 1.

```
	struct inet_connection_sock *icsk = inet_csk(sk);
	struct tcp_sock *tp = tcp_sk(sk);
	//等待ack，也就是发送未确认的序列号。
	u32 prior_snd_una = tp->snd_una;
	u32 ack_seq = TCP_SKB_CB(skb)->seq;
	//得到ack的序列号。
	u32 ack = TCP_SKB_CB(skb)->ack_seq;
	u32 prior_in_flight;
	u32 prior_fackets;
	int prior_packets;
	int frto_cwnd = 0;

	//如果ack的序列号小于发送未确认的，也就是说可能这个ack只是重传老的ack，因此我们忽略它。
	if (before(ack, prior_snd_una))
		goto old_ack;

	//如果ack大于snd_nxt,也就是它确认了我们还没发送的数据段，因此我们discard这个段。
	if (after(ack, tp->snd_nxt))
		goto invalid_ack;
	//如果ack大于发送未确认，则设置flag
	if (after(ack, prior_snd_una))
		flag |= FLAG_SND_UNA_ADVANCED;

	//是否设置tcp_abc，有设置的话，说明我们不需要每个ack都要拥塞避免，因此我们需要计算已经ack的字节数。
	if (sysctl_tcp_abc) {
		if (icsk->icsk_ca_state < TCP_CA_CWR)
			tp->bytes_acked += ack - prior_snd_una;
		else if (icsk->icsk_ca_state == TCP_CA_Loss)
			 tp->bytes_acked += min(ack - prior_snd_una,qtp->mss_cache);
	}

	//得到fack的数据包的字节数
	prior_fackets = tp->fackets_out;
	//计算还在传输的数据段的字节数,下面会详细分析这个函数。
	prior_in_flight = tcp_packets_in_flight(tp);
```
packets_out这个表示已经发送还没有ack的数据段的字节数(这个值不会重复加的，比如重传的话不会增加这个值）。  
sakced_out :sack了的字节数。  
lost_out:丢失了的字节数。  
retrans_out:重传的字节数。  
现在我们就对这个函数的返回值很清楚了，它也就是包含了还没有到达对方的数据段的字节数。
```
	static inline unsigned int tcp_left_out(const struct tcp_sock *tp)
	{
		return tp->sacked_out + tp->lost_out;
	}

	static inline unsigned int tcp_packets_in_flight(const struct tcp_sock *tp)
	{
		return tp->packets_out - tcp_left_out(tp) + tp->retrans_out;
	}
```
接下来这一段主要是通过判断flag(slow还是fast)来进行一些窗口的操作。有关slow_path和fast_path的区别，可以看我前面的blog。  
fast_path的话很简单，我们就更新相关的域以及snd_wl1(这个域主要是用于update窗口的时候).它这里会被赋值为我们这次的数据包的序列号。然后进行拥塞控制的操作。  
snd_wl1是只要我们需要更新发送窗口的话，这个值是都会被更新的。  
slow_path的话，我们就需要判断要不要update窗口的大小了。以及是否要处理sack等。  
在看下面的代码之前，我们先来看传递进tcp_ack这个函数中的第三个参数flag，这里我们在函数中也还会修改这个值，这个flag也就是当前的skb的类型信息。看了注释后就清楚了。可疑看到好几个都是ack的类型。
```
	//这个说明当前的输入帧包含有数据。
	#define FLAG_DATA       0x01
	//这个说明当前的ack是一个窗口更新的ack
	#define FLAG_WIN_UPDATE     0x02
	//这个ack确认了一些数据
	#define FLAG_DATA_ACKED     0x04
	//这个表示ack确认了一些我们重传的段。
	#define FLAG_RETRANS_DATA_ACKED 0x08
	//这个表示这个ack是对syn的回复。
	#define FLAG_SYN_ACKED      0x10
	//新的sack
	#define FLAG_DATA_SACKED    0x20
	//ack中包含ECE
	#define FLAG_ECE        0x40
	//sack检测到了数据丢失。
	#define FLAG_DATA_LOST      0x80
	//当更新窗口的时候不跳过RFC的检测。
	#define FLAG_SLOWPATH       0x100

	#define FLAG_ONLY_ORIG_SACKED   0x200
	//snd_una被改变了。也就是更新了。
	#define FLAG_SND_UNA_ADVANCED   0x400
	//包含D-sack
	#define FLAG_DSACKING_ACK   0x800
	//这个不太理解什么意思。
	#define FLAG_NONHEAD_RETRANS_ACKED  0x1000
	//
	#define FLAG_SACK_RENEGING  0x2000

	//下面也就是一些组合。
	#define FLAG_ACKED  (FLAG_DATA_ACKED|FLAG_SYN_ACKED)
	#define FLAG_NOT_DUP (FLAG_DATA|FLAG_WIN_UPDATE|FLAG_ACKED)
	#define FLAG_CA_ALERT       (FLAG_DATA_SACKED|FLAG_ECE)
	#define FLAG_FORWARD_PROGRESS   (FLAG_ACKED|FLAG_DATA_SACKED)
	#define FLAG_ANY_PROGRESS   (FLAG_FORWARD_PROGRESS|FLAG_SND_UNA_ADVANCED)
```
然后我们来看代码，下面的代码会设置flag，也就是用上面的宏。  
这里有一个很大的不同就是slow_path中，我们需要update窗口的大小，而在fast模式中，我们不需要，这个详细去看我前面的blog介绍的fast和slow的区别。fast就是最理想的情况，因此我们不需要update窗口。
```
	//如果不是slowpath并且ack确实是正确的序列号(必须大于snd_una).
		if (!(flag & FLAG_SLOWPATH) && after(ack, prior_snd_una)) {
	//更新snd_wl1域为ack_seq;
			tcp_update_wl(tp, ack_seq);
	//snd_una更新为ack也就是确认的序列号
			tp->snd_una = ack;
	//更新flag域。
			flag |= FLAG_WIN_UPDATE;
	//进入拥塞的操作。
			tcp_ca_event(sk, CA_EVENT_FAST_ACK);
	................................
		} else {
	//这个判断主要是为了判断是否输入帧包含数据。也就是ack还包含了数据，如果有的话，我们设置标记然后后面会处理。
			if (ack_seq != TCP_SKB_CB(skb)->end_seq)
				flag |= FLAG_DATA;
			else
	.....................................

	//然后进入更新窗口的操作。
			flag |= tcp_ack_update_window(sk, skb, ack, ack_seq);
	//然后判断是否有sack段，有的话，我们进入sack段的处理。
			if (TCP_SKB_CB(skb)->sacked)
				flag |= tcp_sacktag_write_queue(sk, skb, prior_snd_una);
	//判断是否有ecn标记，如果有的话，设置ecn标记。
			if (TCP_ECN_rcv_ecn_echo(tp, tcp_hdr(skb)))
				flag |= FLAG_ECE;
	//进入拥塞的处理。
			tcp_ca_event(sk, CA_EVENT_SLOW_ACK);
		}
```
接下来这段主要工作是：  
1 清理重传队列中的已经ack的段。  
2 处理F-RTO。  
3 判断是否是零窗口探测的回复ack。  
4 检测是否要进入拥塞处理。  
```
	sk->sk_err_soft = 0;
	icsk->icsk_probes_out = 0;
	tp->rcv_tstamp = tcp_time_stamp;
	//如果发送并且没有ack的数据段的值为0,则说明这个有可能是0窗口探测的回复，因此我们进入no_queue的处理，这个我们紧接着会详细介绍。
	prior_packets = tp->packets_out;
	if (!prior_packets)
		goto no_queue;
	//清理重传队列中的已经ack的数据段。
	flag |= tcp_clean_rtx_queue(sk, prior_fackets, prior_snd_una);

	//处理F-RTO
	if (tp->frto_counter)
		frto_cwnd = tcp_process_frto(sk, flag);

	if (before(tp->frto_highmark, tp->snd_una))
		tp->frto_highmark = 0;
	//判断ack是否是可疑的。它主要是检测我们是否进入拥塞状态，或者已经处于拥塞状态。
	if (tcp_ack_is_dubious(sk, flag)) {
	//检测flag以及是否需要update拥塞窗口的大小。
	if ((flag & FLAG_DATA_ACKED) && !frto_cwnd &&
		tcp_may_raise_cwnd(sk, flag))
	//如果都为真，则更新拥塞窗口。
		tcp_cong_avoid(sk, ack, prior_in_flight);
	//这里进入拥塞状态的处理(这个函数是一个非常关键的函数,等到后面详细分析拥塞的时候，会分析到)。
		tcp_fastretrans_alert(sk, prior_packets - tp->packets_out,flag);
	} else {
	//这里可以看到和上面相比，没有tcp_may_raise_cwnd这个，我们紧接着就会分析到。
		if ((flag & FLAG_DATA_ACKED) && !frto_cwnd)
			tcp_cong_avoid(sk, ack, prior_in_flight);
	}
	//是否更新neigh子系统。
	if ((flag & FLAG_FORWARD_PROGRESS) || !(flag & FLAG_NOT_DUP))
		dst_confirm(sk->sk_dst_cache);

	return 1;

	no_queue:
	//这里判断发送缓冲区是否为空，如果不为空，则我们进入判断需要重启keepalive定时器还是关闭定时器
		if (tcp_send_head(sk))
			tcp_ack_probe(sk);
		return 1;
```
ok，，接着来看上面略过的几个函数，先来看tcp_ack_is_dubious，这里的条件我们一个个来看  
1 说明flag不能是 FLAG_NOT_DUP的， FLAG_NOT_DUP表示我们的ack不是重复的。  
2 是flag是CA_ALERT,它的意思是我们是否在我们进入拥塞状态时被alert。  
3 拥塞状态不能为TCP_CA_OPEN不为这个，就说明我们已经进入了拥塞状态。  
可以看下面这几个宏的定义，就比较清楚了。
```
	#define FLAG_ACKED  (FLAG_DATA_ACKED|FLAG_SYN_ACKED)
	#define FLAG_NOT_DUP (FLAG_DATA|FLAG_WIN_UPDATE|FLAG_ACKED)

	//收到sack则说明可能有的段丢失了。而ECE则是路由器提示我们有拥塞了。我们必须处理。
	#define FLAG_CA_ALERT       (FLAG_DATA_SACKED|FLAG_ECE)
```
上面的任意一个为真。就说明ack是可疑的。这里起始也可以说我们就必须进入拥塞的处理了(tcp_fastretrans_alert)
```
	static inline int tcp_ack_is_dubious(const struct sock *sk, const int flag)
	{
		return (!(flag & FLAG_NOT_DUP) || (flag & FLAG_CA_ALERT) ||inet_csk(sk)->icsk_ca_state != TCP_CA_Open);
	}
```
然后是 tcp_may_raise_cwnd，这个函数用来判断是否需要增大拥塞窗口。  
1 不能有ECE flag或者发送的拥塞窗口不能大于slow start的阀值。  
3 拥塞状态为RECO或者CWR.  
```
	static inline int tcp_may_raise_cwnd(const struct sock *sk, const int flag)
	{
		const struct tcp_sock *tp = tcp_sk(sk);
		return (!(flag & FLAG_ECE) || tp->snd_cwnd < tp->snd_ssthresh) &&!((1 << inet_csk(sk)->icsk_ca_state) & (TCPF_CA_Recovery | TCPF_CA_CWR));
	}
```
在看tcp_ack_update_window函数之前，我们先来看tcp_may_update_window，这个函数用来判断是否需要更新发送窗口。  
1 新的数据已经被ack了。  
2 当前的数据包的序列号大于当窗口更新的时候那个数据包的序列号。  
3 当前的数据包的序列号等于窗口更新时的序列号并且新的窗口大小大于当前的发送窗口大小。这个说明对端可能已经增加了窗口的大小
```
	static inline int tcp_may_update_window(const struct tcp_sock *tp,const u32 ack, const u32 ack_seq,const u32 nwin)
	{
		return (after(ack, tp->snd_una) ||
			after(ack_seq, tp->snd_wl1) ||
			(ack_seq == tp->snd_wl1 && nwin > tp->snd_wnd));
	}
```
然后是tcp_ack_update_window函数，这个主要用来更新发送窗口的大小。
```
	static int tcp_ack_update_window(struct sock *sk, struct sk_buff *skb, u32 ack, u32 ack_seq)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		int flag = 0;
		//得到窗口的大小。
		u32 nwin = ntohs(tcp_hdr(skb)->window);

		if (likely(!tcp_hdr(skb)->syn))
			nwin <<= tp->rx_opt.snd_wscale;

		//判断是否需要update窗口。
		if (tcp_may_update_window(tp, ack, ack_seq, nwin)) {
			flag |= FLAG_WIN_UPDATE;
		//更新snd_wl1
			tcp_update_wl(tp, ack_seq);
		//如果不等于，则说明我们需要更新窗口。
			if (tp->snd_wnd != nwin) {
				tp->snd_wnd = nwin;
		...................................
			}
		}

		tp->snd_una = ack;
		return flag;
	}
```
然后是tcp_cong_avoid函数，这个函数用来实现慢开始和快重传的拥塞算法。
```
	static void tcp_cong_avoid(struct sock *sk, u32 ack, u32 in_flight)
	{
		const struct inet_connection_sock *icsk = inet_csk(sk);
		icsk->icsk_ca_ops->cong_avoid(sk, ack, in_flight);
		tcp_sk(sk)->snd_cwnd_stamp = tcp_time_stamp;
	}
```
可以看到它主要是调用cong_avoid回调函数，而这个函数被初始化为tcp_reno_cong_avoid，我们来看这个函数，在看这个函数之前我们要知道一些慢开始和快回复的概念。这些东西随便介绍tcp的书上都有介绍的。
```
	void tcp_reno_cong_avoid(struct sock *sk, u32 ack, u32 in_flight)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		//是否已经到达拥塞窗口的限制。
		if (!tcp_is_cwnd_limited(sk, in_flight))
			return;
		//如果拥塞窗口还没有到达慢开始的阈值，我们就进入慢开始处理。
		if (tp->snd_cwnd <= tp->snd_ssthresh)
			tcp_slow_start(tp);

		//否则我们就要进入拥塞避免阶段。
		else if (sysctl_tcp_abc) {
		//RFC3465,只有当当前的拥塞窗口的所有段都被ack了，窗口才被允许增加。
		if (tp->bytes_acked >= tp->snd_cwnd*tp->mss_cache) {
			tp->bytes_acked -= tp->snd_cwnd*tp->mss_cache;
				if (tp->snd_cwnd < tp->snd_cwnd_clamp)
					tp->snd_cwnd++;
			}
		} else {
		//和上面处理方式类似。
			tcp_cong_avoid_ai(tp, tp->snd_cwnd);
		}
	}
```
最后我们来看tcp_clean_rtx_queue函数，这个函数主要用于清理发送队列中已经被ack的数据段。函数比较大，我们来分段看。  
这里有使用karn算法，也就是如果重传的段，则计算rto的话，不采样这次的值。  
还有就是要判断是syn的ack回复，还是数据的ack回复。以及sack的判断。  
首先是遍历部分：
```
	while ((skb = tcp_write_queue_head(sk)) && skb != tcp_send_head(sk)) {
		struct tcp_skb_cb *scb = TCP_SKB_CB(skb);
		u32 acked_pcount;
		u8 sacked = scb->sacked;
		//这个说明当前的数据已经在发送未确认的段里面了。
		if (after(scb->end_seq, tp->snd_una)) {
			//这边不是很懂。
			if (tcp_skb_pcount(skb) == 1 ||
				!after(tp->snd_una, scb->seq))
				break;
			acked_pcount = tcp_tso_acked(sk, skb);
			if (!acked_pcount)
				break;
			fully_acked = 0;
		} else {
			acked_pcount = tcp_skb_pcount(skb);
		}
		//如果sack的状态有被设置重传，则我们会使用karn算法。
		if (sacked & TCPCB_RETRANS) {
			//如果标记为sack了重传段，则更新重传的计数。
			if (sacked & TCPCB_SACKED_RETRANS)
				tp->retrans_out -= acked_pcount;
			flag |= FLAG_RETRANS_DATA_ACKED;

			//都为-1，也就是后面计算rtt，不会采样这次值。
			ca_seq_rtt = -1;
			seq_rtt = -1;
				if ((flag & FLAG_DATA_ACKED) || (acked_pcount > 1))
			flag |= FLAG_NONHEAD_RETRANS_ACKED;
		} else {
			//否则根据时间戳得到对应的rtt
			ca_seq_rtt = now - scb->when;
			last_ackt = skb->tstamp;
			if (seq_rtt < 0) {
				seq_rtt = ca_seq_rtt;
			}
			if (!(sacked & TCPCB_SACKED_ACKED))
				reord = min(pkts_acked, reord);
		}
		//如果有sack的数据包被ack确认了，则我们需要减小sack的计数
		if (sacked & TCPCB_SACKED_ACKED)
			tp->sacked_out -= acked_pcount;
		if (sacked & TCPCB_LOST)
			tp->lost_out -= acked_pcount;
		//总得发送为ack的数据字节计数更新。
		tp->packets_out -= acked_pcount;
		pkts_acked += acked_pcount;
		//判断是否为syn的ack。
		if (!(scb->flags & TCPCB_FLAG_SYN)) {
			flag |= FLAG_DATA_ACKED;
		} else {
			//如果是设置标记
			flag |= FLAG_SYN_ACKED;
			tp->retrans_stamp = 0;
		}

		if (!fully_acked)
			break;
		//从写buf，unlink掉。
		tcp_unlink_write_queue(skb, sk);
		//释放内存。
		sk_wmem_free_skb(sk, skb);
		tp->scoreboard_skb_hint = NULL;
		if (skb == tp->retransmit_skb_hint)
			tp->retransmit_skb_hint = NULL;
		if (skb == tp->lost_skb_hint)
			tp->lost_skb_hint = NULL;
	}
```
剩下的部分就是计算rtt的部分，这里就不介绍了。

