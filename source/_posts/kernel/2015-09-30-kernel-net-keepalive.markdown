---
layout: post
title: "TCP的定时器系列 — 保活定时器"
date: 2015-09-30 15:32:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/44177475

主要内容：保活定时器的实现，TCP_USER_TIMEOUT选项的实现。  
内核版本：3.15.2  

#### 原理

HTTP有Keepalive功能，TCP也有Keepalive功能，虽然都叫Keepalive，但是它们的目的却是不一样的。为了说明这一点，先来看下长连接和短连接的定义。

连接的“长短”是什么？  
短连接：建立一条连接，传输一个请求，马上关闭连接。  
长连接：建立一条连接，传输一个请求，过会儿，又传输若干个请求，最后再关闭连接。

长连接的好处是显而易见的，多个请求可以复用一条连接，省去连接建立和释放的时间开销和系统调用，但也意味着服务器的一部分资源会被长时间占用着。

HTTP的Keepalive，顾名思义，目的在于延长连接的时间，以便在同一条连接中传输多个HTTP请求。

HTTP服务器一般会提供Keepalive Timeout参数，用来决定连接保持多久，什么时候关闭连接。

当连接使用了Keepalive功能时，对于客户端发送过来的一个请求，服务器端会发送一个响应，然后开始计时，如果经过Timeout时间后，客户端没有再发送请求过来，服务器端就把连接关了，不再保持连接了。

TCP的Keepalive，是挂羊头卖狗肉的，目的在于看看对方有没有发生异常，如果有异常就及时关闭连接。

当传输双方不主动关闭连接时，就算双方没有交换任何数据，连接也是一直有效的。

如果这个时候对端、中间网络出现异常而导致连接不可用，本端如何得知这一信息呢？

答案就是保活定时器。它每隔一段时间会超时，超时后会检查连接是否空闲太久了，如果空闲的时间超过了设置时间，就会发送探测报文。然后通过对端是否响应、响应是否符合预期，来判断对端是否正常，如果不正常，就主动关闭连接，而不用等待HTTP层的关闭了。

当服务器发送探测报文时，客户端可能处于4种不同的情况：仍然正常运行、已经崩溃、已经崩溃并重启了、由于中间链路问题不可达。在不同的情况下，服务器会得到不一样的反馈。

(1) 客户主机依然正常运行，并且从服务器端可达

客户端的TCP响应正常，从而服务器端知道对方是正常的。保活定时器会在两小时以后继续触发。


(2) 客户主机已经崩溃，并且关闭或者正在重新启动

客户端的TCP没有响应，服务器没有收到对探测包的响应，此后每隔75s发送探测报文，一共发送9次。

socket函数会返回-1，errno设置为ETIMEDOUT，表示连接超时。


(3) 客户主机已经崩溃，并且重新启动了

客户端的TCP发送RST，服务器端收到后关闭此连接。

socket函数会返回-1，errno设置为ECONNRESET，表示连接被对端复位了。


(4) 客户主机依然正常运行，但是从服务器不可达

双方的反应和第二种是一样的，因为服务器不能区分对端异常与中间链路异常。

socket函数会返回-1，errno设置为EHOSTUNREACH，表示对端不可达。

 
#### 选项

内核默认并不使用TCP Keepalive功能，除非用户设置了SO_KEEPALIVE选项。

有两种方式可以自行调整保活定时器的参数：一种是修改TCP参数，一种是使用TCP层选项。

(1) TCP参数

tcp_keepalive_time

最后一次数据交换到TCP发送第一个保活探测报文的时间，即允许连接空闲的时间，默认为7200s。

tcp_keepalive_intvl

保活探测报文的重传时间，默认为75s。

tcp_keepalive_probes

保活探测报文的发送次数，默认为9次。

 

Q：一次完整的保活探测需要花费多长时间？

A：tcp_keepalive_time + tcp_keepalive_intvl * tcp_keepalive_probes，默认值为7875s。如果觉得两个多小时太长了，可以自行调整上述参数。


(2) TCP层选项

TCP_KEEPIDLE：含义同tcp_keepalive_time。

TCP_KEEPINTVL：含义同tcp_keepalive_intvl。

TCP_KEEPCNT：含义同tcp_keepalive_probes。

 

Q：既然有了TCP参数可供调整，为什么还增加了上述的TCP层选项？

A：TCP参数是面向本机的所有TCP连接，一旦调整了，对所有的连接都有效。而TCP层选项是面向一条连接的，一旦调整了，只对本条连接有效。

 
#### 激活

在连接建立后，可以通过设置SO_KEEPALIVE选项，来激活保活定时器。

```
	int keepalive = 1;
	setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &keepalive, sizeof(keepalive));
```

```
	int sock_setsockopt(struct socket *sock, int level, int optname, char __user *optval,   
		unsigned int optlen)  
	{  
		...  
		case SO_KEEPALIVE:  
	#ifdef CONFIG_INET  
			if (sk->sk_protocol == IPPROTO_TCP && sk->sk_type == SOCK_STREAM)  
				tcp_set_keepalive(sk, valbool); /* 激活或删除保活定时器 */  
	#endif  
			sock_valbool_flag(sk, SOCK_KEEPOPEN, valbool); /* 设置或取消SOCK_KEEPOPEN标志位 */  
			break;  
		...  
	}  
	  
	static inline void sock_valbool_flag (struct sock *sk, int bit, int valbool)  
	{  
		if (valbool)  
			sock_set_flag(sk, bit);  
		else  
			sock_reset_flag(sk, bit);  
	}  
```

```
	void tcp_set_keepalive(struct sock *sk, int val)  
	{  
		/* 不在以下两个状态设置保活定时器： 
		 * TCP_CLOSE：sk_timer用作FIN_WAIT2定时器 
		 * TCP_LISTEN：sk_timer用作SYNACK重传定时器 
		 */  
		if ((1 << sk->sk_state) & (TCPF_CLOSE | TCPF_LISTEN))  
			return;  
	  
		/* 如果SO_KEEPALIVE选项值为1，且此前没有设置SOCK_KEEPOPEN标志， 
		 * 则激活sk_timer，用作保活定时器。 
		 */  
		if (val && !sock_flag(sk, SOCK_KEEPOPEN))  
			inet_csk_reset_keepalive_timer(sk, keepalive_time_when(tcp_sk(sk)));  
		else if (!val)  
			/* 如果SO_KEEPALIVE选项值为0，则删除保活定时器 */  
			inet_csk_delete_keepalive_timer(sk);  
	}  
	   
	/* 保活定时器的超时时间 */  
	static inline int keepalive_time_when(const struct tcp_sock *tp)  
	{  
		return tp->keepalive_time ? : sysctl_tcp_keepalive_time;  
	}  
	  
	void inet_csk_reset_keepalive_timer (struc sock *sk, unsigned long len)  
	{  
		sk_reset_timer(sk, &sk->sk_timer, jiffies + len);  
	}  
```

可以使用TCP层选项来动态调整保活定时器的参数。

```
	int keepidle = 600;
	int keepintvl = 10;
	int keepcnt = 6;

	setsockopt(fd, SOL_TCP, TCP_KEEPIDLE, &keepidle, sizeof(keepidle));
	setsockopt(fd, SOL_TCP, TCP_KEEPINTVL, &keepintvl, sizeof(keepintvl));
	setsockopt(fd, SOL_TCP, TCP_KEEPCNT, &keepcnt, sizeof(keepcnt));
```

```
	struct tcp_sock {  
		...  
		/* 最后一次接收到ACK的时间 */  
		u32 rcv_tstamp; /* timestamp of last received ACK (for keepalives) */  
		...  
		/* time before keep alive takes place, 空闲多久后才发送探测报文 */  
		unsigned int keepalive_time;  
		/* time iterval between keep alive probes */  
		unsigned int keepalive_intvl; /* 探测报文之间的时间间隔 */  
		/* num of allowed keep alive probes */  
		u8 keepalive_probes; /* 探测报文的发送次数 */  
		...  
		struct {  
			...  
			/* 最后一次接收到带负荷的报文的时间 */  
			__u32 lrcvtime; /* timestamp of last received data packet */  
			...  
		} icsk_ack;  
		...  
	};  
	  
	#define TCP_KEEPIDLE 4 /* Start Keepalives after this period */  
	#define TCP_KEEPINTVL 5 /* Interval between keepalives */  
	#define TCP_KEEPCNT 6 /* Number of keepalives before death */  
	   
	#define MAX_TCP_KEEPIDLE 32767  
	#define MAX_TCP_KEEPINTVL 32767  
	#define MAX_TCP_KEEPCNT 127  
```

```
	static int do_tcp_setsockopt(struct sock *sk, int level, int optname, char __user *optval,  
		unsigned int optlen)  
	{  
		...  
		case TCP_KEEPIDLE:  
		   if (val < 1 || val > MAX_TCP_KEEPIDLE)  
			   err = -EINVAL;  
			else {  
				tp->keepalive_time = val * HZ; /* 设置新的空闲时间 */  
	  
				/* 如果有使用SO_KEEPALIVE选项，连接处于非监听非结束的状态。 
				 * 这个时候保活定时器已经在计时了，这里设置新的超时时间。 
				 */  
				if (sock_flag(sk, SOCK_KEEPOPEN) &&   
					!((1 << sk->sk_state) & (TCPF_CLOSE | TCPF_LISTEN))) {  
					u32 elapsed = keepalive_time_elapsed(tp); /* 连接已经经历的空闲时间 */  
	  
					if (tp->keepalive_time > elapsed)  
						elapsed = tp->keepalive_time - elapsed; /* 接着等待的时间，然后超时 */  
					else  
						elapsed = 0; /* 会导致马上超时 */  
					inet_csk_reset_keepalive_timer(sk, elapsed);  
				}  
			}  
			break;  
	  
		case TCP_KEEPINTVL:  
			if (val < 1 || val > MAX_TCP_KEEPINTVL)  
				err = -EINVAL;  
			else  
				tp->keepalive_intvl = val * HZ; /* 设置新的探测报文间隔 */  
			break;  
	  
		case TCP_KEEPCNT:  
			if (val < 1 || val > MAX_TCP_KEEPCNT)  
				err = -EINVAL;  
			else  
				tp->keepalive_probes = val; /* 设置新的探测次数 */  
			break;  
		...  
	}  
```

到目前为止，连接已经经历的空闲时间，即最后一次接收到报文至今的时间。

```
	static inline u32 keepalive_time_elapsed (const struct tcp_sock *tp)  
	{  
		const struct inet_connection_sock *icsk = &tp->inet_conn;  
	  
		/* lrcvtime是最后一次接收到数据报的时间 
		 * rcv_tstamp是最后一次接收到ACK的时间 
		 * 返回值就是最后一次接收到报文，到现在的时间，即经历的空闲时间。 
		 */  
		return min_t(u32, tcp_time_stamp - icsk->icsk_ack.lrcvtime,  
			tcp_time_stamp - tp->rcv_tstamp);  
	}  
```

#### 超时处理函数

我们知道保活定时器、SYNACK重传定时器、FIN_WAIT2定时器是共用一个定时器实例sk->sk_timer，所以它们的超时处理函数也是一样的，都为tcp_keepalive_timer()。而在函数内部，可以根据此时连接所处的状态，来判断是哪个定时器触发了超时。

Q：什么时候判断对端为异常并关闭连接？

A：分两种情况。

1. 用户使用了TCP_USER_TIMEOUT选项。当连接的空闲时间超过了用户设置的时间，且有发送过探测报文。

2. 用户没有使用TCP_USER_TIMEOUT选项。当发送保活探测包的次数达到了保活探测的最大次数时。

```
	static void tcp_keepalive_timer (unsigned long data)  
	{  
		struct sock *sk = (struct sock *) data;  
		struct inet_connection_sock *icsk = inet_csk(sk);  
		struct tcp_sock *tp = tcp_sk(sk);  
		u32 elapsed;  
	  
		/* Only process if socket is not in use. */  
		bh_lock_sock(sk);  
	  
		/* 加锁以保证在此期间，连接状态不会被用户进程修改。 
		 * 如果用户进程正在使用此sock，那么过50ms再来看看。 
		 */  
		if (sock_owned_by_user(sk)) {  
			/* Try again later. */  
			inet_csk_reset_keepalive_timer(sk, HZ/20);  
			goto out;  
		}  
	  
		/* 三次握手期间，用作SYNACK定时器 */  
		if (sk->sk_state == TCP_LISTEN) {  
			tcp_synack_timer(sk);  
			goto out;  
		}      
	  
		/* 连接释放期间，用作FIN_WAIT2定时器 */  
		if (sk->sk_state == TCP_FIN_WAIT2 && sock_flag(sk, SOCK_DEAD)) {  
			...  
		}  
	  
		/* 接下来就是用作保活定时器了 */  
		if (!sock_flag(sk, SOCK_KEEPOPEN) || sk->sk_state == TCP_CLOSE)  
			goto out;  
	  
		elapsed = keepalive_time_when(tp); /* 连接的空闲时间超过此值，就发送保活探测报文 */  
	  
		/* It is alive without keepalive. 
		 * 如果网络中有发送且未确认的数据包，或者发送队列不为空，说明连接不是idle的？ 
		 * 既然连接不是idle的，就没有必要探测对端是否正常。 
		 * 保活定时器重新开始计时即可。 
		 *  
		 * 而实际上当网络中有发送且未确认的数据包时，对端也可能会发生异常而没有响应。 
		 * 这个时候会导致数据包的不断重传，只能依靠重传超过了允许的最大时间，来判断连接超时。 
		 * 为了解决这一问题，引入了TCP_USER_TIMEOUT，允许用户指定超时时间，可见下文：） 
		 */  
		if (tp->packets_out || tcp_send_head(sk))  
			goto resched; /* 保活定时器重新开始计时 */  
	  
		/* 连接经历的空闲时间，即上次收到报文至今的时间 */  
		elapsed = keepalive_time_elapsed(tp);  
	  
		/* 如果连接空闲的时间超过了设置的时间值 */  
		if (elapsed >= keepalive_time_when(tp)) {  
	  
			/* 什么时候关闭连接？ 
			 * 1. 使用了TCP_USER_TIMEOUT选项。当连接空闲时间超过了用户设置的时间，且有发送过探测报文。 
			 * 2. 用户没有使用选项。当发送的保活探测包达到了保活探测的最大次数。 
			 */  
			if (icsk->icsk_user_timeout != 0 && elapsed >= icsk->icsk_user_timeout &&  
				icsk->icsk_probes_out > 0) || (icsk->icsk_user_timeout == 0 &&  
				icsk->icsk_probes_out >= keepalive_probes(tp))) {  
				tcp_send_active_reset(sk, GFP_ATOMIC); /* 构造一个RST包并发送 */  
				tcp_write_err(sk); /* 报告错误，关闭连接 */  
				goto out;  
			}  
	  
			/* 如果还不到关闭连接的时候，就继续发送保活探测包 */  
			if (tcp_write_wakeup(sk) <= 0) {  
				icsk->icsk_probes_out++; /* 已发送的保活探测包个数 */  
				elapsed = keepalive_intvl_when(tp); /* 下次超时的时间，默认为75s */  
			} else {  
				/* If keepalive was lost due to local congestion, try harder. */  
				elapsd = TCP_RESOURCE_PROBE_INTERVAL; /* 默认为500ms，会使超时更加频繁 */  
			}  
	  
		} else {  
			/* 如果连接的空闲时间，还没有超过设定值，则接着等待 */  
			elapsed = keepalive_time_when(tp) - elapsed;  
		}   
	  
		sk_mem_reclaim(sk);  
	  
	resched: /* 重设保活定时器 */  
		inet_csk_reset_keepalive_timer(sk, elapsed);  
		goto out;   
	  
	out:  
		bh_unlock_sock(sk);  
		sock_put(sk);  
	}  
```

Q：TCP是如何发送Keepalive探测报文的？

A：分两种情况。

1. 有新的数据段可供发送，且对端接收窗口还没被塞满。发送新的数据段，来作为探测包。

2. 没有新的数据段可供发送，或者对端的接收窗口满了。发送序号为snd_una - 1、长度为0的ACK包作为探测包。

```
	/* Initiate keepalive or window probe from timer. */  
	  
	int tcp_write_wakeup (struct sock *sk)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		struct sk_buff *skb;  
	  
		if (sk->sk_state == TCP_CLOSE)  
			return -1;  
	  
		/* 如果还有未发送过的数据包，并且对端的接收窗口还没有满 */  
		if ((skb = tcp_send_head(sk)) != NULL && before(TCP_SKB_CB(skb)->seq, tcp_wnd_end(tp))) {  
			int err;  
			unsigned int mss = tcp_current_mss(sk); /* 当前的MSS */  
			/* 对端接收窗口所允许的最大报文长度 */  
			unsigned int seg_size = tcp_wnd_end(tp) - TCP_SKB_CB(skb)->seq;  
	  
			/* pushed_seq记录发送出去的最后一个字节的序号 */  
			if (before(tp->pushed_seq, TCP_SKB_CB(skb)->end_seq))  
				tp->pushed_seq = TCP_SKB_CB(skb)->end_seq;  
	  
			/* 如果对端接收窗口小于此数据段的长度，或者此数据段的长度超过了MSS，那么就要进行分段 */  
			if (seg_size < TCP_SKB_CB(skb)->end_seq - TCP_SKB_CB(skb)->seq || skb->len > mss) {  
				seg_size = min(seg_size, mss);  
				TCP_SKB_CB(skb)->tcp_flags |= TCPHDR_PSH; /* 设置PSH标志，让对端马上把数据提交给程序 */  
				if (tcp_fragment(sk, skb, seg_size, mss)) /* 进行分段 */  
					return -1;  
			} else if (! tcp_skb_pcount(skb)) /* 进行TSO分片 */  
				tcp_set_skb_tso_segs(sk, skb, mss); /* 初始化分片相关变量 */  
	  
			TCP_SKB_CB(skb)->tcp_flags |= TCPHDR_PSH;  
			TCP_SKB_CB(skb)->when = tcp_time_stamp;  
			err = tcp_transmit_skb(sk, skb, 1, GFP_ATOMIC); /* 发送此数据段 */  
			if (!err)  
				tcp_event_new_data_sent(sk, skb); /* 发送了新的数据，更新相关参数 */  
	  
		} else { /* 如果没有新的数据段可用作探测报文发送，或者对端的接收窗口为0 */  
	  
		   /* 处于紧急模式时，额外发送一个序号为snd_una的ACK包，告诉对端紧急指针 */  
		   if (between(tp->snd_up, tp->snd_una + 1, tp->snd_una + 0xFFFF))  
			   tcp_xmit_probe_skb(sk, 1);  
	  
			/* 发送一个序号为snd_una -1的ACK包，长度为0，这是一个序号过时的报文。 
			 * snd_una: first byte we want an ack for，所以snd_una - 1序号的字节已经被确认过了。 
			 * 对端会响应一个ACK。 
			 */  
			return tcp_xmit_probe_skb(sk, 0);  
		}  
	}  
```

Q：当没有新的数据可以用作探测包、或者对端的接收窗口为0时，怎么办呢？

A：发送一个序号为snd_una - 1、长度为0的ACK包，对端收到此包后会发送一个ACK响应。如此一来本端就能够知道对端是否还活着、接收窗口是否打开了。

```
	/* This routine sends a packet with an out of date sequence number. 
	 * It assumes the other end will try to ack it. 
	 *  
	 * Question: what should we make while urgent mode? 
	 * 4.4BSD forces sending single byte of data. We cannot send out of window 
	 * data, because we have SND.NXT == SND.MAX... 
	 *  
	 * Current solution: to send TWO zero-length segments in urgent mode: 
	 * one is with SEG.SEG=SND.UNA to deliver urgent pointer, another is out-of-date with 
	 * SND.UNA - 1 to probe window. 
	 */  
	  
	static int tcp_xmit_probe_skb (struct sock *sk, int urgent)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		struct sk_buff *skb;  
	  
		/* We don't queue it, tcp_transmit_skb() sets ownership. */  
		skb = alloc_skb(MAX_TCP_HEADER, sk_gfp_atomic(sk, GFP_ATOMIC));  
		if (skb == NULL)  
			return -1;  
	  
		/* Reserve space for headers and set control bits. */  
		skb_reserve(skb, MAX_TCP_HEADER);  
	  
		/* Use a previous sequence. This should cause the other end to send an ack. 
		 * Don't queue or clone SKB, just send it. 
		 */  
		/* 如果没有设置紧急指针，那么发送的序号为snd_una - 1，否则发送的序号为snd_una */  
		tcp_init_nondata_skb(skb, tp->snd_una - !urgent, TCPHDR_ACK);  
		TCP_SKB_CB(skb)->when = tcp_time_stamp;  
		return tcp_transmit_skb(sk, skb, 0, GFP_ATOMIC); /* 发送探测包 */  
	}  
```

发送RST包。

```
	/* We get here when a process closes a file descriptor (either due to an explicit close() 
	 * or as a byproduct of exit()'ing) and there was unread data in the receive queue. 
	 * This behavior is recommended by RFC 2525, section 2.17. -DaveM 
	 */  
	  
	void tcp_send_active_reset (struct sock *sk, gfp_t priority)  
	{  
		struct sk_buff *skb;  
		/* NOTE: No TCP options attached and we never retransmit this. */  
		skb = alloc_skb(MAX_TCP_HEADER, priority);  
		if (!skb) {  
			NET_INC_STATS(sock_net(sk), LINUX_MIB_TCPABORTFAILED);  
			return;  
		}  
	  
		/* Reserve space for headers and prepare control bits. */  
		skb_reserve(skb, MAX_TCP_HEADER); /* 为报文头部预留空间 */  
		/* 初始化不携带数据的skb的一些控制字段 */  
		tcp_init_nondata_skb(skb, tcp_acceptable_seq(sk), TCPHDR_ACK | TCPHDR_RST);  
	  
		/* Send if off，发送此RST包*/  
		TCP_SKB_CB(skb)->when = tcp_time_stamp;  
		if (tcp_transmit_skb(sk, skb, 0, priority))  
			NET_INC_STATS(sock_net(sk), LINUX_MIB_TCPABORTFAILED);  
		TCP_INC_STATS(sock_net(sk), TCP_MIB_OUTRSTS);  
	}  
	  
	static inline __u32 tcp_acceptable_seq (const struct sock *sk)  
	{  
		const struct tcp_sock *tp = tcp_sk(sk);  
	  
		/* 如果snd_nxt在对端接收窗口范围内 */  
		if (! before(tcp_wnd_end(tp), tp->snd_nxt))  
			return tp->snd_nxt;  
		else  
			return tcp_wnd_end(tp);  
	}  
```
 
#### TCP_USER_TIMEOUT选项

从上文可知同时符合以下条件时，保活定时器才会发送探测报文：

1. 网络中没有发送且未确认的数据包。

2. 发送队列为空。

3. 连接的空闲时间超过了设定的时间。

Q：如果网络中有发送且未确认的数据包、或者发送队列不为空时，保活定时器不起作用了，岂不是不能够检测到对端的异常了？

A：可以使用TCP_USER_TIMEOUT，显式的指定当发送数据多久后还没有得到响应，就判定连接超时，从而主动关闭连接。


TCP_USER_TIMEOUT选项会影响到超时重传定时器和保活定时器。
 

(1) 超时重传定时器

判断连接是否超时，分3种情况：

1. SYN包：当SYN包的重传次数达到上限时，判定连接超时。(默认允许重传5次，初始超时时间为1s，总共历时31s)

2. 非SYN包，用户使用TCP_USER_TIMEOUT：当数据包发出去后的等待时间超过用户设置的时间时，判定连接超时。

3. 非SYN包，用户没有使用TCP_USER_TIMEOUT：当数据包发出去后的等待时间超过以TCP_RTO_MIN为初始超时时间，重传boundary次所花费的时间后，判定连接超时。(boundary的最大值为tcp_retries2，默认值为15)


(2) 保活定时器

判断连接是否异常，分2种情况：

1. 用户使用了TCP_USER_TIMEOUT选项。当连接的空闲时间超过了用户设置的时间，且有发送过探测报文。

2. 用户没有使用TCP_USER_TIMEOUT选项。当发送保活探测包的次数达到了保活探测的最大次数时。


