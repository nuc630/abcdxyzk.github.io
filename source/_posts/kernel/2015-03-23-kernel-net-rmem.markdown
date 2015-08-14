---
layout: post
title: "TCP接收缓存大小的动态调整"
date: 2015-03-23 13:53:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/8200048

#### 引言
TCP中有拥塞控制，也有流控制，它们各自有什么作用呢？

拥塞控制(Congestion Control) — A mechanism to prevent a TCP sender from overwhelming the network.  
流控制(Flow Control) — A mechanism to prevent a TCP sender from overwhelming a TCP receiver.

下面是一段关于流控制原理的简要描述。  
“The basic flow control algorithm works as follows: The receiver communicates to the sender the maximum amount of data it can accept using the rwnd protocol field. This is called the receive window. The TCP sender then sends no more than this amount of data across the network. The TCP sender then stops and waits for acknowledgements back from the receiver. When acknowledgement of the previously sent data is returned to the sender, the sender then resumes sending new data. It's essentially the old maxim hurry up and wait. ”

由于发送速度可能大于接收速度、接收端的应用程序未能及时从接收缓冲区读取数据、接收缓冲区不够大不能缓存所有接收到的报文等原因，TCP接收端的接收缓冲区很快就会被塞满，从而导致不能接收后续的数据，发送端此后发送数据是无效的，因此需要流控制。TCP流控制主要用于匹配发送端和接收端的速度，即根据接收端当前的接收能力来调整发送端的发送速度。

TCP流控制中一个很重要的地方就是，TCP接收缓存大小是如何动态调整的，即TCP确认窗口上限是如何动态调整的？

本文主要分析TCP接收缓存大小动态调整的原理和实现。
 
#### 原理
早期的TCP实现中，TCP接收缓存的大小是固定的。随着网络的发展，固定的TCP接收缓存值就不适应了，成为TCP性能的瓶颈之一。这时候就需要手动去调整，因为不同的网络需要不同大小的TCP接收缓存，手动调整不仅费时费力，还会引起一些问题。TCP接收缓存设置小了，就不能充分利用网络。而TCP缓存设置大了，又浪费了内存。

如果把TCP接收缓存设置为无穷大，那就更糟糕了，因为某些应用可能会耗尽内存，使其它应用的连接陷入饥饿。所以TCP接收缓存的大小需要动态调整，才能达到最佳的效果。

动态调整TCP接收缓存大小，就是使TCP接收缓存按需分配，同时要确保TCP接收缓存大小不会成为传输的限制。

linux采用Dynamic Right-Sizing方法来动态调整TCP的接收缓存大小，其基本思想就是：通过估算发送方的拥塞窗口的大小，来动态设置TCP接收缓存的大小。

It has been demomstrated that this method can successfully grow the receiver's advertised window at a pace sufficient to avoid constraining the sender's throughput. As a result, systems can avoid the network performance problems that result from either the under-utilization or over-utilization of buffer space.

#### 实现
下文代码基于3.2.12内核，主要源文件为：net/ipv4/tcp_input.c。
```
	struct tcp_sock {  
		...  
		u32 rcv_nxt; /* What we want to receive next，希望接收的下一个序列号 */  
		u32 rcv_wnd; /* Current receiver window，当前接收窗口的大小*/  
		u32 copied_seq; /* Head of yet unread data，应用程序下次从这里复制数据 */  
		u16 advmss; /* Advertised MSS，接收端通告的MSS */  
		u32 window_clamp; /* Maximal window to advertise，通告窗口的上限*/  
	  
		/* Receiver side RTT estimation */  
		struct {  
			u32 rtt;  
			u32 seq;  
			u32 time;  
		} rcv_rtt_est; /* 用于接收端的RTT测量*/  
	  
		/* Receiver queue space */  
		struct {  
			int space;  
			u32 seq;  
			u32 time;  
		} rcvq_space; /* 用于调整接收缓冲区和接收窗口*/  
	  
		/* Options received (usually on last packet, some only on SYN packets). */  
		struct tcp_options_received rx_opt; /* TCP选项*/  
		...  
	};  
	  
	struct sock {  
		...  
		int sk_rcvbuf; /* TCP接收缓冲区的大小*/  
		int sk_sndbuf; /* TCP发送缓冲区大小*/  
		unsigned int ...  
			sk_userlocks : 4, /*TCP接收缓冲区的锁标志*/  
		...  
	};
```

#### RTT测量
在发送端有两种RTT的测量方法(具体可见前面blog)，但是因为TCP流控制是在接收端进行的，所以接收端也需要有测量RTT的方法。

#####（1）没有时间戳时的测量方法
```
	static inline void tcp_rcv_rtt_measure(struct tcp_sock *tp)  
	{  
		/* 第一次接收到数据时，需要对相关变量初始化*/  
		if (tp->rcv_rtt_est.time == 0)  
			goto new_measure;  
	  
		/* 收到指定的序列号后，才能获取一个RTT测量样本*/  
		if (before(tp->rcv_nxt, tp->rcv_rtt_est.seq))  
			return;  
	  
		/* RTT的样本：jiffies - tp->rcv_rtt_est.time */  
		tcp_rcv_rtt_update(tp, jiffies - tp->rcv_rtt_est.time, 1);  
	  
	new_measure:  
		tp->rcv_rtt_est.seq = tp->rcv_nxt + tp->rcv_wnd; /* 收到此序列号的ack时，一个RTT样本的计时结束*/  
		tp->rcv_rtt_est.time = tcp_time_stamp; /* 一个RTT样本开始计时*/  
	}
```

此函数在接收到带有负载的数据段时被调用。

此函数的原理：我们知道发送端不可能在一个RTT期间发送大于一个通告窗口的数据量。那么接收端可以把接收一个确认窗口的数据量(rcv_wnd)所用的时间作为RTT。接收端收到一个数据段，然后发送确认(确认号为rcv_nxt，通告窗口为rcv_wnd)，开始计时，RTT就是收到序号为rcv_nxt + rcv_wnd的数据段所用的时间。很显然，这种假设并不准确，测量所得的RTT会偏大一些。所以这种方法只有当没有采用时间戳选项时才使用，而内核默认是采用时间戳选项的(tcp_timestamps为1)。

下面是一段对此方法的评价：  
If the sender is being throttled by the network, this estimate will be valid. However, if the sending application did not have any data to send, the measured time could be much larger than the actual round-trip time. Thus this measurement acts only as an upper-bound on the round-trip time.

#####（2）采用时间戳选项时的测量方法
```
	static inline void tcp_rcv_rtt_measure_ts(struct sock *sk, const struct sk_buff *skb)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		/* 启用了Timestamps选项，并且流量稳定*/  
		if (tp->rx_opt.rcv_tsecr && (TCP_SKB_CB(skb)->end_seq - TCP_SKB_CB(skb)->seq >=  
			inet_csk(sk)->icsk_ack.rcv_mss))  
			/* RTT = 当前时间 - 回显时间*/  
			tcp_rcv_rtt_update(tp, tcp_time_stamp - tp->rx_opt.rcv_tsecr, 0);  
	}
```

虽然此种方法是默认方法，但是在流量小的时候，通过时间戳采样得到的RTT的值会偏大，此时就会采用没有时间戳时的RTT测量方法。

#####（3）采样处理
不管是没有使用时间戳选项的RTT采样，还是使用时间戳选项的RTT采样，都是获得一个RTT样本。之后还需要对获得的RTT样本进行处理，以得到最终的RTT。
```
	/* win_dep表示是否对RTT采样进行微调，1为不进行微调，0为进行微调。*/  
	static void tcp_rcv_rtt_update(struct tcp_sock *tp, u32 sample, int win_dep)  
	{  
		u32 new_sample = tp->rcv_rtt_est.rtt;  
		long m = sample;  
	  
		if (m == 0)  
			m = 1; /* 时延最小为1ms*/  
	  
		if (new_sample != 0) { /* 不是第一次获得样本*/  
			/* If we sample in larger samples in the non-timestamp case, we could grossly 
			 * overestimate the RTT especially with chatty applications or bulk transfer apps 
			 * which are stalled on filesystem I/O. 
			 * 
			 * Also, since we are only going for a minimum in the non-timestamp case, we do 
			 * not smooth things out else with timestamps disabled convergence takes too long. 
			 */  
			/* 对RTT采样进行微调，新的RTT样本只占最终RTT的1/8 */  
			if (! win_dep) {   
				m -= (new_sample >> 3);  
				new_sample += m;  
	  
			} else if (m < new_sample)  
				/* 不对RTT采样进行微调，直接取最小值，原因可见上面那段注释*/  
				new_sample = m << 3;   
	  
		} else {   
			/* No previous measure. 第一次获得样本*/  
			new_sample = m << 3;  
		}  
	  
		if (tp->rcv_rtt_est.rtt != new_sample)  
			tp->rcv_rtt_est.rtt = new_sample; /* 更新RTT*/  
	}
```

对于没有使用时间戳选项的RTT测量方法，不进行微调。因为用此种方法获得的RTT采样值已经偏高而且收敛很慢。直接选择最小RTT样本作为最终的RTT测量值。  
对于使用时间戳选项的RTT测量方法，进行微调，新样本占最终RTT的1/8，即rtt = 7/8 old + 1/8 new。

#### 调整接收缓存
当数据从TCP接收缓存复制到用户空间之后，会调用tcp_rcv_space_adjust()来调整TCP接收缓存和接收窗口上限的大小。
```
	/*  
	 * This function should be called every time data is copied to user space. 
	 * It calculates the appropriate TCP receive buffer space. 
	 */  
	void tcp_rcv_space_adjust(struct sock *sk)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		int time;  
		int space;  
	  
		/* 第一次调整*/  
		if (tp->rcvq_space.time == 0)  
			goto new_measure;  
	  
		time = tcp_time_stamp - tp->rcvq_space.time; /*计算上次调整到现在的时间*/  
	  
		/* 调整至少每隔一个RTT才进行一次，RTT的作用在这里！*/  
		if (time < (tp->rcv_rtt_est.rtt >> 3) || tp->rcv_rtt_est.rtt == 0)  
			return;  
	  
		/* 一个RTT内接收方应用程序接收并复制到用户空间的数据量的2倍*/  
		space = 2 * (tp->copied_seq - tp->rcvq_space.seq);  
		space = max(tp->rcvq_space.space, space);  
	  
		/* 如果这次的space比上次的大*/  
		if (tp->rcvq_space.space != space) {  
			int rcvmem;  
			tp->rcvq_space.space = space; /*更新rcvq_space.space*/  
	  
			/* 启用自动调节接收缓冲区大小，并且接收缓冲区没有上锁*/  
			if (sysctl_tcp_moderate_rcvbuf && ! (sk->sk_userlocks & SOCK_RCVBUF_LOCK)) {  
				int new_clamp = space;  
				/* Receive space grows, normalize in order to take into account packet headers and 
				 * sk_buff structure overhead. 
				 */  
				 space /= tp->advmss; /* 接收缓冲区可以缓存数据包的个数*/  
	  
				 if (!space)  
					space = 1;  
	  
				/* 一个数据包耗费的总内存包括： 
				   * 应用层数据：tp->advmss， 
				   * 协议头：MAX_TCP_HEADER， 
				   * sk_buff结构， 
				   * skb_shared_info结构。 
				   */  
				 rcvmem = SKB_TRUESIZE(tp->advmss + MAX_TCP_HEADER);  
	  
				 /* 对rcvmem进行微调*/  
				 while(tcp_win_from_space(rcvmem) < tp->advmss)  
					 rcvmem += 128;  
	  
				 space *= rcvmem;  
				 space = min(space, sysctl_tcp_rmem[2]); /*不能超过允许的最大接收缓冲区大小*/  
	  
				 if (space > sk->sk_rcvbuf) {  
					 sk->sk_rcvbuf = space; /* 调整接收缓冲区的大小*/  
					 /* Make the window clamp follow along. */  
					 tp->window_clamp = new_clamp; /*调整接收窗口的上限*/  
				 }  
			}  
		}  
	  
	new_measure:  
		 /*此序号之前的数据已复制到用户空间，下次复制将从这里开始*/  
		tp->rcvq_space.seq = tp->copied_seq;  
		tp->rcvq_space.time = tcp_time_stamp; /*记录这次调整的时间*/  
	}  
	  
	  
	/* return minimum truesize of the skb containing X bytes of data */  
	#define SKB_TRUESIZE(X) ((X) +              \  
		SKB_DATA_ALIGN(sizeof(struct sk_buff)) +        \  
		SKB_DATA_ALIGN(sizeof(struct skb_shared_info)))  
	  
	  
	static inline int tcp_win_from_space(int space)  
	{  
		return sysctl_tcp_adv_win_scale <= 0 ?  
				  (space >> (-sysctl_tcp_adv_win_scale)) :  
				   space - (space >> sysctl_tcp_adv_win_scale);  
	}
```

tp->rcvq_space.space表示当前接收缓存的大小（只包括应用层数据，单位为字节）。  
sk->sk_rcvbuf表示当前接收缓存的大小（包括应用层数据、TCP协议头、sk_buff和skb_shared_info结构，tcp_adv_win_scale微调，单位为字节）。

#### 系统参数
##### (1) tcp_moderate_rcvbuf
是否自动调节TCP接收缓冲区的大小，默认值为1。

##### (2) tcp_adv_win_scale
在tcp_moderate_rcvbuf启用的情况下，用来对计算接收缓冲区和接收窗口的参数进行微调，默认值为2。  
This means that the application buffer is 1/4th of the total buffer space specified in the tcp_rmem variable.

##### (3) tcp_rmem
包括三个参数：min default max。  
tcp_rmem[1] — default ：接收缓冲区长度的初始值，用来初始化sock的sk_rcvbuf，默认为87380字节。  
tcp_rmem[2] — max：接收缓冲区长度的最大值，用来调整sock的sk_rcvbuf，默认为4194304，一般是2000多个数据包。 

##### 小结
接收端的接收窗口上限和接收缓冲区大小，是接收方应用程序在上个RTT内接收并复制到用户空间的数据量的2倍，并且接收窗口上限和接收缓冲区大小是递增的。

######（1）为什么是2倍呢？
In order to keep pace with the growth of the sender's congestion window during slow-start, the receiver should use the same doubling factor. Thus the receiver should advertise a window that is twice the size of the last measured window size.

这样就能保证接收窗口上限的增长速度不小于拥塞窗口的增长速度，避免接收窗口成为传输瓶颈。

######（2）收到乱序包时有什么影响？
Packets that are received out of order may have lowered the goodput during this measurement, but will increase the goodput of the following measurement which, if larger, will supercede this measurement. 

乱序包会使本次的吞吐量测量值偏小，使下次的吞吐量测量值偏大。

#### Reference
[1] Mike Fisk, Wu-chun Feng, "Dynamic Right-Sizing in TCP".

