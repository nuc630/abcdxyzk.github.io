---
layout: post
title: "TCP拥塞控制窗口有效性验证机制"
date: 2015-12-08 15:49:00 +0800
comments: false
categories:
- 2015
- 2015~12
- kernel
- kernel~net
tags:
---
blog.csdn.net/zhangskd/article/details/7609465

#### 概述
问题1：当发送方长时间受到应用程序的限制，不能发送数据时，会使拥塞窗口无效。TCP是根据拥塞窗口来动态地估计网络带宽的。发送方受到应用程序的限制后，没有数据可以发送。那么此时的拥塞窗口就不能准确的反应网络状况，因为这个拥塞窗口是很早之前的。

问题2：当发送方受到应用程序限制，不能利用完拥塞窗口，会使拥塞窗口的增长无效。TCP不断调整cwnd来测试网络带宽。如果不能完全使用掉cwnd，就不知道网络能否承受得了cwnd的数据量，这种情况下的cwnd增长是无效的。


#### 原理
TCP sender受到的两种限制

(1) application-limited ：when the sender sends less than is allowed by the congestion or receiver window.

(2) network-limited：when the sender is limited by the TCP window. More precisely, we define a network-limited period as any period when the sender is sending a full window of data.

##### 问题1描述

TCP's congestion window controls the number of packets a TCP flow may have in the
network at any time. However, long periods when the sender is idle or application-limited
can lead to the invalidation of the congestion window, in that the congestion window no longer
reflects current information about the state of the network.

The congestion window is set using an Additive-Increase, Multiplicative-Decrease(AIMD) mechanism
that probes for available bandwidth, dynamically adapting to changing network conditions. This AIMD
works well when the sender continually has data to send, as is typically the case for TCP used for
bulk-data transfer. In contrast, for TCP used with telnet applications, the data sender often has little
or no data to send, and the sending rate is often determined by the rate at which data is generated
by the user.

##### 问题2描述

An invalid congestion window also results when the congestion window is increased (i.e.,
in TCP's slow-start or congestion avoidance phases) during application-limited periods, when the
previous value of the congestion window might never have been fully utilized. As far as we know, all
current TCP implementations increase the congestion window when an acknowledgement arrives,
if allowed by the receiver's advertised window and the slow-start or congestion avoidance window
increase algorithm, without checking to see if the previous value of the congestion window has in
fact been used.

This document proposes that the window increase algorithm not be invoked during application-
limited periods. This restriction prevents the congestion window from growing arbitrarily large,
in the absence of evidence that the congestion window can be supported by the network.

 
#### 实现(1)

发送方在发送数据包时，如果发送的数据包有负载，则会检测拥塞窗口是否超时。如果超时，则会使拥塞窗口失效并重新计算拥塞窗口。然后根据最近接收段的时间，确定是否进入pingpong模式。
```
	/* Congestion state accounting after a packet has been sent. */  
	static void tcp_event_data_sent (struct tcp_sock *tp, struct sock *sk)  
	{  
		struct inet_connection_sock *icsk = inet_csk(sk);  
		const u32 now = tcp_time_stamp;  
	  
		if (sysctl_tcp_slow_start_after_idle &&   
			(!tp->packets_out && (s32) (now - tp->lsndtime) > icsk->icsk_rto))  
			tcp_cwnd_restart(sk, __sk_dst_get(sk)); /* 重置cnwd */  
	  
		tp->lsndtime = now; /* 更新最近发包的时间*/  
	  
		/* If it is a reply for ato after last received packets,  
		 * enter pingpong mode. */  
		if ((u32)(now - icsk->icsk_ack.lrcvtime) < icsk.icsk_ack.ato)  
			icsk->icsk_ack.pingpong = 1;  
	}  
```

tcp_event_data_sent()中，符合三个条件才重置cwnd：

（1）tcp_slow_start_after_idle选项设置，这个内核默认置为1
（2）tp->packets_out == 0，表示网络中没有未确认数据包
（3）now - tp->lsndtime > icsk->icsk_rto，距离上次发送数据包的时间超过了RTO

```
	/* RFC2861. Reset CWND after idle period longer RTO to "restart window". 
	 * This is the first part of cnwd validation mechanism. 
	 */  
	static void tcp_cwnd_restart (struct sock *sk, const struct dst_entry *dst)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		s32 delta = tcp_time_stamp - tp->lsndtime;  
	  
		/* 关于tcp_init_cwnd()可见上一篇blog.*/  
		u32 restart_cwnd = tcp_init_cwnd(tp, dst);  
		u32 cwnd = tp->snd_cwnd;  
		  
		/* 触发拥塞窗口重置事件*/  
		tcp_ca_event(sk, CA_EVENT_CWND_RESTART);  
	  
		/* 阈值保存下来，并没有重置。*/  
		tp->snd_ssthresh = tcp_current_ssthresh(sk);  
		restart_cwnd = min(restart_cwnd, cwnd);  
	  
		/* 闲置时间每超过一个RTO且cwnd比重置后的大时，cwnd减半。*/  
		while((delta -= inet_csk(sk)->icsk_rto) > 0 && cwnd > restart_cwnd)  
			cwnd >> 1;  
	  
		tp->snd_cwnd = max(cwnd, restart_cwnd); /* 取其大者！*/  
		tp->snd_cwnd_stamp = tcp_time_stamp;  
		tp->snd_cwnd_used = 0;  
	}  
```

那么调用tcp_cwnd_restart()后，tp->snd_cwnd是多少呢？这个是不确定的，要看闲置时间delta、闲置前的cwnd、路由器中设置的initcwnd。当然，最大概率的是：拥塞窗口降为闲置前cwnd的一半。

#### 实现(2)

在发送方成功发送一个数据包后，会检查从发送队列发出而未确认的数据包是否用完拥塞窗口。
如果拥塞窗口被用完了，说明发送方收到网络限制；
如果拥塞窗口没被用完，且距离上次检查时间超过了RTO，说明发送方收到应用程序限制。
```
	/* Congestion window validation.(RFC2861) */  
	static void tcp_cwnd_validate(struct sock *sk) {  
		struct tcp_sock *tp = tcp_sk(sk);  
	  
		if (tp->packets_out >= tp->snd_cwnd) {  
			/* Network is feed fully. */  
			tp->snd_cwnd_used = 0; /*不用这个变量*/  
			tp->snd_cwnd_stamp = tcp_time_stamp; /* 更新检测时间*/  
	  
		} else {  
			/* Network starves. */  
			if (tp->packets_out > tp->snd_cwnd_used)  
				tp->snd_cwnd_used = tp->packets_out; /* 更新已使用窗口*/  
	  
				/* 如果距离上次检测的时间，即距离上次发包时间已经超过RTO*/  
				if (sysctl_tcp_slow_start_after_idle &&  
					(s32) (tcp_time_stamp - tp->snd_cwnd_stamp) >= inet_csk(sk)->icsk_rto)  
					tcp_cwnd_application_limited(sk);  
		}  
	}  
```

在发送方收到应用程序的限制期间，每隔RTO时间，都会调用tcp_cwnd_application_limited()来重新设置sshresh和cwnd，具体如下：
```
	/* RFC2861, slow part. Adjust cwnd, after it was not full during one rto. 
	 * As additional protections, we do not touch cwnd in retransmission phases, 
	 * and if application hit its sndbuf limit recently. 
	 */  
	void tcp_cwnd_application_limited(struct sock *sk)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
	  
		/* 只有处于Open态，应用程序没受到sndbuf限制时，才进行 
		 * ssthresh和cwnd的重置。 
		 */  
		if (inet_csk(sk)->icsk_ca_state == TCP_CA_Open &&   
			sk->sk_socket && !test_bit(SOCK_NOSPACE, &sk->sk_socket->flags)) {  
	  
			/* Limited by application or receiver window. */  
			u32 init_win = tcp_init_cwnd(tp, __sk_dst_get(sk));  
			u32 win_used = max(tp->snd_cwnd_used, init_win);  
	  
			/* 没用完拥塞窗口*/  
			if (win_used < tp->snd_cwnd) {  
				/* 并没有减小ssthresh，反而增大，保留了过去的信息，以便之后有数据发送 
				  * 时能快速增大到接近此时的窗口。 
				  */  
				tp->snd_ssthresh = tcp_current_ssthresh(sk);   
				/* 减小了snd_cwnd */  
				tp->snd_cwnd = (tp->snd_cwnd + win_used) >> 1;  
			}  
			tp->snd_cwnd_used = 0;  
		}  
		tp->snd_cwnd_stamp = tcp_time_stamp; /* 更新最近的数据包发送时间*/  
	}  
```

发送方受到应用程序限制，且限制的时间每经过RTO后，就会调用以上函数来处理snd_ssthresh和snd_cwnd：

（1）snd_ssthresh = max(snd_ssthresh, 3/4 cwnd)

慢启动阈值并没有减小，相反，如果此时cwnd较大，ssthresh会相应的增大。ssthresh是一个很重要的参数，它保留了旧的信息。这样一来，如果应用程序产生了大量的数据，发送方不再受到限制后，经过慢启动阶段，拥塞窗口就能快速恢复到接近以前的值了。

（2）snd_cwnd = (snd_cwnd + snd_cwnd_used) / 2

因为snd_cwnd_used < snd_cwnd，所以snd_cwnd是减小了的。减小snd_cwnd是为了不让它盲目的增长。因为发送方没有利用完拥塞窗口，并不能检测到网络是否能承受该拥塞窗口，这时的增长是无根据的。

#### 结论
在发送完数据包后，通过对拥塞窗口有效性的检验，能够避免使用不合理的拥塞窗口。

拥塞窗口代表着网络的状况，通过避免使用不合理的拥塞窗口，就能得到正确的网络状况，而不会采取一些不恰当的措施。

在上文的两种情况下，通过TCP的拥塞窗口有效性验证机制（TCP congestion window validationmechanism），能够更合理的利用网络、避免丢包，从而提高传输效率。

#### Reference
RFC2861

