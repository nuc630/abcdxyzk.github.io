---
layout: post
title: "TCP的TSO处理（一）"
date: 2015-03-19 18:27:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/7699081

#### 概述
In computer networking, large segment offload (LSO) is a technique for increasing outbound
throughput of high-bandwidth network connections by reducing CPU overhead. It works by queuing
up large buffers and letting the network interface card (NIC) split them into separate packets.
The technique is also called TCP segmentation offload (TSO) when applied to TCP, or generic
segmentation offload (GSO).

The inbound counterpart of large segment offload is large recive offload (LRO).

When large chunks of data are to be sent over a computer network, they need to be first broken
down to smaller segments that can pass through all the network elements like routers and
switches between the source and destination computers. This process it referred to as
segmentation. Segmentation is often done by the TCP protocol in the host computer. Offloading
this work to the NIC is called TCP segmentation offload (TSO).

For example, a unit of 64KB (65,536 bytes) of data is usually segmented to 46 segments of 1448
bytes each before it is sent over the network through the NIC. With some intelligence in the NIC,
the host CPU can hand over the 64KB of data to the NIC in a single transmit request, the NIC can
break that data down into smaller segments of 1448 bytes, add the TCP, IP, and data link layer
protocol headers——according to a template provided by the host's TCP/IP stack——to each
segment, and send the resulting frames over the network. This significantly reduces the work
done by the CPU. Many new NICs on the market today support TSO. [1]

 
#### 具体

It is a method to reduce CPU workload of packet cutting in 1500byte and asking hardware to
perform the same functionality.

1.TSO feature is implemented using the hardware support. This means hardware should be
able to segment the packets in max size of 1500 byte and reattach the header with every
packets.

2.Every network hardware is represented by netdevice structure in kernel. If hardware supports
TSO, it enables the Segmentation offload features in netdevice, mainly represented by
" NETIF_F_TSO" and other fields. [2]

TCP Segmentation Offload is supported in Linux by the network device layer. A driver that wants
to offer TSO needs to set the NETIF_F_TSO bit in the network device structure. In order for a
device to support TSO, it needs to also support Net : TCP Checksum Offloading and
Net : Scatter Gather.

The driver will then receive super-sized skb's. These are indicated to the driver by
skb_shinfo(skb)->gso_size being non-zero. The gso_size is the size the hardware should
fragment the TCP data. TSO may change how and when TCP decides to send data. [3]

 
#### 实现
```
    /* This data is invariant across clones and lives at the end of the 
     * header data, ie. at skb->end. 
     */  
    struct skb_share_info {  
        ...  
       unsigned short gso_size; // 每个数据段的大小  
       unsigned short gso_segs; // skb被分割成多少个数据段  
       unsigned short gso_type;  
       struct sk_buff *frag_list; // 分割后的数据包列表  
       ...  
    }
```

```
    /* Initialize TSO state of skb. 
     * This must be invoked the first time we consider transmitting 
     * SKB onto the wire. 
     */  
    static int tcp_init_tso_segs(struct sock *sk, struct sk_buff *skb,  
                                                unsigned int mss_now)  
    {  
        int tso_segs = tcp_skb_pcount(skb);  
      
        /* 如果还没有分段，或者有多个分段但是分段长度不等于当前MSS，则需处理*/  
        if (! tso_segs || (tso_segs > 1 && tcp_skb_mss(skb) != mss_now)) {  
            tcp_set_skb_tso_segs(sk, skb, mss_now);  
      
            tso_segs = tcp_skb_pcount(skb);/* 重新获取分段数量 */  
        }  
        return tso_segs;  
    }  
      
    /* Initialize TSO segments for a packet. */  
    static void tcp_set_skb_tso_segs(struct sock *sk, struct sk_buff *skb,  
                                            unsigned int mss_now)  
    {  
        /* 有以下情况则不需要分片： 
          * 1. 数据的长度不超过允许的最大长度MSS 
         * 2. 网卡不支持GSO 
         * 3. 网卡不支持重新计算校验和 
         */  
        if (skb->len <= mss_now || ! sk_can_gso(sk) ||  
            skb->ip_summed == CHECKSUM_NONE) {  
      
            /* Avoid the costly divide in the normal non-TSO case.*/  
            skb_shinfo(skb)->gso_segs = 1;  
            skb_shinfo(skb)->gso_size = 0;  
            skb_shinfo(skb)->gso_type = 0;  
        } else {  
      
            /* 计算需要分成几个数据段*/  
            skb_shinfo(skb)->gso_segs = DIV_ROUND_UP(skb->len, mss_now);/*向上取整*/  
            skb_shinfo(skb)->gso_size = mss_now; /* 每个数据段的大小*/  
            skb_shinfo(skb)->gso_type = sk->sk_gso_type;  
        }  
    }  
      
    /* Due to TSO, an SKB can be composed of multiple actual packets.  
     * To keep these tracked properly, we use this. 
     */  
    static inline int tcp_skb_pcount (const struct sk_buff *skb)  
    {  
        return skb_shinfo(skb)->gso_segs;  
    }  
       
    /* This is valid if tcp_skb_pcount() > 1 */  
    static inline int tcp_skb_mss(const struct sk_buff *skb)  
    {  
        return skb_shinfo(skb)->gso_size;  
    }  
      
    static inline int sk_can_gso(const struct sock *sk)  
    {  
        /* sk_route_caps标志网卡驱动的特征, sk_gso_type表示GSO的类型， 
         * 设置为SKB_GSO_TCPV4 
         */  
        return net_gso_ok(sk->sk_route_caps, sk->sk_gso_type);  
    }  
      
    static inline int net_gso_ok(int features, int gso_type)  
    {  
        int feature = gso_type << NETIF_F_GSO_SHIFT;  
        return (features & feature) == feature;  
    }
```

##### sk_gso_max_size

NIC also specify the maximum segment size which it can handle, in sk_gso_max_size field.
Mostly it will be set to 64k. This 64k values means if the data at TCP is more than 64k,
then again TCP has to segment it in 64k and then push to interface.

相关变量，sock中：unsigned int sk_gso_max_size.

```
    /* RFC2861 Check whether we are limited by application or congestion window 
     * This is the inverse of cwnd check in tcp_tso_should_defer 
     * 函数返回1，受拥塞控制窗口的限制，需要增加拥塞控制窗口； 
     * 函数返回0，受应用程序的限制，不需要增加拥塞控制窗口。 
     */  
      
    int tcp_is_cwnd_limited(const struct sock *sk, u32 in_flight)  
    {  
        const struct tcp_sock *tp = tcp_sk(sk);  
        u32 left;  
       
        if (in_flight >= tp->snd_cwnd)  
            return 1;  
       
        /* left表示还可以发送的数据量 */  
        left = tp->snd_cwnd - in_flight;  
       
      
        /* 如果使用gso，符合以下条件，认为是拥塞窗口受到了限制， 
         * 可以增加拥塞窗口。 
         */  
        if (sk_can_gso(sk) &&   
            left * sysctl_tcp_tso_win_divisor < tp->snd_cwnd &&  
            left * tp->mss_cache < sk->sk_gso_max_size)  
            return 1;  
      
        /* 如果left大于允许的突发流量，那么拥塞窗口的增长已经很快了， 
         * 不能再增加了。 
         */  
        return left <= tcp_max_burst(tp);  
    }
```

#### TSO Nagle

GSO, Generic Segmentation Offload，是协议栈提高效率的一个策略。

它尽可能晚的推迟分段(segmentation)，最理想的是在网卡驱动里分段，在网卡驱动里把
大包(super-packet)拆开，组成SG list，或在一块预先分配好的内存中重组各段，然后交给
网卡。

The idea behind GSO seems to be that many of the performance benefits of LSO (TSO/UFO)
can be obtained in a hardware-independent way, by passing large "superpackets" around for
as long as possible, and deferring segmentation to the last possible moment - for devices
without hardware segmentation/fragmentation support, this would be when data is actually
handled to the device driver; for devices with hardware support, it could even be done in hardware.

Try to defer sending, if possible, in order to minimize the amount of TSO splitting we do.
View it as a kind of TSO Nagle test.

通过延迟数据包的发送，来减少TSO分段的次数，达到减小CPU负载的目的。

```
    struct tcp_sock {  
        ...  
        u32 tso_deferred; /* 上次TSO延迟的时间戳 */  
        ...  
    };
```

```
    /** This algorithm is from John Heffner. 
     * 0: send now ; 1: deferred 
     */  
    static int tcp_tso_should_defer (struct sock *sk, struct sk_buff *skb)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        const struct inet_connection_sock *icsk = inet_csk(sk);  
        u32 in_flight, send_win, cong_win, limit;  
        int win_divisor;  
          
        /* 如果此skb包含结束标志，则马上发送*/  
        if (TCP_SKB_CB(skb)->flags & TCPHDR_FIN)  
            goto send_now;  
      
        /* 如果此时不处于Open态，则马上发送*/  
        if (icsk->icsk_ca_state != TCP_CA_Open)  
            goto send_now;  
      
        /* Defer for less than two clock ticks. 
         * 上个skb被延迟了，且超过现在1ms以上，则不再延迟。 
         * 也就是说，TSO延迟不能超过2ms！ 
         */  
        if (tp->tso_deferred && (((u32)jiffies <<1) >> 1) - (tp->tso_deferred >> 1) > 1)  
            goto send_now;  
        
        in_flight = tcp_packets_in_flight(tp);  
        /* 如果此数据段不用分片，或者受到拥塞窗口的限制不能发包，则报错*/  
        BUG_ON(tcp_skb_pcount(skb) <= 1 || (tp->snd_cwnd <= in_flight));  
        /* 通告窗口的剩余大小*/  
        send_win = tcp_wnd_end(tp) - TCP_SKB_CB(skb)->seq;  
        /* 拥塞窗口的剩余大小*/  
        cong_win = (tp->snd_cwnd - in_flight) * tp->mss_cache;  
        /* 取其小者作为最终的发送限制*/  
        limit = min(send_win, cong_win);  
      
        /*If a full-sized TSO skb can be sent, do it. 
         * 一般来说是64KB 
         */  
        if (limit >= sk->sk_gso_max_size)  
            goto send_now;  
      
        /* Middle in queue won't get any more data, full sendable already ? */  
        if ((skb != tcp_write_queue_tail(sk)) && (limit >= skb->len))  
            goto send_now;  
      
        win_divisor = ACCESS_ONCE(sysctl_tcp_tso_win_divisor);  
        if (win_divisor) {  
            /* 一个RTT内允许发送的最大字节数*/  
            u32 chunk = min(tp->snd_wnd, tp->snd_cwnd * tp->mss_cache);  
            chunk /= win_divisor; /* 单个TSO段可消耗的发送量*/  
      
            /* If at least some fraction of a window is available, just use it. */  
            if (limit >= chunk)  
                goto send_now;  
        } else {  
            /* Different approach, try not to defer past a single ACK. 
             * Receiver should ACK every other full sized frame, so if we have space for 
             * more than 3 frames then send now. 
             */  
            if (limit > tcp_max_burst(tp) * tp->mss_cache)  
                goto send_now;  
        }  
      
        /* OK, it looks like it is advisable to defer. */  
        tp->tso_deferred = 1 | (jiffies << 1); /* 记录此次defer的时间戳*/  
      
        return 1;  
      
    send_now:  
        tp->tso_deferred = 0;  
        return 0;  
    }  
      
    /* Returns end sequence number of the receiver's advertised window */  
    static inline u32 tcp_wnd_end (const struct tcp_sock *tp)  
    {  
        /* snd_wnd的单位为字节*/  
        return tp->snd_una + tp->snd_wnd;  
    }
```

tcp_tso_win_divisor：单个TSO段可消耗拥塞窗口的比例，默认值为3。

##### 符合以下任意条件，不会TSO延迟，可马上发送：  
(1) 数据包带有FIN标志。传输快结束了，不宜延迟。  
(2) 发送方不处于Open拥塞状态。处于异常状态时，不宜延迟。  
(3) 上一次skb被延迟了，且距离现在大于等于2ms。延迟不能超过2ms。  
(4) min(send_win, cong_win) > full-sized TSO skb。允许发送的数据量超过TSO一次能处理的最大值，没必要再defer。  
(5) skb处于发送队列中间，且允许整个skb一起发送。处于发送队列中间的skb不能再获得新的数据，没必要再defer。  
(6) tcp_tso_win_divisor有设置时，limit > 单个TSO段可消耗的数据量，即min(snd_wnd, snd_cwnd * mss_cache) / tcp_tso_win_divisor。  
(7) tcp_tso_win_divisor没有设置时，limit > tcp_max_burst(tp) * mss_cache，一般是3个数据包。

条件4、5、6/7，都是limit > 某个阈值，就可以马上发送。这个因为通过这几个条件，可以确定此时发送是受到应用程序的限制，而不是通告窗口或者拥塞窗口。在应用程序发送的数据量很少的情况下，不宜采用TSO Nagle，因为这会影响此类应用。

我们注意到tcp_is_cwnd_limited()中的注释说：  
" This is the inverse of cwnd check in tcp_tso_should_defer"，所以可以认为在tcp_tso_should_defer()中包含判断
tcp_is_not_cwnd_limited (或者tcp_is_application_limited) 的条件。

 

##### 符合以下所有条件，才会进行TSO延迟：  
(1) 数据包不带有FIN标志。  
(2) 发送方处于Open拥塞状态。  
(3) 距离上一次延迟的时间在2ms以内。  
(4) 允许发送的数据量小于sk_gso_max_size。  
(5) skb处于发送队列末尾，或者skb不能整个发送出去。  
(6) tcp_tso_win_divisor有设置时，允许发送的数据量不大于单个TSO段可消耗的。  
(7) tcp_tso_win_divisor没有设置时，允许发送的数据量不大于3个包。  

 
可以看到TSO的触发条件并不苛刻，所以被调用时并没有加unlikely。
 
#### 应用
##### (1) 禁用TSO
```
	ethtool -K ethX tso off
```

##### (2) 启用TSO
TSO是默认启用的。
```
	ethtool -K ethX tso on
```

 
#### Reference
[1] http://en.wikipedia.org/wiki/Large_segment_offload

[2] http://tejparkash.wordpress.com/2010/03/06/tso-explained/

[3] http://www.linuxfoundation.org/collaborate/workgroups/networking/tso

