---
layout: post
title: "Linux TCP数据包接收处理tcp_rcv_established"
date: 2015-04-01 17:50:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://www.cppblog.com/fwxjj/archive/2013/02/18/197906.aspx

tcp_rcv_established函数的工作原理是把数据包的处理分为2类：fast path和slow path，其含义显而易见。这样分类的目的当然是加快数据包的处理，因为在正常情况下，数据包是按顺序到达的，网络状况也是稳定的，这时可以按照fast path直接把数据包存放到receive queue了。而在其他的情况下则需要走slow path流程了。

在协议栈中，是用头部预测来实现的，每个tcp sock有个pred_flags成员，它就是判别的依据。

```
    static inline void __tcp_fast_path_on(struct tcp_sock *tp, u32 snd_wnd)  
    {  
        tp->pred_flags = htonl((tp->tcp_header_len << 26) |  
                       ntohl(TCP_FLAG_ACK) |  
                       snd_wnd);  
    }  
```

可以看出头部预测依赖的是头部长度字段和通告窗口。也就是说标志位除了ACK和PSH外，如果其他的存在的话，就不能用

##### fast path处理，其揭示的含义如下：

1 Either the data transaction is taking place in only one direction (which means that we are the receiver and not transmitting any data) or in the case where we are sending out data also, the window advertised from the other end is constant. The latter means that we have not transmitted any data from our side for quite some time but are receiving data from the other end. The receive window advertised by the other end is constant.

2. Other than PSH|ACK flags in the TCP header, no other flag is set (ACK is set for each TCP segment).   
This means that if any other flag is set such as URG, FIN, SYN, ECN, RST, and CWR, we know that something important is there to be attended and we need to move into the SLOW path.

3. The header length has unchanged. If the TCP header length remains unchanged, we have not added/reduced any TCP option and we can safely assume that there is nothing important to be attended, if the above two conditions are TRUE.


##### fast path工作的条件
```
    static inline void tcp_fast_path_check(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
      
        if (skb_queue_empty(&tp->out_of_order_queue) &&  
            tp->rcv_wnd &&  
            atomic_read(&sk->sk_rmem_alloc) < sk->sk_rcvbuf &&  
            !tp->urg_data)  
            tcp_fast_path_on(tp);  
    }  
```

1 没有乱序数据包  
2 接收窗口不为0  
3 还有接收缓存空间  
4 没有紧急数据  

反之，则进入slow path处理；另外当连接新建立时处于slow path。

##### 从fast path进入slow path的触发条件（进入slow path 后pred_flags清除为0）：  
1 在tcp_data_queue中接收到乱序数据包  
2 在tcp_prune_queue中用完缓存并且开始丢弃数据包  
3 在tcp_urgent_check中遇到紧急指针  
4 在tcp_select_window中发送的通告窗口下降到0.  

##### 从slow_path进入fast_path的触发条件：  
1 When we have read past an urgent byte in tcp_recvmsg() . Wehave gotten an urgent byte and we remain in the slow path mode until we receive the urgent byte because it is handled in the slow path in tcp_rcv_established().  
2 当在tcp_data_queue中乱序队列由于gap被填充而处理完毕时，运行tcp_fast_path_check。  
3 tcp_ack_update_window()中更新了通告窗口。

#### fast path处理流程
A 判断能否进入fast path

```
    if ((tcp_flag_word(th) & TCP_HP_BITS) == tp->pred_flags &&  
            TCP_SKB_CB(skb)->seq == tp->rcv_nxt) {  
```
TCP_HP_BITS的作用就是排除flag中的PSH标志位。只有在头部预测满足并且数据包以正确的顺序（该数据包的第一个序号就是下个要接收的序号）到达时才进入fast path。

```
    int tcp_header_len = tp->tcp_header_len;  
      
    /* Timestamp header prediction: tcp_header_len 
     * is automatically equal to th->doff*4 due to pred_flags 
     * match. 
     */  
      
    /* Check timestamp */  
    //相等说明tcp timestamp option被打开。
    if (tcp_header_len == sizeof(struct tcphdr) + TCPOLEN_TSTAMP_ALIGNED) {  
        /* No? Slow path! */  
        //这里主要是parse timestamp选项，如果返回0则表明pase出错，此时我们进入slow_path
        if (!tcp_parse_aligned_timestamp(tp, th))  
            goto slow_path;  
      
        /* If PAWS failed, check it more carefully in slow path */  
        //如果上面pase成功，则tp对应的rx_opt域已经被正确赋值，此时如果rcv_tsval（新的接收的数据段的时间戳)比ts_recent(对端发送过来的数据(也就是上一次)的最新的一个时间戳)小，则我们要进入slow path 处理paws。
        if ((s32)(tp->rx_opt.rcv_tsval - tp->rx_opt.ts_recent) < 0)  
            goto slow_path;  
      
        /* DO NOT update ts_recent here, if checksum fails 
         * and timestamp was corrupted part, it will result 
         * in a hung connection since we will drop all 
         * future packets due to the PAWS test. 
         */  
    }  
```
该代码段是依据时戳选项来检查PAWS（Protect Against Wrapped Sequence numbers）。
如果发送来的仅是一个TCP头的话（没有捎带数据或者接收端检测到有乱序数据这些情况时都会发送一个纯粹的ACK包）

```
    /* Bulk data transfer: sender */  
    if (len == tcp_header_len) {  
        /* Predicted packet is in window by definition. 
         * seq == rcv_nxt and rcv_wup <= rcv_nxt. 
         * Hence, check seq<=rcv_wup reduces to: 
         */  
        if (tcp_header_len ==  
            (sizeof(struct tcphdr) + TCPOLEN_TSTAMP_ALIGNED) &&  
            tp->rcv_nxt == tp->rcv_wup)  
            tcp_store_ts_recent(tp);  
      
        /* We know that such packets are checksummed 
         * on entry. 
         */  
        tcp_ack(sk, skb, 0);  
        __kfree_skb(skb);  
        tcp_data_snd_check(sk);  
        return 0;  
    } else { /* Header too small */  
        TCP_INC_STATS_BH(sock_net(sk), TCP_MIB_INERRS);  
        goto discard;  
    }  
```

主要的工作如下：  
1 保存对方的最近时戳 tcp_store_ts_recent。通过前面的if判断可以看出tcp总是回显2次时戳回显直接最先到达的数据包的时戳，  
  rcv_wup只在发送数据（这时回显时戳）时重置为rcv_nxt，所以接收到前一次回显后第一个数据包后，rcv_nxt增加了，但是  
  rcv_wup没有更新，所以后面的数据包处理时不会调用该函数来保存时戳。  
2 ACK处理。这个函数非常复杂，包含了拥塞控制机制，确认处理等等。  
3 检查是否有数据待发送 tcp_data_snd_check。

如果该数据包中包含了数据的话

```
            } else {  
                int eaten = 0;  
                int copied_early = 0;  
                /* 此数据包刚好是下一个读取的数据，并且用户空间可存放下该数据包*/  
                if (tp->copied_seq == tp->rcv_nxt &&  
                    len - tcp_header_len <= tp->ucopy.len) {  
    #ifdef CONFIG_NET_DMA  
                    if (tcp_dma_try_early_copy(sk, skb, tcp_header_len)) {  
                        copied_early = 1;  
                        eaten = 1;  
                    }  
    #endif          /* 如果该函数在进程上下文中调用并且sock被用户占用的话*/  
                    if (tp->ucopy.task == current &&  
                        sock_owned_by_user(sk) && !copied_early) {  
                        /* 进程有可能被设置为TASK_INTERRUPTIBLE */  
                        __set_current_state(TASK_RUNNING);  
                        /* 直接copy数据到用户空间*/  
                        if (!tcp_copy_to_iovec(sk, skb, tcp_header_len))  
                            eaten = 1;  
                    }  
                    if (eaten) {  
                        /* Predicted packet is in window by definition. 
                         * seq == rcv_nxt and rcv_wup <= rcv_nxt. 
                         * Hence, check seq<=rcv_wup reduces to: 
                         */  
                        if (tcp_header_len ==  
                            (sizeof(struct tcphdr) +  
                             TCPOLEN_TSTAMP_ALIGNED) &&  
                            tp->rcv_nxt == tp->rcv_wup)  
                            tcp_store_ts_recent(tp);  
                        /* 更新RCV RTT，Dynamic Right-Sizing算法*/  
                        tcp_rcv_rtt_measure_ts(sk, skb);  
      
                        __skb_pull(skb, tcp_header_len);  
                        tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;  
                        NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPHPHITSTOUSER);  
                    }  
                    if (copied_early)  
                        tcp_cleanup_rbuf(sk, skb->len);  
                }  
                if (!eaten) { /* 没有直接读到用户空间*/  
                    if (tcp_checksum_complete_user(sk, skb))  
                        goto csum_error;  
      
                    /* Predicted packet is in window by definition. 
                     * seq == rcv_nxt and rcv_wup <= rcv_nxt. 
                     * Hence, check seq<=rcv_wup reduces to: 
                     */  
                    if (tcp_header_len ==  
                        (sizeof(struct tcphdr) + TCPOLEN_TSTAMP_ALIGNED) &&  
                        tp->rcv_nxt == tp->rcv_wup)  
                        tcp_store_ts_recent(tp);  
      
                    tcp_rcv_rtt_measure_ts(sk, skb);  
      
                    if ((int)skb->truesize > sk->sk_forward_alloc)  
                        goto step5;  
      
                    NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPHPHITS);  
      
                    /* Bulk data transfer: receiver */  
                    __skb_pull(skb, tcp_header_len);  
                                    /* 进入receive queue 排队，以待tcp_recvmsg读取*/  
                    __skb_queue_tail(&sk->sk_receive_queue, skb);  
                    skb_set_owner_r(skb, sk);  
                    tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;  
                }  
                /* 数据包接收后续处理*/  
                tcp_event_data_recv(sk, skb);  
                /* ACK 处理*/  
                if (TCP_SKB_CB(skb)->ack_seq != tp->snd_una) {  
                    /* Well, only one small jumplet in fast path... */  
                    tcp_ack(sk, skb, FLAG_DATA);  
                    tcp_data_snd_check(sk);  
                    if (!inet_csk_ack_scheduled(sk))  
                        goto no_ack;  
                }  
                /* ACK发送处理*/  
                if (!copied_early || tp->rcv_nxt != tp->rcv_wup)  
                    __tcp_ack_snd_check(sk, 0);  
    no_ack:  
    #ifdef CONFIG_NET_DMA  
                if (copied_early)  
                    __skb_queue_tail(&sk->sk_async_wait_queue, skb);  
                else  
    #endif                    
                /* eaten为1，表示数据直接copy到了用户空间，这时无需提醒用户进程数据的到达，否则需调用sk_data_ready来通知，因为此时数据到达了receive queue*/  
                if (eaten)  
                    __kfree_skb(skb);  
                else  
                    sk->sk_data_ready(sk, 0);  
                return 0;  
            }  
```

#### tcp_event_data_recv函数
```
    static void tcp_event_data_recv(struct sock *sk, struct sk_buff *skb)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        struct inet_connection_sock *icsk = inet_csk(sk);  
        u32 now;  
        /* 接收到了数据，设置ACK需调度标志*/  
        inet_csk_schedule_ack(sk);  
      
        tcp_measure_rcv_mss(sk, skb);  
      
        tcp_rcv_rtt_measure(tp);  
      
        now = tcp_time_stamp;  
        /* 以下为根据接收间隔更新icsk_ack.ato，该值主要用于判断pingpong模式见函数tcp_event_data_sent */  
        if (!icsk->icsk_ack.ato) {  
            /* The _first_ data packet received, initialize 
             * delayed ACK engine. 
             */  
            tcp_incr_quickack(sk);  
            icsk->icsk_ack.ato = TCP_ATO_MIN;  
        } else {  
            int m = now - icsk->icsk_ack.lrcvtime;  
      
            if (m <= TCP_ATO_MIN / 2) {  
                /* The fastest case is the first. */  
                icsk->icsk_ack.ato = (icsk->icsk_ack.ato >> 1) + TCP_ATO_MIN / 2;  
            } else if (m < icsk->icsk_ack.ato) {  
                icsk->icsk_ack.ato = (icsk->icsk_ack.ato >> 1) + m;  
                if (icsk->icsk_ack.ato > icsk->icsk_rto)  
                    icsk->icsk_ack.ato = icsk->icsk_rto;  
            } else if (m > icsk->icsk_rto) {  
                /* Too long gap. Apparently sender failed to 
                 * restart window, so that we send ACKs quickly. 
                 */  
                tcp_incr_quickack(sk);  
                sk_mem_reclaim(sk);  
            }  
        }  
        icsk->icsk_ack.lrcvtime = now;  
      
        TCP_ECN_check_ce(tp, skb);  
        /* 每次接收到来自对方的一个TCP数据报，且数据报长度大于128字节时，我们需要调用tcp_grow_window，增加rcv_ssthresh的值，一般每次为rcv_ssthresh增长两倍的mss，增加的条件是rcv_ssthresh小于window_clamp,并且 rcv_ssthresh小于接收缓存剩余空间的3/4，同时tcp_memory_pressure没有被置位(即接收缓存中的数据量没有太大)。 tcp_grow_window中对新收到的skb的长度还有一些限制，并不总是增长rcv_ssthresh的值*/  
        if (skb->len >= 128)  
            tcp_grow_window(sk, skb);  
    }  
```

rcv_ssthresh是当前的接收窗口大小的一个阀值，其初始值就置为rcv_wnd。它跟rcv_wnd配合工作，当本地socket收到数据报，并满足一定条件时，增长rcv_ssthresh的值，在下一次发送数据报组建TCP首部时，需要通告对方当前的接收窗口大小，这时需要更新rcv_wnd，此时rcv_wnd的取值不能超过rcv_ssthresh的值。两者配合，达到一个滑动窗口大小缓慢增长的效果。

`__tcp_ack_snd_check`用来判断ACK的发送方式
```
    /* 
     * Check if sending an ack is needed. 
     */  
    static void __tcp_ack_snd_check(struct sock *sk, int ofo_possible)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
      
            /* More than one full frame received... */  
        if (((tp->rcv_nxt - tp->rcv_wup) > inet_csk(sk)->icsk_ack.rcv_mss  
             /* ... and right edge of window advances far enough. 
              * (tcp_recvmsg() will send ACK otherwise). Or... 
              */  
             && __tcp_select_window(sk) >= tp->rcv_wnd) ||  
            /* We ACK each frame or... */  
            tcp_in_quickack_mode(sk) ||  
            /* We have out of order data. */  
            (ofo_possible && skb_peek(&tp->out_of_order_queue))) {  
            /* Then ack it now */  
            tcp_send_ack(sk);  
        } else {  
            /* Else, send delayed ack. */  
            tcp_send_delayed_ack(sk);  
        }  
    }  
```

这里有个疑问，就是当ucopy应用读到需要读取到的数据包后，也即在一次处理中
```
    if (tp->copied_seq == tp->rcv_nxt &&  
                    len - tcp_header_len <= tp->ucopy.len) {  
```

的第二个条件的等号为真 len - tcp_header_len == tp->ucopy.len，然后执行流程到后面eaten为1，所以函数以释放skb结束，没有调用sk_data_ready函数。假设这个处理调用流程如下：  
tcp_recvmsg-> sk_wait_data  -> sk_wait_event -> release_sock -> __release_sock-> sk_backlog_rcv-> tcp_rcv_established那么即使此时用户得到了所需的数据，但是在tcp_rcv_established返回前没有提示数据已得到，
```
    #define sk_wait_event(__sk, __timeo, __condition)           /  
        ({  int __rc;                       /  
            release_sock(__sk);                 /  
            __rc = __condition;                 /  
            if (!__rc) {                        /  
                *(__timeo) = schedule_timeout(*(__timeo));  /  
            }                           /  
            lock_sock(__sk);                    /  
            __rc = __condition;                 /  
            __rc;                           /  
        })  
```

但是在回到sk_wait_event后，由于__condition为 !skb_queue_empty(&sk->sk_receive_queue)，所以还是会调用schedule_timeout来等待。这点显然是浪费时间，所以这个condition应该考虑下这个数据已经读满的情况，而不能光靠观察receive queue来判断是否等待。

接下来分析slow path
```
    slow_path:  
        if (len < (th->doff << 2) || tcp_checksum_complete_user(sk, skb))  
            goto csum_error;  
      
        /* 
         *  Standard slow path. 
         */  
            /* 检查到达的数据包 */  
        res = tcp_validate_incoming(sk, skb, th, 1);  
        if (res <= 0)  
            return -res;  
      
    step5:  /* 如果设置了ACK，则调用tcp_ack处理，后面再分析该函数*/  
        if (th->ack)  
            tcp_ack(sk, skb, FLAG_SLOWPATH);  
      
        tcp_rcv_rtt_measure_ts(sk, skb);  
      
        /* Process urgent data. */  
        tcp_urg(sk, skb, th);  
      
        /* step 7: process the segment text */  
        tcp_data_queue(sk, skb);  
              
        tcp_data_snd_check(sk);  
        tcp_ack_snd_check(sk);  
        return 0;  
```

先看看tcp_validate_incoming函数，在slow path处理前检查输入数据包的合法性。

```
    /* Does PAWS and seqno based validation of an incoming segment, flags will 
     * play significant role here. 
     */  
    static int tcp_validate_incoming(struct sock *sk, struct sk_buff *skb,  
                      struct tcphdr *th, int syn_inerr)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
      
        /* RFC1323: H1. Apply PAWS check first. */  
        if (tcp_fast_parse_options(skb, th, tp) && tp->rx_opt.saw_tstamp &&  
            tcp_paws_discard(sk, skb)) {  
            if (!th->rst) {  
                NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_PAWSESTABREJECTED);  
                tcp_send_dupack(sk, skb);  
                goto discard;  
            }  
            /* Reset is accepted even if it did not pass PAWS. */  
        }  
      
        /* Step 1: check sequence number */  
        if (!tcp_sequence(tp, TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq)) {  
            /* RFC793, page 37: "In all states except SYN-SENT, all reset 
             * (RST) segments are validated by checking their SEQ-fields." 
             * And page 69: "If an incoming segment is not acceptable, 
             * an acknowledgment should be sent in reply (unless the RST 
             * bit is set, if so drop the segment and return)". 
             */  
            if (!th->rst)  
                tcp_send_dupack(sk, skb);  
            goto discard;  
        }  
      
        /* Step 2: check RST bit */  
        if (th->rst) {  
            tcp_reset(sk);  
            goto discard;  
        }  
      
        /* ts_recent update must be made after we are sure that the packet 
         * is in window. 
         */  
        tcp_replace_ts_recent(tp, TCP_SKB_CB(skb)->seq);  
      
        /* step 3: check security and precedence [ignored] */  
      
        /* step 4: Check for a SYN in window. */  
        if (th->syn && !before(TCP_SKB_CB(skb)->seq, tp->rcv_nxt)) {  
            if (syn_inerr)  
                TCP_INC_STATS_BH(sock_net(sk), TCP_MIB_INERRS);  
            NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPABORTONSYN);  
            tcp_reset(sk);  
            return -1;  
        }  
      
        return 1;  
      
    discard:  
        __kfree_skb(skb);  
        return 0;  
    }  
```

第一步：检查PAWS tcp_paws_discard
```
    static inline int tcp_paws_discard(const struct sock *sk,  
                       const struct sk_buff *skb)  
    {  
        const struct tcp_sock *tp = tcp_sk(sk);  
        return ((s32)(tp->rx_opt.ts_recent - tp->rx_opt.rcv_tsval) > TCP_PAWS_WINDOW &&  
            get_seconds() < tp->rx_opt.ts_recent_stamp + TCP_PAWS_24DAYS &&  
            !tcp_disordered_ack(sk, skb));  
    }  
```
PAWS丢弃数据包要满足以下条件

1 The difference between the timestamp value obtained in the current segmentand last seen timestamp on the incoming TCP segment should be more than TCP_PAWS_WINDOW (= 1), which means that if the segment that was transmitted 1 clock tick before the segment that reached here earlier TCP seq should be acceptable.  
It may be because of reordering of the segments that the latter reached earlier.  
2 the 24 days have not elapsed since last time timestamp was stored,  
3 tcp_disordered_ack返回0.  

以下转载自CU论坛http://linux.chinaunix.net/bbs/viewthread.php?tid=1130308
----------
在实际进行PAWS预防时，Linux是通过如下代码调用来完成的
```
tcp_rcv_established  
    |  
    |-->tcp_paws_discard  
          |  
          |-->tcp_disordered_ack  
```

其中关键是local方通过tcp_disordered_ack函数对一个刚收到的数据分段进行判断，下面我们对该函数的判断逻辑进行下总结：  
大前提：该收到分段的TS值表明有回绕现象发生  
a）若该分段不是一个纯ACK，则丢弃。因为显然这个分段所携带的数据是一个老数据了，不是local方目前希望接收的（参见PAWS的处理依据一节）  
b）若该分段不是local所希望接收的，则丢弃。这个原因很显然  
c）若该分段是一个纯ACK，但该ACK并不是一个重复ACK（由local方后续数据正确到达所引发的），则丢弃。因为显然该ACK是一个老的ACK，并不是由于为了加快local方重发而在每收到一个丢失分段后的分段而发出的ACK。  
d）若该分段是一个ACK，且为重复ACK，并且该ACK的TS值超过了local方那个丢失分段后的重发rto，则丢弃。因为显然此时local方已经重发了那个导致此重复ACK产生的分段，因此再收到此重复ACK就可以直接丢弃。  
e）若该分段是一个ACK，且为重复ACK，但是没有超过一个rto的时间，则不能丢弃，因为这正代表peer方收到了local方发出的丢失分段后的分段，local方要对此ACK进行处理（例如立刻重传）

  这里有一个重要概念需要理解，即在出现TS问题后，纯ACK和带ACK的数据分段二者是显著不同的，对于后者，可以立刻丢弃掉，因为从一个窗口的某个seq到下一个窗口的同一个seq过程中，一定有窗口变化曾经发生过，从而TS记录值ts_recent也一定更新过，此时一定可以通过PAWS进行丢弃处理。但是对于前者，一个纯ACK，就不能简单丢弃了，因为有这样一个现象是合理的，即假定local方的接收缓存很大，并且peer方在发送时很快就回绕了，于是在local方的某个分段丢失后，peer方需要在每收到的后续分段时发送重复ACK，而此时该重发ACK的ack_seq就是这个丢失分段的序号，而该重发ACK的seq已经是回绕后的重复序号了，尽管此时到底是回绕后的那个重复ACK还是之前的那个同样序号seq的重复ACK，对于local方来都需要处理（立刻启动重发动作），而不能简单丢弃掉。

----------
第2步 检查数据包的序号是否正确，该判断失败后调用tcp_send_dupack发送一个duplicate acknowledge（未设置RST标志位时）。
```
    static inline int tcp_sequence(struct tcp_sock *tp, u32 seq, u32 end_seq)  
    {  
        return  !before(end_seq, tp->rcv_wup) &&  
            !after(seq, tp->rcv_nxt + tcp_receive_window(tp));  
    }  
```

由rcv_wup的更新时机（发送ACK时的tcp_select_window）可知位于序号rcv_wup前面的数据都已确认，所以待检查数据包的结束序号至少要大于该值；同时开始序号要落在接收窗口内。

第3步 如果设置了RST，则调用tcp_reset处理

第4步 更新ts_recent，

第5步 检查SYN，因为重发的SYN和原来的SYN之间不会发送数据，所以这2个SYN的序号是相同的，如果不满足则reset连接。


