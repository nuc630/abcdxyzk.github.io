---
layout: post
title: "TCP接收窗口的调整算法"
date: 2015-03-19 17:42:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
[TCP接收窗口的调整算法（上）](http://blog.csdn.net/zhangskd/article/details/8588202)  
[TCP接收窗口的调整算法（中）](http://blog.csdn.net/zhangskd/article/details/8602493)  
[TCP接收窗口的调整算法（下）](http://blog.csdn.net/zhangskd/article/details/8603099)  


------------

### TCP接收窗口的调整算法（上）


我们知道TCP首部中有一个16位的接收窗口字段，它可以告诉对端：我现在能接收多少数据。TCP的流控制主要就是通过调整接收窗口的大小来进行的。

本文内容：分析TCP接收窗口的调整算法，包括一些相关知识和初始接收窗口的取值。

内核版本：3.2.12

#### 数据结构
以下是涉及到的数据结构。
```
    struct tcp_sock {  
        ...  
        /* 最早接收但未确认的段的序号，即当前接收窗口的左端*/  
        u32 rcv_wup; /* rcv_nxt on last window update sent */  
        u16 advmss; /* Advertised MSS. 本端能接收的MSS上限，建立连接时用来通告对端*/  
        u32 rcv_ssthresh; /* Current window clamp. 当前接收窗口大小的阈值*/  
        u32 rcv_wnd; /* Current receiver window，当前的接收窗口大小*/  
        u32 window_clamp; /* 接收窗口的最大值，这个值也会动态调整*/  
        ...  
    }
```

```
    struct tcp_options_received {  
        ...  
            snd_wscale : 4, /* Window scaling received from sender, 对端接收窗口扩大因子 */  
            rcv_wscale : 4; /* Window scaling to send to receiver, 本端接收窗口扩大因子 */  
        u16 user_mss; /* mss requested by user in ioctl */  
        u16 mss_clamp; /* Maximal mss, negotiated at connection setup，对端的最大mss */  
    }
```

```
	/** 
	 * struct sock - network layer representation of sockets 
	 * @sk_rcvbuf: size of receive buffer in bytes 
	 * @sk_receive_queue: incoming packets 
	 * @sk_write_queue: packet sending queue 
	 * @sk_sndbuf: size of send buffer in bytes 
	 */  
	struct sock {  
		...  
		struct sk_buff_head sk_receive_queue;  
		/* 表示接收队列sk_receive_queue中所有段的数据总长度*/  
	#define sk_rmem_alloc sk_backlog.rmem_alloc  
	  
		int sk_rcvbuf; /* 接收缓冲区长度的上限*/  
		int sk_sndbuf; /* 发送缓冲区长度的上限*/  
	  
		struct sk_buff_head sk_write_queue;  
		...  
	}  
	  
	struct sk_buff_head {  
		/* These two members must be first. */  
		struct sk_buff *next;  
		struct sk_buff *prev;  
		__u32 qlen;  
		spinlock_t lock;  
	};
```

<!-- more -->

在慢速路径中，有可能只带有TIMES
```
    /** 
     * inet_connection_sock - INET connection oriented sock 
     * @icsk_ack: Delayed ACK control data 
     */  
    struct inet_connection_sock {  
        ...  
        struct {  
            ...  
            /* 在快速发送确认模式中，可以快速发送ACK段的数量*/  
            __u8 quick; /* Scheduled number of quick acks */  
            /* 由最近接收到的段计算出的对端发送MSS */  
            __16 rcv_mss; /* MSS used for delayed ACK decisions */  
        } icsk_ack;  
        ...  
    }
```

```
    struct tcphdr {  
        __be16 source;  
        __be16 dest;  
        __be32 seq;  
        __be32 ack_seq;  
      
    #if defined (__LITTLE_ENDIAN_BITFIELD)  
        __u16 resl : 4,  
              doff : 4,  
              fin : 1,  
              syn : 1,  
              rst : 1,  
              psh : 1,  
              ack : 1,  
              urg : 1,  
              ece : 1,  
              cwr : 1;  
      
    #elif defined (__BIG_ENDIAN_BITFIELD)  
        __u16 doff : 4,  
              resl : 4,  
              cwr : 1,  
              ece : 1,  
              urg : 1,  
              ack : 1,  
              psh : 1,  
              rst : 1,  
              syn : 1,  
              fin : 1;  
    #else  
    #error "Adjust your <asm/byteorder.h> defines"  
    #endif  
        __be16 window; /* 接收窗口，在这边呢 */  
        __sum16 check;  
        __be16 urg_ptr;  
    }
```

发送窗口和接收窗口的更新：

![](/images/kernel/2015-03-19-1.jpg)  

#### MSS
先来看下MSS，它在接收窗口的调整中扮演着重要角色。  
通过MSS (Max Segment Size)，数据被分割成TCP认为合适发送的数据块，称为段(Segment)。  
注意：这里说的段(Segment)不包括协议首部，只包含数据！  

与MSS最为相关的一个参数就是网络设备接口的MTU(Max Transfer Unit)。  
两台主机之间的路径MTU并不一定是个常数，它取决于当时所选的路由。而选路不一定是对称的(从A到B的路由和从B到A的路由不同)。因此路径MTU在两个方向上不一定是对称的。  
所以，从A到B的有效MSS、从B到A的有效MSS是动态变化的，并且可能不相同。  

每个端同时具有几个不同的MSS：  
（1）tp->advmss  
本端在建立连接时使用的MSS，是本端能接收的MSS上限。  
这是从路由缓存中获得的(dst->metrics[RTAX_ADVMSS - 1])，一般是1460。

（2）tp->rx_opt.mss_clamp  
对端的能接收的MSS上限，min(tp->rx_opt.user_mss, 对端在建立连接时通告的MSS)。

（3）tp->mss_cache  
本端当前有效的发送MSS。显然不能超过对端接收的上限，tp->mss_cache <= tp->mss_clamp。

（4）tp->rx_opt.user_mss  
用户通过TCP_MAXSEG选项设置的MSS上限，用于决定本端和对端的接收MSS上限。

（5）icsk->icsk_ack.rcv_mss  
对端有效的发送MSS的估算值。显然不能超过本端接收的上限，icsk->icsk_ack.rcv_mss <= tp->advmss。

#### Receive buffer
接收缓存sk->sk_rcvbuf分为两部分：  
（1） network buffer，一般占3/4，这部分是协议能够使用的。  
（2）application buffer，一般占1/4。  

我们在计算连接可用接收缓存的时候，并不会使用整个的sk_rcvbuf，防止应用程序读取数据的速度比网络数据包到达的速度慢时，接收缓存被耗尽的情况。

以下是详细的说明：  
The idea is not to use a complete receive buffer space to calculate the receive buffer.  
We reserve some space as an application buffer, and the rest is used to queue incoming data segments.  
An application buffer corresponds to the space that should compensate for the delay in time it takes for an application to read from the socket buffer.  

If the application is reading more slowly than the rate at which data are arriving, data will be queued in the receive buffer. In order to avoid queue getting full, we advertise less receive window so that the sender can slow down the rate of data transmission and by that time the application gets a chance to read data from the receiver buffer.

一个包含X字节数据的skb的最小真实内存消耗(truesize)：
```
    /* return minimum truesize of one skb containing X bytes of data，这里的X包含协议头 */  
    #define SKB_TRUESIZE(X) ((X) +  \  
                        SKB_DATA_ALIGN(sizeof(struct sk_buff)) + \  
                        SKB_DATA_ALIGN(sizeof(struct skb_shared_info)))
```

#### 接收窗口的初始化
从最简单的开始，先来看下接收窗口的初始值、接收窗口扩大因子是如何取值的。
```
	/* Determine a window scaling and initial window to offer. 
	 * Based on the assumption that the given amount of space will be offered. 
	 * Store the results in the tp structure. 
	 * NOTE: for smooth operation initial space offering should be a multiple of mss 
	 * if possible. We assume here that mss >= 1. This MUST be enforced by all calllers. 
	 */  
	  
	void tcp_select_initial_window (int __space, __u32 mss, __u32 *rcv_wnd, __u32 *window_clamp,  
		                            int wscale_ok, __u8 *rcv_wscale, __u32 init_rcv_wnd)  
	{  
		unsigned int space = (__space < 0 ? 0 : __space); /* 接收缓存不能为负*/  
	  
		/* If no clamp set the clamp to the max possible scaled window。 
		 * 如果接收窗口上限的初始值为0，则把它设成最大。 
		 */  
		if (*window_clamp == 0)  
		    (*window_clamp) = (65535 << 14); /*这是接收窗口的最大上限*/  
	   
		/* 接收窗口不能超过它的上限 */  
		space = min(*window_clamp, space);   
	  
		/* Quantize space offering to a multiple of mss if possible. 
		 * 接收窗口大小最好是mss的整数倍。 
		 */  
		if (space > mss)  
		    space = (space / mss) * mss; /* 让space为mss的整数倍*/  
	   
		/* NOTE: offering an initial window larger than 32767 will break some 
		 * buggy TCP stacks. If the admin tells us it is likely we could be speaking 
		 * with such a buggy stack we will truncate our initial window offering to 
		 * 32K - 1 unless the remote has sent us a window scaling option, which 
		 * we interpret as a sign the remote TCP is not misinterpreting the window 
		 * field as a signed quantity. 
		 */  
		/* 当协议使用有符号的接收窗口时，则接收窗口大小不能超过32767*/  
		if (sysctl_tcp_workaround_signed_windows)  
		    (*rcv_wnd) = min(space, MAX_TCP_WINDOW);  
		esle  
		    (*rcv_wnd) = space;  
	   
		(*rcv_wscale) = 0;  
		/* 计算接收窗口扩大因子rcv_wscale，需要多大才能表示本连接的最大接收窗口大小？*/  
		if (wscale_ok) {  
		    /* Set window scaling on max possible window 
		     * See RFC1323 for an explanation of the limit to 14 
		     * tcp_rmem[2]为接收缓冲区长度上限的最大值，用于调整sk_rcvbuf。 
		      * rmem_max为系统接收窗口的最大大小。 
		      */  
		    space = max_t(u32, sysctl_tcp_rmem[2], sysctl_rmem_max);  
		    space = min_t(u32, space, *window_clamp); /*受限于具体连接*/  
	  
		    while (space > 65535 && (*rcv_wscale) < 14) {  
		        space >>= 1;  
		        (*rcv_wscale)++;  
		    }  
	   }  
	   
		/* Set initial window to a value enough for senders starting with initial 
		 * congestion window of TCP_DEFAULT_INIT_RCVWND. Place a limit on the  
		 * initial window when mss is larger than 1460. 
		 * 
		 * 接收窗口的初始值在这里确定，一般是10个数据段大小左右。 
		 */  
		if (mss > (1 << *rcv_wscale)) {  
		    int init_cwnd = TCP_DEFAULT_INIT_RCVWND; /* 10 */  
		    if (mss > 1460)  
		        init_cwnd = max_t(u32, 1460 * TCP_DEFAULT_INIT_RCVWND) / mss, 2);  
		      
		    /* when initializing use the value from init_rcv_wnd rather than the  
		     * default from above. 
		     * 决定初始接收窗口时，先考虑路由缓存中的，如果没有，再考虑系统默认的。 
		      */  
		    if (init_rcv_wnd) /* 如果路由缓存中初始接收窗口大小不为0*/  
		        *rcv_wnd = min(*rcv_wnd, init_rcv_wnd * mss);  
		    else   
		        *rcv_wnd = min(*rcv_wnd, init_cwnd *mss);  
		}  
	   
		/* Set the clamp no higher than max representable value */  
		(*window_clamp) = min(65535 << (*rcv_wscale), *window_clamp);  
	}
```

初始的接收窗口的取值(mss的整数倍)：  
（1）先考虑路由缓存中的RTAX_INITRWND  
（2）在考虑系统默认的TCP_DEFAULT_INIT_RCVWND(10)  
（3）最后考虑min(3/4 * sk_rcvbuf, window_clamp)，如果这个值很低  


窗口扩大因子的取值：  
接收窗口取最大值为max(tcp_rmem[2], rmem_max)，本连接接收窗口的最大值为 min(max(tcp_rmem[2], rmem_max), window_clamp)。  
那么我们需要多大的窗口扩大因子，才能用16位来表示最大的接收窗口呢？  
如果接收窗口的最大值受限于tcp_rmem[2] = 4194304，那么rcv_wscale = 7，窗口扩大倍数为128。  

发送SYN/ACK时的调用路径：tcp_v4_send_synack -> tcp_make_synack -> tcp_select_initial_window。

```
    /* Prepare a SYN-ACK. */  
    struct sk_buff *tcp_make_synack (struct sock *sk, struct dst_entry *dst,   
                                     struct request_sock *req, struct request_values *rvp)  
    {  
        struct inet_request_sock *ireq = inet_rsk(req);  
        struct tcp_sock *tp = tcp_sk(sk);  
        struct tcphdr *th;  
        struct sk_buff *skb;  
        ...  
        mss = dst_metric_advmss(dst); /*路由缓存中的mss*/  
        /*如果用户有特别设置，则取其小者*/  
        if (tp->rx_opt.user_mss && tp->rx_opt.user_mss < mss)  
            mss = tp->rx_opt.user_mss;  
       
        if (req->rcv_wnd == 0) { /* ignored for retransmitted syns */  
            __u8 rcv_wscale;  
      
            /* Set this up on the first call only */  
            req->window_clamp = tp->window_clamp ? : dst_metric(dst, RTAX_WINDOW);  
      
            /* limit the window selection if the user enforce a smaller rx buffer */  
            if (sk->sk_userlocks & SOCK_RCVBUF_LOCK &&   
                (req->window_clamp > tcp_full_space(sk) || req->window_clamp == 0))  
                req->window_clamp = tcp_full_space(sk);  
       
            /* tcp_full_space because it is guaranteed to be the first packet */  
            tcp_select_initial_window(tcp_full_space(sk),   
                                mss - (ireq->tstamp_ok ? TCPOLEN_TSTAMP_ALIGNED : 0),  
                                &req->rcv_wnd,  
                                &req->window_clamp,  
                                ireq->wscale_ok,  
                                &rcv_wscale,  
                                dst_metric(dst, RTAX_INITRWND));  
      
            ireq->rcv_wscale = rcv_wscale;  
        }  
        ...  
    }
```

-----------

### TCP接收窗口的调整算法（中）


本文内容：分析TCP接收窗口的调整算法，主要是接收窗口当前阈值的调整算法。

内核版本：3.2.12

#### 接收窗口当前阈值的调整算法
我们知道，在拥塞控制中，有个慢启动阈值，控制着拥塞窗口的增长。在流控制中，也有个接收窗口的当前阈值，控制着接收窗口的增长。可见TCP的拥塞控制和流控制，在某些地方有异曲同工之处。

接收窗口当前阈值tp->rcv_ssthresh的主要功能：  
On reception of data segment from the sender, this value is recalculated based on the size of the segment, and later on this value is used as upper limit on the receive window to be advertised.

可见，接收窗口当前阈值对接收窗口的大小有着重要的影响。

接收窗口当前阈值调整算法的基本思想：  
When we receive a data segment, we need to calculate a receive window that needs to be advertised to the sender, depending on the segment size received.  

The idea is to avoid filling the receive buffer with too many small segments when an application is reading very slowly and packets are transmitted at a very high rate.

在接收窗口当前阈值的调整算法中，收到数据报的负荷是个关键因素，至于它怎么影响接收窗口当前阈值的增长，来看下代码吧。

当接收到一个报文段时，调用处理函数：
```
    static void tcp_event_data_recv (struct sock *sk, struct sk_buff *skb)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        struct inet_connection_sock *icsk = inet_csk(sk);  
        u32 now;  
        ...  
        /* 当报文段的负荷不小于128字节时，考虑增大接收窗口当前阈值rcv_ssthresh */  
        if (skb->len >= 128)  
            tcp_grow_window(sk, skb);  
    }
```

下面这个函数决定是否增长rcv_ssthresh，以及增长多少。
```
    static void tcp_grow_window (struct sock *sk, const struct sk_buff *skb)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
       
        /* Check #1,关于这三个判断条件的含义可见下文分析 */  
        if (tp->rcv_ssthresh < tp->window_clamp &&   
             (int) tp->rcv_ssthresh < tcp_space(sk) && ! tcp_memory_pressure) {  
            int incr;  
              
            /* Check #2. Increase window, if skb with such overhead will fit to rcvbuf in future.  
             * 如果应用层数据占这个skb总共消耗内存的75%以上，则说明这个数据报是大的数据报， 
              * 内存的额外开销较小。这样一来我们可以放心的增长rcv_ssthresh了。 
              */  
            if (tcp_win_from_space(skb->truesize) <= skb->len)  
                incr = 2 * tp->advmss; /* 增加两个本端最大接收MSS */  
            else  
                /* 可能增大rcv_ssthresh，也可能不增大，具体视额外内存开销和剩余缓存而定*/  
                incr = __tcp_grow_window(sk, skb);  
      
            if (incr) {  
                /* 增加后不能超过window_clamp */  
                tp->rcv_ssthresh = min(tp->rcv_ssthresh + incr, tp->window_clamp);  
                inet_csk(sk)->icsk_ack.quick |= 1; /* 允许快速ACK */  
            }  
        }  
    }  
       
    /* Slow part of check#2. */  
    static int __tcp_grow_window (const struct sock *sk, const struct sk_buff *skb)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        /* Optimize this! */  
        int truesize = tcp_win_from_space(skb->truesize) >> 1;  
        int window = tcp_win_from_space(sysctl_tcp_rmem[2]) >> 1; /* 接收缓冲区长度上限的一半*/  
      
        /* rcv_ssthresh不超过一半的接收缓冲区上限才有可能*/  
        while (tp->rcv_ssthresh <= window) {  
            if (truesize <= skb->len)  
                return 2 * inet_csk(sk)->icsk_ack.rcv_mss; /* 增加两个对端发送MSS的估计值*/  
              
            truesize >>= 1;  
            window >>= 1;  
        }  
      
        return 0;/*不增长*/  
    }
```

这个算法可能不太好理解，我们来分析一下。

只有当数据段长度大于128字节时才会考虑增长rcv_ssthresh，并且有以下大前提(就是check #1)：  
a. 接收窗口当前阈值不能超过接收窗口的上限。  
b. 接收窗口当前阈值不能超过剩余接收缓存的3/4，即network buffer。  
c.  没有内存压力。TCP socket系统总共使用的内存过大。  

check#2是根据额外开销的内存占的比重，来判断是否允许增长。额外的内存开销(overhead)指的是：  
sk_buff、skb_shared_info结构体，以及协议头。有效的内存开销指的是数据段的长度。

（1） 额外开销小于25%，则rcv_ssthresh增长两个本端最大接收MSS。  
（2）额外开销大于25%，分为两种情况。  

算法如下：  
把3/4的剩余接收缓存，即剩余network buffer均分为2^n块。把额外开销均分为2^n份。  
如果均分后每块缓存的大小大于rcv_ssthresh，且均分后的每份开销小于数据段的长度，则： 
允许rcv_ssthresh增大2个对端发送MSS的估计值。  
否则，不允许增大rcv_ssthresh。  

我们注意到在(1)和(2)中，rcv_ssthresh的增长幅度是不同的。在(1)中，由于收到大的数据段，额外开销较低，所以增长幅度较大(2 * tp->advmss)。在(2)中，由于收到中等数据段，额外开销较高，所以增长幅度较小(2 * icsk->icsk_ack.rcv_mss)。这样做是为了防止额外开销过高，而耗尽接收窗口。

rcv_ssthresh增长算法的基本思想：  
This algorithm works on the basis that we do not want to increase the advertised window if we receive lots of small segments (i.e. interactive data flow), as the per-segment overhead (headers and the buffer control block) is very high.

额外开销大小，取决于数据段的大小。我们从这个角度来分析下当接收到一个数据报时，rcv_ssthresh的增长情况：
（1）Small segment (len < 128)  
如果接收到的数据段很小，这时不允许增大rcv_ssthresh，防止额外内存开销过大。

（2）Medium segment (128 <= len <= 647)  
如果接收到中等长度的数据段，符合条件时，rcv_ssthresh += 2 * rcv_mss。

（3）Large segment (len > 647)  
如果接收到数据段长度较大的报文，符合条件时(rcv_ssthresh不超过window_clamp和3/4剩余接收缓存等)，rcv_ssthresh += 2 * advmss。这是比较常见的情况，这时接收窗口阈值一般增加2 * 1460 = 2920字节。

这个值还可能有细微波动，这是由于对齐窗口扩大因子的关系。

----------

### TCP接收窗口的调整算法（下）


本文内容：分析TCP接收窗口的调整算法，主要是接收窗口的调整算法和总结。

内核版本：3.2.12

#### 接收窗口的调整算法
经过一系列的前奏，我们终于到了最关键的地方。接下来我们可以看到，接收窗口的大小主要取决于剩余的接收缓存，以及接收窗口当前阈值。决定接收窗口大小的函数tcp_select_window()在tcp_transmit_skb()中调用，也就是说每次我们要发送数据包时，都要使用tcp_select_window()来决定通告的接收窗口大小。

```
	static int tcp_transmit_skb (struct sock *sk, struct sk_buff *skb, int clone_it,   
		                         gfp_t gfp_mask)  
	{  
		const struct inet_connection_sock *icsk = inet_csk(sk);  
		struct inet_sock *inet;  
		struct tcp_sock *tp;  
		struct tcp_skb_cb *tcb;  
		struct tcphdr *th;  
		...  
		/* Build TCP header and checksum it，以下是TCP头的赋值*/  
		th = tcp_hdr(skb); /* skb->transport_header */  
		th->source = inet->inet_sport;  
		th->dest = inet->inet_dport;  
		th->seq = htonl(tcb->seq);  
		th->ack_seq = htonl(tp->rcv_nxt);  
		/* 这个语句可以看出C语言的强大*/  
		*(((__be16 *) th) + 6) = htons(((tcp_header_size >> 2) << 12) | tcb->tcp_flags);  
		  
		if (unlikely(tcb->tcp_flags & TCPHDR_SYN)) {  
		    /* RFC1323: The window in SYN & SYN/ACK segments in never scaled. 
		     * 从这里我们可以看到，在三次握手阶段，接收窗口并没有按扩大因子缩放。 
		      */  
		    th->window = htons(min(tp->rcv_wnd, 65535U));  
	  
		} else {  
		    th->window = htons(tcp_select_window(sk)); /* 更新接收窗口的大小*/  
		}  
		th->check = 0;  
		th->urg_ptr = 0;  
		...  
	}
```

来看下tcp_select_window()。

注意，接收窗口的返回值只有16位，所以如果不使用窗口扩大选项，那么接收窗口的最大值为65535。

```
    static u16 tcp_select_window(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
      
        u32 cur_win = tcp_receive_window(tp); /* 当前接收窗口的剩余大小*/  
        u32 new_win = __tcp_select_window(sk); /*根据剩余的接收缓存，计算新的接收窗口的大小 */  
      
        /* Never shrink the offered window，不允许缩小已分配的接收窗口*/  
        if (new_win < cur_win) {  
            /* Danger Will Robinson! 
             * Don't update rcv_wup/rcv_wnd here or else 
             * we will not be able to advertise a zero window in time. --DaveM 
             * Relax Will Robinson. 
             */  
            new_win = ALIGN(cur_win, 1 << tp->rx_opt.rcv_wscale);  
        }  
      
        /* 更新接收窗口大小。个人觉得这句代码应该后移，因为此时接收窗口的大小还未最终确定！*/  
        tp->rcv_wnd = new_win;  
        tp->rcv_wup = tp->rcv_nxt; /* 更新接收窗口的左边界，把未确认的数据累积确认*/  
       
        /* 确保接收窗口大小不超过规定的最大值。 
          * Make sure we do not exceed the maximum possible scaled window. 
         */  
        if (! tp->rx_opt.rcv_wscale && sysctl_tcp_workaround_signed_windows)  
            /* 不能超过32767，因为一些奇葩协议采用有符号的接收窗口大小*/  
            new_win = min(new_win, MAX_TCP_WINDOW);   
      
        else  
            new_win = min(new_win, (65535U << tp->rx_opt.rcv_wscale));  
       
        /* RFC1323 scaling applied. 按比例因子缩小接收窗口，这样最多能表示30位*/  
        new_win >>= tp->rx_opt.rcv_wscale;  
       
        /* If we advertise zero window, disable fast path. */  
        if (new_win == 0)  
            tp->pred_flags = 0;  
       
        return new_win; /* 返回最终的接收窗口大小*/  
    }
```

每次发送一个TCP数据段，都要构建TCP首部，这时会调用tcp_select_window选择接收窗口大小。  
窗口大小选择的基本算法：  
1. 计算当前接收窗口的剩余大小cur_win。  
2. 计算新的接收窗口大小new_win，这个值为剩余接收缓存的3/4，且不能超过rcv_ssthresh。  
3. 取cur_win和new_win中值较大者作为接收窗口大小。  

##### tcp_workaround_signed_windows
标识在未启用窗口扩大因子选项时，是否使用初始值不超过32767的TCP窗口，默认值为0(不启用)。  
我们知道在不启用窗口扩大因子选项时，接收窗口有16位，最大值为65535。但是有些很糟糕的协议  
采用的是有符号的窗口大小，所以最大值只能为32767。当然，这种协议并不多见：）。  

```
    @include/net/tcp.h：  
    /* 
     * Never offer a window over 32767 without using window scaling. 
     * Some poor stacks do signed 16bit maths!  
     */  
    #define MAX_TCP_WINDOW 32767U
```

计算当前接收窗口的剩余大小cur_win。

```
    /*  
     * Compute the actual receive window we are currently advertising. 
     * rcv_nxt can be after the window if our peer push more data than 
     * the offered window. 
     */  
    static inline u32 tcp_receive_window (const struct tcp_sock *tp)  
    {  
        s32 win = tp->rcv_wup + tp->rcv_wnd - tp->rcv_nxt;  
       
        if (win < 0)  
            win = 0;  
      
        return (u32) win;  
    }
```

详细说明：  
This is calculated as the last advertised window minus unacknowledged data length:  
tp->rcv_wnd - (tp->rcv_nxt - tp->rcv_wup)  
tp->rcv_wup is synced with next byte to be received (tp->rcv_nxt) only when we are sending ACK in tcp_select_window(). If there is no unacknowledged bytes, the routine returns the exact receive window advertised last.

计算新的接收窗口大小new_win，这个是关键函数，我们将看到rcv_ssthresh所起的作用。

```
	/*  
	 * calculate the new window to be advertised. 
	 */  
	u32 __tcp_select_window(struct sock *sk)  
	{  
		struct inet_connection_sock *icsk = inet_csk(sk);  
		struct tcp_sock *tp = tcp_sk(sk);  
	   
		/* MSS for the peer's data. Previous versions used mss_clamp here. 
		 * I don't know if the value based on our guesses of peer's MSS is better 
		 * for the performance. It's more correct but may be worse for the performance 
		 * because of rcv_mss fluctuations. —— SAW 1998/11/1 
		 */  
		int mss = icsk->icsk_ack.rcv_mss;/*这个是估计目前对端有效的发送mss，而不是最大的*/    
		int free_space = tcp_space(sk); /* 剩余接收缓存的3/4 */  
		int full_space = min_t(int, tp->window_clamp, tcp_full_space(sk)); /* 总的接收缓存 */  
		int window;  
	   
		if (mss > full_space)  
		    mss = full_space; /* 减小mss，因为接收缓存太小了*/  
	   
		/* receive buffer is half full，接收缓存使用一半以上时要小心了 */  
		if (free_space < (full_space >> 1)) {  
		    icsk->icsk_ack.quick = 0; /* 可以快速发送ACK段的数量置零*/  
	   
		    if (tcp_memory_pressure)/*有内存压力时，把接收窗口限制在5840字节以下*/  
		        tp->rcv_ssthresh = min(tp->rcv_ssthresh, 4U * tp->advmss);  
	  
		    if (free_space < mss) /* 剩余接收缓存不足以接收mss的数据*/  
		        return 0;  
		}  
	   
		if (free_space > tp->rcv_ssthresh)  
		    /* 看！不能超过当前接收窗口阈值，这可以达接收窗口平滑增长的效果*/  
		    free_space = tp->rcv_ssthresh;    
	  
		/* Don't do rounding if we are using window scaling, since the scaled window will 
		 * not line up with the MSS boundary anyway. 
		 */  
		window = tp->rcv_wnd;  
		if (tp->rx_opt.rcv_wscale) { /* 接收窗口扩大因子不为零*/  
		    window = free_space;  
	  
		    /* Advertise enough space so that it won't get scaled away. 
		     * Import case: prevent zero window announcement if 1 << rcv_wscale > mss. 
		     * 防止四舍五入造通告的接收窗口偏小。 
		      */  
		    if (((window >> tp->rx_opt.rcv_wscale) << tp->rx_opt.rcv_wscale) != window)  
		        window =(((window >> tp->rx_opt.rcv_wscale) + 1) << tp->rx_opt.rcv_wscale);  
	  
		} else {  
		    /* Get the largest window that is a nice multiple of mss. 
		     * Window clamp already applied above. 
		     * If our current window offering is within 1 mss of the free space we just keep it. 
		     * This prevents the divide and multiply from happening most of the time. 
		     * We also don't do any window rounding when the free space is too small. 
		     */  
		    /* 截取free_space中整数个mss，如果rcv_wnd和free_space的差距在一个mss以上*/  
		    if (window <= free_space - mss || window > free_space)   
		        window = (free_space / mss) * mss;  
		    /* 如果free space过小，则直接取free space值*/  
		    else if (mss = full_space && free_space > window + (full_space >> 1))  
		        window = free_space;  
		    /* 当free_space -mss < window < free_space时，直接使用rcv_wnd，不做修改*/  
		}      
	  
		return window;  
	}
```

```
    /* 剩余接收缓存的3/4。 
     * Note: caller must be prepared to deal with negative returns. 
     */  
    static inline int tcp_space (const struct sock *sk)  
    {  
        return tcp_win_from_space(sk->sk_rcvbuf - atomic_read(&sk->sk_rmem_alloc));  
    }  
      
    static inline int tcp_win_from_space(int space)  
    {  
        return sysctl_tcp_adv_win_scale <= 0 ? (space >> (-sysctl_tcp_adv_win_scale)) :  
            space - (space >> sysctl_tcp_adv_win_scale);  
    }  
      
    /* 最大的接收缓存的3/4 */  
    static inline int tcp_full_space(const struct sock *sk)  
    {  
        return tcp_win_from_space(sk->sk_rcvbuf);  
    }
```

总体来说，新的接收窗口大小值为：剩余接收缓存的3/4，但不能超过接收缓存的阈值。

#### 小结
接收窗口的调整算法主要涉及：  
（1）window_clamp和sk_rcvbuf的调整，在之前的blog《TCP接收缓存大小的动态调整》中有分析。  
（2）rcv_ssthresh接收窗口当前阈值的动态调整，一般增长2*advmss。  
（3）rcv_wnd接收窗口的动态调整，一般为min(3/4 free space in sk_rcvbuf, rcv_ssthresh)。  

如果剩余的接收缓存够大，rcv_wnd受限于rcv_ssthresh。这个时候每收到一个大的数据包，rcv_wnd就增大2920字节(由于缩放原因这个值可能波动)。这就像慢启动一样，接收窗口指数增长。

接收窗口当然不能无限制增长，当它增长到一定大小时，就会受到一系列因素的限制，比如window_clamp和sk_rcvbuf，或者剩余接收缓存区大小。

当应用程序读取接收缓冲区数据不够快时，或者发生了丢包时，接收窗口会变小，这主要受限于剩余的接收缓存的大小。

总的来说，接收窗口的调整算法涉及到一些变量，由于这些变量本身又是动态变化的，所以分析起来比较复杂，笔者也还需要再进行深入了解：）


