---
layout: post
title: "TCP拥塞状态机的实现tcp_fastretrans_alert"
date: 2015-03-23 14:03:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
[TCP拥塞状态机的实现（上）](http://blog.csdn.net/zhangskd/article/details/8260873)  
[TCP拥塞状态机的实现（中）](http://blog.csdn.net/zhangskd/article/details/8283687)  
[TCP拥塞状态机的实现（下）](http://blog.csdn.net/zhangskd/article/details/8283689)  

--------------

### TCP拥塞状态机的实现（上）
内容：本文主要分析TCP拥塞状态机的实现中，主体函数tcp_fastretrans_alert()的实现。接下来的文章会对其中重要的部分进行更具体的分析。

内核版本：2.6.37

#### 原理
先来看一下涉及到的知识。

##### 拥塞状态：
（1）Open：Normal state, no dubious events, fast path.  
（2）Disorder：In all respects it is Open, but requres a bit more attention.  
          It is entered when we see some SACKs or dupacks. It is split of Open mainly to move some processing from fast path to slow one.  
（3）CWR：cwnd was reduced due to some Congestion Notification event.  
          It can be ECN, ICMP source quench, local device congestion.  
（4）Recovery：cwnd was reduced, we are fast-retransmitting.  
（5）Loss：cwnd was reduced due to RTO timeout or SACK reneging.  

##### tcp_fastretrans_alert() is entered：
（1）each incoming ACK, if state is not Open  
（2）when arrived ACK is unusual, namely:  
          SACK  
          Duplicate ACK  
          ECN ECE  

##### Counting packets in flight is pretty simple.
（1）in_flight = packets_out - left_out + retrans_out  
packets_out is SND.NXT - SND.UNA counted in packets.   
retrans_out is number of retransmitted segments.  
left_out is number of segments left network, but not ACKed yet.  

（2）left_out = sacked_out + lost_out  
sacked_out：Packets, which arrived to receiver out of order and hence not ACKed. With SACK this number is simply amount of SACKed data. Even without SACKs it is easy to give pretty reliable estimate of this number, counting duplicate ACKs.

（3）lost_out：Packets lost by network. TCP has no explicit loss notification feedback from network(for now). It means that this number can be only guessed. Actually, it is the heuristics to predict lossage that distinguishes different algorithms.  
F.e. after RTO, when all the queue is considered as lost, lost_out = packets_out and in_flight = retrans_out.

##### Essentially, we have now two algorithms counting lost packets.
1）FACK：It is the simplest heuristics. As soon as we decided that something is lost, we decide that all not SACKed packets until the most forward SACK are lost. I.e.  
lost_out = fackets_out - sacked_out and left_out = fackets_out  
It is absolutely correct estimate, if network does not reorder packets. And it loses any connection to reality when reordering takes place. We use FACK by defaut until reordering is suspected on the path to this destination.

2）NewReno：when Recovery is entered, we assume that one segment is lost (classic Reno). While we are in Recovery and a partial ACK arrives, we assume that one more packet is lost (NewReno).  
This heuristics are the same in NewReno and SACK.   
Imagine, that's all! Forget about all this shamanism about CWND inflation deflation etc. CWND is real congestion window, never inflated, changes only according to classic VJ rules. 

Really tricky (and requiring careful tuning) part of algorithm is hidden in functions tcp_time_to_recover() and tcp_xmit_retransmit_queue().

##### tcp_time_to_recover()
It determines the moment when we should reduce cwnd and, hence, slow down forward transmission. In fact, it determines the moment when we decide that hole is caused by loss, rather than by a reorder.


##### tcp_xmit_retransmit_queue()
It decides what we should retransmit to fill holes, caused by lost packets.

##### undo heuristics
And the most logically complicated part of algorithm is undo heuristics. We detect false retransmits due to both too early fast retransmit (reordering) and underestimated RTO, analyzing timestamps and D-SACKs. When we detect that some segments were retransmitted by mistake and CWND reduction was wrong, we undo window reduction and abort recovery phase. This logic is hidden inside several functions named tcp_try_undo_<something>.

#### 主体函数 
TCP拥塞状态机主要是在tcp_fastretrans_alert()中实现的，tcp_fastretrans_alert()在tcp_ack()中被调用。

此函数分成几个阶段：  
A. FLAG_ECE，收到包含ECE标志的ACK。  
B. reneging SACKs，ACK指向已经被SACK的数据段。如果是此原因，进入超时处理，然后返回。  
C. state is not Open，发现丢包，需要标志出丢失的包，这样就知道该重传哪些包了。  
D. 检查是否有错误( left_out > packets_out)。  
E. 各个状态是怎样退出的，当snd_una >= high_seq时候。  
F. 各个状态的处理和进入。  

下文会围绕这几个阶段进行具体分析。
```
	/* Process an event, which can update packets-in-flight not trivially.
	 * Main goal of this function is to calculate new estimate for left_out,
	 * taking into account both packets sitting in receiver's buffer and
	 * packets lost by network. 
	 * 
	 * Besides that it does CWND reduction, when packet loss is detected
	 * and changes state of machine.
	 *
	 * It does not decide what to send, it is made in function
	 * tcp_xmit_retransmit_queue().
	 */

	/* 此函数被调用的条件：
	 * (1) each incoming ACK, if state is not Open
	 * (2) when arrived ACK is unusual, namely:
	 *       SACK
	 *       Duplicate ACK
	 *       ECN ECE
	 */

	static void tcp_fastretrans_alert(struct sock *sk, int pkts_acked, int flag)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_sock *tp = tcp_sk(sk);

		/* 判断是不是重复的ACK*/
		int is_dupack = ! (flag & (FLAG_SND_UNA_ADVANCED | FLAG_NOT_DUP));

		/* tcp_fackets_out()返回hole的大小，如果大于reordering，则认为发生丢包.*/
		int do_lost = is_dupack || ((flag & FLAG_DATA_SACKED) && 
		                            (tcp_fackets_out(tp) > tp->reordering ));

		int fast_rexmit = 0, mib_idx;

		/* 如果packet_out为0，那么不可能有sacked_out */
		if (WARN_ON(!tp->packets_out && tp->sacked_out))
		    tp->sacked_out = 0;

		/* fack的计数至少需要依赖一个SACK的段.*/
		if (WARN_ON(!tp->sacked_out && tp->fackets_out))
		    tp->fackets_out = 0;
	 
		/* Now state machine starts.
		 * A. ECE, hence prohibit cwnd undoing, the reduction is required. 
		 * 禁止拥塞窗口撤销，并开始减小拥塞窗口。
		 */
		if (flag & FLAG_ECE)
		    tp->prior_ssthresh = 0;
		
		/* B. In all the states check for reneging SACKs. 
		 * 检查是否为虚假的SACK，即ACK是否确认已经被SACK的数据.
		 */
		if (tcp_check_sack_reneging(sk, flag))
		    return;
		 
		/* C. Process data loss notification, provided it is valid. 
		 * 为什么需要这么多个条件？不太理解。
		 * 此时不在Open态，发现丢包，需要标志出丢失的包。
		  */
		if (tcp_is_fack(tp) && (flag & FLAG_DATA_LOSS) &&
		    before(tp->snd_una, tp->high_seq) &&
		    icsk->icsk_ca_state != TCP_CA_Open &&
		    tp->fackets_out > tp->reordering) {
		    tcp_mark_head_lost(sk, tp->fackets_out - tp->reordering, 0);
		    NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPLOSS);
		    }

		/* D. Check consistency of the current state. 
		 * 确定left_out < packets_out
		 */
		tcp_verify_left_out(tp); 

		/* E. Check state exit conditions. State can be terminated 
		 * when high_seq is ACKed. */
		if (icsk->icsk_ca_state == TCP_CA_Open) {
		    /* 在Open状态，不可能有重传且尚未确认的段*/
		    WARN_ON(tp->retrans_out != 0);
		    /* 清除上次重传阶段第一个重传段的发送时间*/
		    tp->retrans_stamp = 0;

		} else if (!before(tp->snd_una, tp->high_seq) {/* high_seq被确认了*/
		    switch(icsk->icsk_ca_state) {
		        case TCP_CA_Loss:
		            icsk->icsk_retransmits = 0; /*超时重传次数归0*/ 

		            /*不管undo成功与否，都会返回Open态，除非没有使用SACK*/
		            if (tcp_try_undo_recovery(sk)) 
		                return;
		            break;
	 
		        case TCP_CA_CWR:
		            /* CWR is to be held someting *above* high_seq is ACKed
		             * for CWR bit to reach receiver.
		             * 需要snd_una > high_seq才能撤销
		               */
		            if (tp->snd_una != tp->high_seq) {
		                tcp_complete_cwr(sk);
		                tcp_set_ca_state(sk, TCP_CA_Open);
		            }
		            break;

		        case TCP_CA_Disorder:
		            tcp_try_undo_dsack(sk);
		             /* For SACK case do not Open to allow to undo
		              * catching for all duplicate ACKs.?*/
		            if (!tp->undo_marker || tcp_is_reno(tp) || 
		                tp->snd_una != tp->high_seq) {
		                tp->undo_marker = 0;
		                tcp_set_ca_state(sk, TCP_CA_Open);
		            }

		        case TCP_CA_Recovery:
		            if (tcp_is_reno(tp))
		                tcp_reset_reno_sack(tp)); /* sacked_out清零*/

		            if (tcp_try_undo_recovery(sk))
		                return;

		            tcp_complete_cwr(sk);
		            break;
		    }
		}

		/* F. Process state. */
		switch(icsk->icsk_ca_state) {
		    case TCP_CA_Recovery:
		        if (!(flag & FLAG_SND_UNA_ADVANCED)) {
		            if (tcp_is_reno(tp) && is_dupack)
		                tcp_add_reno_sack(sk); /* 增加sacked_out ，检查是否出现reorder*/
		        } else 
		            do_lost = tcp_try_undo_partial(sk, pkts_acked);
		        break;

		    case TCP_CA_Loss:
		        /* 收到partical ack，超时重传的次数归零*/
		        if (flag & FLAG_DATA_ACKED)
		            icsk->icsk_retransmits = 0;

		        if (tcp_is_reno(tp) && flag & FLAG_SND_UNA_ADVANCED)
		            tcp_reset_reno_sack(tp); /* sacked_out清零*/

		        if (!tcp_try_undo_loss(sk)) { /* 尝试撤销拥塞调整，进入Open态*/
		            /* 如果不能撤销，则继续重传标志为丢失的包*/
		            tcp_moderate_cwnd(tp);
		            tcp_xmit_retransmit_queue(sk); /* 待看*/
		           return;
		        }

		        if (icsk->icsk_ca_state != TCP_CA_Open)
		            return;
	 
		    /* Loss is undone; fall through to process in Open state.*/
		    default:
		        if (tcp_is_reno(tp)) {
		            if (flag & FLAG_SND_UNA_ADVANCED)
		               tcp_reset_reno_sack(tp);

		            if (is_dupack)
		               tcp_add_reno_sack(sk);
		        }

		        if (icsk->icsk_ca_state == TCP_CA_Disorder)
		            tcp_try_undo_dsack(sk); /*D-SACK确认了所有重传的段*/
		         
		        /* 判断是否应该进入Recovery状态*/
		        if (! tcp_time_to_recover(sk)) {
		           /*此过程中，会判断是否进入Open、Disorder、CWR状态*/
		            tcp_try_to_open(sk, flag); 
		            return;
		        }

		        /* MTU probe failure: don't reduce cwnd */
		        /* 关于MTU探测部分此处略过！*/
		        ......

		        /* Otherwise enter Recovery state */
		        if (tcp_is_reno(tp))
		            mib_idx = LINUX_MIB_TCPRENORECOVERY;
		        else
		            mib_idx = LINUX_MIB_TCPSACKRECOVERY;

		         NET_INC_STATS_BH(sock_net(sk), mib_idx);

		        /* 进入Recovery状态前，保存那些用于恢复的数据*/
		        tp->high_seq = tp->snd_nxt; /* 用于判断退出时机*/
		        tp->prior_ssthresh = 0;
		        tp->undo_marker = tp->snd_una;
		        tp->undo_retrans=tp->retrans_out;
	 
		       if (icsk->icsk_ca_state < TCP_CA_CWR) {
		           if (! (flag & FLAG_ECE))
		               tp->prior_ssthresh = tcp_current_ssthresh(sk); /*保存旧阈值*/
		           tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk);/*更新阈值*/
		           TCP_ECN_queue_cwr(tp);
		       }

		       tp->bytes_acked = 0;
		       tp->snd_cwnd_cnt = 0;

		       tcp_set_ca_state(sk, TCP_CA_Recovery); /* 进入Recovery状态*/
		       fast_rexmit = 1; /* 快速重传标志 */
		}

		if (do_lost || (tcp_is_fack(tp) && tcp_head_timeout(sk)))
		    /* 更新记分牌，标志丢失和超时的数据包，增加lost_out */
		    tcp_update_scoreboard(sk, fast_rexmit); 

		/* 减小snd_cwnd */
		tcp_cwnd_down(sk, flag);
		tcp_xmit_retransmit_queue(sk);
	}
```

#### flag标志
```
    #define FLAG_DATA 0x01  /* Incoming frame contained data. */  
    #define FLAG_WIN_UPDATE 0x02  /* Incoming ACK was a window update. */  
    #define FLAG_SND_UNA_ADVANCED 0x400  /* snd_una was changed (!= FLAG_DATA_ACKED) */  
    #define FLAG_DATA_SACKED 0x20  /* New SACK. */  
    #define FLAG_ECE 0x40  /* ECE in this ACK */  
    #define FLAG_SACK_RENEGING 0x2000  /* snd_una advanced to a sacked seq */  
    #define FLAG_DATA_LOST  /* SACK detected data lossage. */  
       
    #define FLAG_DATA_ACKED 0x04  /* This ACK acknowledged new data. */  
    #define FLAG_SYN_ACKED 0x10    /* This ACK acknowledged SYN. */  
    #define FLAG_ACKED (FLAG_DATA_ACKED | FLAG_SYN_ACKED)  
       
    #define FLAG_NOT_DUP (FLAG_DATA | FLAG_WIN_UPDATE | FLAG_ACKED)  /* 定义非重复ACK*/  
       
    #define FLAG_FORWARD_PROGRESS (FLAG_ACKED | FLAG_DATA_SACKED)  
    #define FLAG_ANY_PROGRESS (FLAG_FORWARD_PROGRESS | FLAG_SND_UNA_ADVANCED)  
    #define FLAG_DSACKING_ACK 0x800  /* SACK blocks contained D-SACK info */  
      
    struct tcp_sock {  
        ...  
        u32 retrans_out; /*重传还未得到确认的TCP段数目*/  
        u32 retrans_stamp; /* 记录上次重传阶段，第一个段的发送时间，用于判断是否可以进行拥塞调整撤销*/  
      
        struct sk_buff *highest_sack; /* highest skb with SACK received,  
                                       *(validity guaranteed only if sacked_out > 0)  
                                       */  
       ...  
    }  
       
    struct inet_connection_sock {  
        ...  
        __u8 icks_retransmits; /* 记录超时重传的次数*/  
        ...  
    }
```

#### SACK/ RENO/ FACK是否启用
```
    /* These function determine how the currrent flow behaves in respect of SACK 
     * handling. SACK is negotiated with the peer, and therefore it can very between 
     * different flows. 
     * 
     * tcp_is_sack - SACK enabled 
     * tcp_is_reno - No SACK 
     * tcp_is_fack - FACK enabled, implies SACK enabled 
     */  
      
    static inline int tcp_is_sack (const struct tcp_sock *tp)  
    {  
            return tp->rx_opt.sack_ok; /* SACK seen on SYN packet */  
    }  
      
    static inline int tcp_is_reno (const struct tcp_sock *tp)  
    {  
            return ! tcp_is_sack(tp);  
    }  
      
    static inline int tcp_is_fack (const struct tcp_sock *tp)  
    {  
            return tp->rx_opt.sack_ok & 2;  
    }  
       
    static inline void tcp_enable_fack(struct tcp_sock *tp)  
    {  
            tp->rx_opt.sack_ok |= 2;  
    }  
       
    static inline int tcp_fackets_out(const struct tcp_sock *tp)  
    {  
            return tcp_is_reno(tp) ? tp->sacked_out +1 : tp->fackets_out;  
    }
```

（1）如果启用了FACK，那么fackets_out = left_out  
           fackets_out = sacked_out + loss_out  
           所以：loss_out = fackets_out - sacked_out  
          这是一种比较激进的丢包估算，即FACK。

（2）如果没启用FACK，那么就假设只丢了一个数据包，所以left_out = sacked_out + 1  
         这是一种较为保守的做法，当出现大量丢包时，这种做法会出现问题。 

--------------

### TCP拥塞状态机的实现（中）

内容：本文主要分析TCP拥塞状态机的实现中，虚假SACK的处理、标志丢失数据包的详细过程。  
内核版本：2.6.37

#### 虚假SACK
state B

如果接收的ACK指向已记录的SACK，这说明记录的SACK并没有反应接收方的真实的状态，也就是说接收方现在已经处于严重拥塞的状态或者在处理上有bug，所以接下来就按照超时重传的方式去处理。因为按照正常的逻辑流程，接收的ACK不应该指向已记录的SACK，而应该指向SACK后面未接收的地方。通常情况下，此时接收方已经删除了保存到失序队列中的段。

```
    /* If ACK arrived pointing to a remembered SACK, it means that our remembered 
     * SACKs do not reflect real state of receiver i.e. receiver host is heavily congested 
     * or buggy. 
     * 
     * Do processing similar to RTO timeout. 
     */  
      
    static int tcp_check_sack_reneging (struct sock *sk, int flag)  
    {  
        if (flag & FLAG_SACK_RENEGING) {  
            struct inet_connection_sock *icsk = inet_csk(sk);  
            /* 记录mib信息，供SNMP使用*/  
            NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPSACKRENEGING);  
              
            /* 进入loss状态，1表示清除SACKED标志*/  
            tcp_enter_loss(sk, 1);  /* 此函数在前面blog中分析过：）*/  
              
            icsk->icsk_retransmits++; /* 未恢复的RTO加一*/  
       
            /* 重传发送队列中的第一个数据包*/  
            tcp_retransmit_skb(sk, tcp_write_queue_head(sk));   
       
            /* 更新超时重传定时器*/  
            inet_csk_reset_xmit_timer(sk, ICSK_TIME_RETRANS,   
                                         icsk->icsk_rto, TCP_RTO_MAX);  
            return 1;  
        }  
        return 0;  
    }  
      
    /** 用于返回发送队列中的第一个数据包，或者NULL 
     * skb_peek - peek at the head of an &sk_buff_head 
     * @list_ : list to peek at  
     * 
     * Peek an &sk_buff. Unlike most other operations you must 
     * be careful with this one. A peek leaves the buffer on the 
     * list and someone else may run off with it. You must hold 
     * the appropriate locks or have a private queue to do this. 
     * 
     * Returns %NULL for an empty list or a pointer to the head element. 
     * The reference count is not incremented and the reference is therefore 
     * volatile. Use with caution. 
     */  
      
    static inline struct sk_buff *skb_peek (const struct sk_buff_head *list_)  
    {  
        struct sk_buff *list = ((const struct sk_buff *) list_)->next;  
        if (list == (struct sk_buff *) list_)  
            list = NULL;  
        return list;  
    }  
      
    static inline struct sk_buff *tcp_write_queue_head(const struct sock *sk)  
    {  
        return skb_peek(&sk->sk_write_queue);  
    }
```

tcp_retransmit_skb()用来重传一个数据包。它最终调用tcp_transmit_skb()来发送一个数据包。这个函数在接下来的blog中会分析。

#### 重设重传定时器
state B

```
    /** inet_connection_sock - INET connection oriented sock 
     * 
     * @icsk_timeout: Timeout 
     * @icsk_retransmit_timer: Resend (no ack) 
     * @icsk_rto: Retransmission timeout 
     * @icsk_ca_ops: Pluggable congestion control hook 
     * @icsk_ca_state: Congestion control state 
     * @icsk_ca_retransmits: Number of unrecovered [RTO] timeouts 
     * @icsk_pending: scheduled timer event 
     * @icsk_ack: Delayed ACK control data 
     */  
      
    struct inet_connection_sock {  
        ...  
        unsigned long icsk_timeout; /* 数据包超时时间*/  
        struct timer_list icsk_retransmit_timer; /* 重传定时器*/  
        struct timer_list icsk_delack_timer; /* delay ack定时器*/  
        __u32 icsk_rto; /*超时时间*/  
        const struct tcp_congestion ops *icsk_ca_ops; /*拥塞控制算法*/  
        __u8 icsk_ca_state; /*所处拥塞状态*/  
        __u8 icsk_retransmits; /*还没恢复的timeout个数*/  
        __u8 icsk_pending; /* 等待的定时器事件*/  
        ...  
        struct {  
           ...  
            __u8 pending; /* ACK is pending */  
            unsigned long timeout; /* Currently scheduled timeout */  
            ...  
        } icsk_ack; /* Delayed ACK的控制模块*/  
        ...  
        u32 icsk_ca_priv[16]; /*放置拥塞控制算法的参数*/  
        ...  
    #define ICSK_CA_PRIV_SIZE (16*sizeof(u32))  
    }  
       
    #define ICSK_TIME_RETRANS 1 /* Retransmit timer */  
    #define ICSK_TIME_DACK 2 /* Delayed ack timer */  
    #define ICSK_TIME_PROBE0 3 /* Zero window probe timer */  
      
    /* 
     * Reset the retransmissiion timer 
     */  
    static inline void inet_csk_reset_xmit_timer(struct sock *sk, const int what,  
                                                unsigned long when,  
                                                const unsigned long max_when)  
    {  
        struct inet_connection_sock *icsk = inet_csk(sk);  
      
        if (when > max_when) {  
    #ifdef INET_CSK_DEBUG  
            pr_debug("reset_xmit_timer: sk=%p %d when=0x%lx, caller=%p\n",  
                        sk, what, when, current_text_addr());  
    #endif  
            when = max_when;  
        }  
        if (what == ICSK_TIME_RETRANS || what == ICSK_TIME_PROBE0) {  
            icsk->icsk_pending = what;  
            icsk->icsk_timeout = jiffies + when; /*数据包超时时刻*/  
            sk_reset_timer(sk, &icsk->icsk_retransmit_timer, icsk->icsk_timeout);  
        } else if (what == ICSK_TIME_DACK) {  
            icsk->icsk_ack.pending |= ICSK_ACK_TIMER;  
            icsk->icsk_ack.timeout = jiffies + when; /*Delay ACK定时器超时时刻*/  
            sk_reset_timer(sk, &icsk->icsk_delack_timer, icsk->icsk_ack.timeout);  
        }  
    #ifdef INET_CSK_DEBUG  
        else {  
            pr_debug("%s", inet_csk_timer_bug_msg);  
        }    
    #endif       
    }
```

#### 添加LOST标志
state C

Q: 我们发现有数据包丢失了，怎么知道要重传哪些数据包呢？  
A: tcp_mark_head_lost()通过给丢失的数据包标志TCPCB_LOST，就可以表明哪些数据包需要重传。  
如果通过SACK发现有段丢失，则需要从重传队首或上次标志丢失段的位置开始，为记分牌为0的段添加LOST标志，直到所有被标志LOST的段数达到packets或者被标志序号超过high_seq为止。

```
    /* Mark head of queue up as lost. With RFC3517 SACK, the packets is against sakced cnt, 
     * otherwise it's against fakced cnt. 
     * packets = fackets_out - reordering，表示sacked_out和lost_out的总和。 
     * 所以，被标志为LOST的段数不能超过packets。 
     * high_seq : 可以标志为LOST的段序号的最大值。 
     * mark_head: 为1表示只需要标志发送队列的第一个段。 
     */  
      
    static void tcp_mark_head_lost(struct sock *sk, int packets, int mark_head)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        struct sk_buff *skb;  
        int cnt, oldcnt;  
        int err;  
        unsigned int mss;  
      
        /* 被标志为丢失的段不能超过发送出去的数据段数*/  
        WARN_ON(packets > tp->packets_out);  
      
        /* 如果已经有标识为丢失的段了*/  
        if (tp->lost_skb_hint) {  
            skb = tp->lost_skb_hint; /* 下一个要标志的段 */  
            cnt = tp->lost_cnt_hint; /* 已经标志了多少段 */  
      
            /* Head already handled? 如果发送队列第一个数据包已经标志了，则返回 */  
            if (mark_head && skb != tcp_write_queue_head(sk))  
                return;  
      
        } else {  
            skb = tcp_write_queue_head(sk);  
            cnt = 0;  
        }  
      
        tcp_for_write_queue_from(skb, sk) {  
            if (skb == tcp_send_head(sk))  
                break; /* 如果遍历到snd_nxt，则停止*/  
      
            /* 更新丢失队列信息*/  
            tp->lost_skb_hint = skb;  
            tp->lost_cnt_hint = cnt ;  
      
            /* 标志为LOST的段序号不能超过high_seq */  
            if (after(TCP_SKB_CB(skb)->end_seq, tp->high_seq))  
                break;  
      
            oldcnt = cnt;  
      
            if (tcp_is_fack(tp) || tcp_is_reno(tp) ||   
                (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED))  
                cnt += tcp_skb_pcount(skb); /* 此段已经被sacked */  
                     
            /* 主要用于判断退出时机 */  
            if (cnt > packets) {  
                if ((tcp_is_sack(tp) && !tcp_is_fack(tp) ||   
                    (TCP_SKB_CB(skb)->sacked & TCPCB_SACKED_ACKED) ||  
                    (oldcnt >= pakcets))  
      
                    break;  
      
                 mss = skb_shinfo(skb)->gso_size;  
                 err = tcp_fragment(sk, skb, (packets - oldcnt) * mss, mss);  
                 if (err < 0)  
                     break;  
                 cnt = packets;  
            }  
      
            /* 标志动作：标志一个段为LOST*/  
            tcp_skb_mark_lost(tp, skb);  
            if (mark_head)  
                break;  
        }  
        tcp_verify_left_out(tp);  
    }
```

涉及变量
```
    struct tcp_sock {  
        /* 在重传队列中，缓存下次要标志的段，为了加速对重传队列的标志操作 */  
        struct sk_buff *lost_skb_hint; /* 下一次要标志的段 */  
        int lost_cnt_hint; /* 已经标志了多少个段 */  
      
        struct sk_buff *retransmit_skb_hint; /* 表示将要重传的起始包*/  
        u32 retransmit_high; /*重传队列的最大序列号*/  
        struct sk_buff *scoreboard_skb_hint; /* 记录超时的数据包，序号最大*/  
    }
```

TCP分片函数tcp_fragment
```
    /* Function to create two new TCP segments. shrinks the given segment 
     * to the specified size and appends a new segment with the rest of the 
     * packet to the list. This won't be called frequently, I hope. 
     * Remember, these are still headerless SKBs at this point. 
     */  
      
    int tcp_fragment (struct sock *sk, struct sk_buff *skb, u32 len,  
                                    unsigned int mss_now) {}  
```

给一个段添加一个LOST标志
```
    static void tcp_skb_mark_lost(struct tcp_sock *tp, struct sk_buff *skb)  
    {  
        if (! (TCP_SKB_CB(skb)->sacked & (TCPCB_LOST | TCPCB_SACKED_ACKED))) {  
            tcp_verify_retransmit_hint(tp, skb); /* 更新重传队列*/  
            tp->lost_out += tcp_skb_pcount(skb); /*增加LOST的段数*/  
            TCP_SKB_CB(skb)->sacked |= TCPCB_LOST; /* 添加LOST标志*/  
        }  
    }  
      
    /* This must be called before lost_out is incremented */  
    static void tcp_verify_retransmit_hint(struct tcp_sock *tp, struct sk_buff *skb)  
    {  
        if ((tp->retransmit_skb_hint == NULL) ||  
             before(TCP_SKB_CB(skb)->seq,  
                           TCP_SKB_CB(tp->retransmit_skb_hint)->seq))  
        tp->retransmit_skb_hint = skb;   
       
        if (! tp->lost_out ||  
            after(TCP_SKB_CB(skb)->end_seq, tp->retransmit_high))  
            tp->retransmit_high = TCP_SKB_CB(skb)->end_seq;  
    }
```

--------------

### TCP拥塞状态机的实现（下）

内容：本文主要分析TCP拥塞状态机的实现中，各个拥塞状态的进入、处理和退出的详细过程。  
内核版本：2.6.37

#### 各状态的退出
state E

各状态的退出时机：tp->snd_una >= tp->high_seq

#####（1） Open
因为Open态是正常态，所以无所谓退出，保持原样。

#####（2）Loss
icsk->icsk_retransmits = 0; /*超时重传次数归0*/  
tcp_try_undo_recovery(sk);  

检查是否需要undo，不管undo成功与否，都返回Open态。

##### （3）CWR
If seq number greater than high_seq is acked, it indicates that the CWR indication has reached the peer TCP, call tcp_complete_cwr() to bring down the cwnd to ssthresh value.

tcp_complete_cwr(sk)中：  
tp->snd_cwnd = min(tp->snd_cwnd, tp->snd_ssthresh);

#####（4）Disorder
启用sack，则tcp_try_undo_dsack(sk)，交给它处理。否则，tp->undo_marker = 0;

#####（5）Recovery
tcp_try_undo_recovery(sk);  
在tcp_complete_cwr(sk)中：  
tp->snd_cwnd = tp->snd_ssthresh;

```
    /*cwr状态或Recovery状态结束时调用，减小cwnd*/   
      
    static inline void tcp_complete_cwr(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        tp->snd_cwnd = min(tp->snd_cwnd, tp->snd_ssthresh);  
        tp->snd_cwnd_stamp = tcp_time_stamp;  
        tcp_ca_event(sk, CA_EVENT_COMPLETE_CWR);  
    }
```

#### Recovery状态处理
state F

##### （1）收到dupack
如果收到的ACK并没有使snd_una前进、是重复的ACK，并且没有使用SACK，则：  
    sacked_out++，增加sacked数据包的个数。  
    检查是否有reordering，如果有reordering则：  
        纠正sacked_out  
        禁用FACK(画外音：这实际上是多此一举，没有使用SACK，哪来的FACK？)  
        更新tp->reordering  

```
    /* Emulate SACKs for SACKless connection: account for a new dupack.*/  
    static void tcp_add_reno_sack(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        tp->sacked_out++; /* 增加sacked数据包个数*/  
        tcp_check_reno_reordering(sk, 0); /*检查是否有reordering*/  
        tcp_verify_left_out(tp);  
    }  
       
    /* If we receive more dupacks than we expected counting segments in  
     * assumption of absent reordering, interpret this as reordering. 
     * The only another reason could be bug in receiver TCP. 
     * tcp_limit_reno_sack()是判断是否有reordering的函数。 
     */  
    static void tcp_check_reno_reordering(struct sock *sk, const int addend)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        if (tcp_limit_reno_sack(tp)) /* 检查sack是否过多*/  
            /* 如果是reordering则更新reordering信息*/  
            tcp_update_reordering(sk, tp->packets_out + addend, 0);  
    }  
       
    /* Limit sacked_out so that sum with lost_out isn't ever larger than packets_out. 
     * Returns zero if sacked_out adjustment wasn't necessary. 
     * 检查sacked_out是否过多，过多则限制，且返回1说明出现reordering了。 
     * Q: 怎么判断是否有reordering呢？ 
     * A: 我们知道dupack可能由lost引起，也有可能由reorder引起，那么如果 
     *    sacked_out + lost_out > packets_out，则说明sacked_out偏大了，因为它错误的把由reorder 
     *    引起的dupack当客户端的sack了。 
     */  
    static int tcp_limit_reno_sacked(struct tcp_sock *tp)  
    {  
        u32 holes;  
        holes = max(tp->lost_out, 1U);  
        holes = min(holes, tp->packets_out);  
        if ((tp->sacked_out + holes) > tp->packets_out) {  
            tp->sacked_out = tp->packets_out - holes;  
            return 1;  
        }  
        return 0;  
    }
```

更新reordering信息

```
    static void tcp_update_reordering(struct sock *sk, const int metric,  
                                           const int ts)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
      
        if (metric > tp->reordering) {  
            int mib_idx;  
            /* 更新reordering的值，取其小者*/  
            tp->reordering = min(TCP_MAX_REORDERING, metric);  
              
            if (ts)  
                mib_idx = LINUX_MIB_TCPTSREORDER;  
            else if (tcp_is_reno(tp))  
                mib_idx = LINUX_MIB_TCPRENOREORDER;  
            else if (tcp_is_fack(tp))  
                mib_idx = LINUX_MIB_TCPFACKREORDER;  
            else   
                mib_idx = LINUX_MIB_TCPSACKREORDER;  
      
            NET_INC_STATS_BH(sock_net(sk), mib_idx);  
    #if FASTRETRANS_DEBUG > 1  
            printk(KERN_DEBUG "Disorder%d %d %u f%u s%u rr%d\n",  
                       tp->rx_opt.sack_ok, inet_csk(sk)->icsk_ca_state,  
                       tp->reordering, tp->fackets_out, tp->sacked_out,  
                       tp->undo_marker ? tp->undo_retrans : 0);  
    #endif  
            tcp_disable_fack(tp); /* 出现了reorder，再用fack就太激进了*/  
        }  
    }  
    /* Packet counting of FACK is based on in-order assumptions, therefore 
     * TCP disables it when reordering is detected. 
     */  
      
    static void tcp_disable_fack(struct tcp_sock *tp)  
    {  
        /* RFC3517 uses different metric in lost marker => reset on change */  
        if (tcp_is_fack(tp))  
            tp->lost_skb_hint = NULL;  
        tp->rx_opt.sack_ok &= ~2; /* 取消FACK选项*/  
    }
```

##### （2）收到partical ack
do_lost = tcp_try_undo_partical(sk, pkts_acked);  
一般情况下do_lost都会为真，除非需要undo。  
具体可以看前面blog《TCP拥塞窗口调整撤销剖析》。


##### （3）跳出F state，标志丢失的数据段
执行完(1)或(2)后，就跳出F state。  
如果有丢失的数据包，或者发送队列的第一个数据包超时，则调用tcp_update_scoreboard()来更新记分牌，给丢失的段加TCPCB_LOST标志，增加lost_out。

检查发送队列的第一个数据包是否超时。

```
    /* 检验发送队列的第一个数据包是否超时*/  
    static inline int tcp_head_timeout(const struct sock *sk)  
    {  
        const struct tcp_sock *tp = tcp_sk(sk);  
        return tp->packets_out &&   
                    tcp_skb_timeout(sk, tcp_write_queue_head(sk));  
    }  
      
    /* 检验发送队列的某个数据包是否超时*/  
    static inline int tcp_skb_timeout(const struct sock *sk,  
                     const struct sk_buff *skb)  
    {  
        return tcp_time_stamp - TCP_SKB_CB(skb)->when > inet_csk(sk)->icsk_rto;  
    }
```

为确定丢失的段更新记分牌，记分牌指的是tcp_skb_cb结构中的sacked，保存该数据包的状态信息。  
(1) 没有使用SACK，每次收到dupack或partical ack时，只能标志一个包为丢失。  

(2) 使用FACK，每次收到dupack或partical ack时，分两种情况：  
      如果lost = fackets_out - reordering <= 0，这时虽然不能排除是由乱序引起的，但是fack的思想较为激进，所以也标志一个包为丢失。  
      如果lost >0，就可以肯定有丢包，一次性可以标志lost个包为丢失。  

(3) 使用SACK，但是没有使用FACK。  
      如果sacked_upto = sacked_out - reordering，这是不能排除是由乱序引起的，除非快速重传标志fast_rexmit为真，才标志一个包为丢失。  
      如果sacked_upto > 0，就可以肯定有丢包，一次性可以标志sacked_upto个包为丢失。  

内核默认使用的是(2)。

```
    /* Account newly detected lost packet(s) */  
      
     static void tcp_update_scoreboard (struct sock *sk, int fast_rexmit)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        if (tcp_is_reno(tp)) {  
            /* 只标志第一个数据包为丢失，reno一次性只标志一个包*/  
            tcp_mark_head_lost(sk, 1, 1);  
      
        } else if (tcp_is_fack(tp)) {  
            /* 还是考虑到乱序的，对于可能是由乱序引起的部分，一次标志一个包*/  
            int lost = tp->fackets_out - tp->reordering;  
            if (lost <= 0)  
                lost = 1;  
      
            /* 因为使用了FACK，可以标志多个数据包丢失*/  
            tcp_mark_head_lost(sk, lost, 0);  
      
        } else {  
            int sacked_upto = tp->sacked_out - tp->reordering;  
            if (sacked_upto >= 0)  
                tcp_mark_head_lost(sk, sacked_upto, 0);  
      
            else if (fast_rexmit)  
                tcp_mark_head_lost(sk, 1, 1);  
        }  
      
        /* 检查发送队列中的数据包是否超时，如果超时则标志为丢失*/  
        tcp_timeout_skbs(sk);  
    }
```

检查发送队列中哪些数据包超时，并标志为丢失

```
    static void tcp_timeout_skbs(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        struct sk_buff *skb;  
      
        if (! tcp_is_fack(tp) || !tcp_head_timeout(sk))  
            return;  
      
        skb = tp->scoreboard_skb_hint;  
      
        if (tp->scoreboard_skb_hint == NULL)  
            skb = tcp_write_queue_head(sk));  
      
        tcp_for_write_queue_from(skb, sk) {  
            if (skb == tcp_send_head(sk)) /*遇到snd_nxt则停止*/  
                break;  
      
            if (!tcp_skb_timeout(sk, skb)) /* 数据包不超时则停止*/  
                break;  
      
            tcp_skb_mark_lost(tp, skb); /* 标志为LOST，并增加lost_out */  
        }  
      
        tp->scoreboard_skb_hint = skb;  
        tcp_verify_left_out(tp);  
    }
```

##### （4）减小snd_cwnd
拥塞窗口每隔一个确认段减小一个段，即每收到2个确认将拥塞窗口减1，直到拥塞窗口等于慢启动阈值为止。

```
    /* Decrease cwnd each second ack. */  
    static void tcp_cwnd_down (struct sock *sk, int flag)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        int decr = tp->snd_cwnd_cnt + 1;  
      
        if ((flag & (FLAG_ANY_PROGRESS | FLAG_DSACKING_ACK )) ||  
            (tcp_is_reno(tp) && ! (flag & FLAG_NOT_DUP))) {  
            tp->snd_cwnd_cnt = decr & 1; /* 0=>1,1=>0 */  
      
            decr >>= 1; /*与上个snd_cwnd_cnt相同，0或1*/  
      
            /* 减小cwnd */  
            if (decr && tp->snd_cwnd > tcp_cwnd_min(sk))  
                tp->snd_cwnd -= decr;  
                  
            /* 注：不太理解这句的用意。*/  
            tp->snd_cwnd = min(tp->snd_cwnd, tcp_packets_in_flight(tp) +1);  
            tp->snd_cwnd_stamp = tcp_time_stamp;  
        }  
    }  
      
    /* Lower bound on congestion window is slow start threshold 
     * unless congestion avoidance choice decides to override it. 
     */  
    static inline u32 tcp_cwnd_min(const struct sock *tp)  
    {  
        const struct tcp_congestion_ops *ca_ops = inet_csk(sk)->icsk_ca_ops;  
        return ca_ops->min_cwnd ? ca_ops->min_cwnd(sk) : tcp_sk(sk)->snd_ssthresh;  
    }
```

##### （5）重传标志为丢失的段
```
    /* This gets called after a retransmit timeout, and the initially retransmitted data is  
     * acknowledged. It tries to continue resending the rest of the retransmit queue, until  
     * either we've sent it all or the congestion window limit is reached. If doing SACK,  
     * the first ACK which comes back for a timeout based retransmit packet might feed us  
     * FACK information again. If so, we use it to avoid unnecessarily retransmissions. 
     */  
      
    void tcp_xmit_retransmit_queue (struct sock *sk) {}
```

这个函数决定着发送哪些包，比较复杂，会在之后的blog单独分析。

##### （6）什么时候进入Recovery状态
tcp_time_to_recover()是一个重要函数，决定什么时候进入Recovery状态。

```
    /* This function decides, when we should leave Disordered state and enter Recovery 
     * phase, reducing congestion window. 
     * 决定什么时候离开Disorder状态，进入Recovery状态。 
     */  
      
    static int tcp_time_to_recover(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        __u32 packets_out;  
      
        /* Do not perform any recovery during F-RTO algorithm 
         * 这说明Recovery状态不能打断Loss状态。 
         */  
        if (tp->frto_counter)  
            return 0;  
      
        /* Trick#1: The loss is proven.  
         * 如果传输过程中存在丢失段，则可以进入Recovery状态。 
         */  
        if (tp->lost_out)  
            return 1;  
       
        /* Not-A-Trick#2 : Classic rule... 
         * 如果收到重复的ACK大于乱序的阈值，表示有数据包丢失了， 
         * 可以进入到Recovery状态。 
         */  
        if (tcp_dupack_heuristics(tp) > tp->reordering)  
            return 1;  
       
        /* Trick#3 : when we use RFC2988 timer restart, fast 
         * retransmit can be triggered by timeout of queue head. 
         * 如果发送队列的第一个数据包超时，则进入Recovery状态。 
         */  
          if (tcp_is_fack(tp) && tcp_head_timeout(sk))  
             return 1;  
      
        /* Trick#4 : It is still not OK... But will it be useful to delay recovery more? 
         * 如果此时由于应用程序或接收窗口的限制而不能发包，且接收到很多的重复ACK。那么不能再等下去了， 
         * 推测发生了丢包，且马上进入Recovery状态。 
         */  
        if (packets_out <= tp->reordering &&  
            tp->sacked_out >= max_t(__u32, packets_out/2, sysctl_tcp_reordering)  
            && ! tcp_may_send_now(sk)  ) {  
            /* We have nothing to send. This connection is limited 
             * either by receiver window or by application. 
             */  
            return 1;  
        }  
      
        /* If a thin stream is detected, retransmit after first received 
         * dupack. Employ only if SACK is supported in order to avoid  
         * possible corner-case series of spurious retransmissions 
         * Use only if there are no unsent data. 
         */  
        if ((tp->thin_dupack || sysctl_tcp_thin_dupack) &&  
             tcp_stream_is_thin(tp) && tcp_dupack_heuristics(tp) > 1 &&  
             tcp_is_sack(tp) && ! tcp_send_head(sk))  
             return 1;  
      
        return 0; /*表示为假*/  
    }
```

```
    /* Heurestics to calculate number of duplicate ACKs. There's no  
     * dupACKs counter when SACK is enabled (without SACK, sacked_out 
     * is used for that purpose). 
     * Instead, with FACK TCP uses fackets_out that includes both SACKed 
     * segments up to the highest received SACK block so far and holes in 
     * between them. 
     * 
     * With reordering, holes may still be in filght, so RFC3517 recovery uses 
     * pure sacked_out (total number of SACKed segment) even though it 
     * violates the RFC that uses duplicate ACKs, often these are equal but 
     * when e.g. out-of-window ACKs or packet duplication occurs, they differ. 
     * Since neither occurs due to loss, TCP shuld really ignore them. 
     */  
    static inline int tcp_dupack_heuristics(const struct tcp_sock *tp)  
    {  
        return tcp_is_fack(tp) ? tp->fackets_out : tp->sacked_out + 1;  
    }  
      
      
    /* Determines whether this is a thin stream (which may suffer from increased 
     * latency). Used to trigger latency-reducing mechanisms. 
     */  
    static inline unsigned int tcp_stream_is_thin(struct tcp_sock *tp)  
    {  
        return tp->packets_out < 4 && ! tcp_in_initial_slowstart(tp);  
    }  
      
    #define TCP_INFINITE_SSTHRESH 0x7fffffff  
      
    static inline bool tcp_in_initial_slowstart(const struct tcp_sock *tp)  
    {  
        return tp->snd_ssthresh >= TCP_INFINITE_SSTHRESH;  
    }
```

This function examines various parameters (like number of packet lost) for TCP connection to decide whether it is the right time to move to Recovery state. It's time to recover when TCP heuristics suggest a strong possibility of packet loss in the network, the following checks are made.

总的来说，一旦确定有丢包，或者很可能丢包，就可以进入Recovery状态恢复丢包了。

可以进入Recovery状态的条件包括：  
(1) some packets are lost (lost_out is non zero)。发现有丢包。  

(2) SACK is an acknowledgement for out of order packets. If number of packets Sacked is greater than the  
      reordering metrics of the network, then loss is assumed to have happened.  
      被fack数据或收到的重复ACK，大于乱序的阈值，表明很可能发生丢包。  

(3) If the first packet waiting to be acked (head of the write Queue) has waited for time equivalent to retransmission  
      timeout, the packet is assumed to have been lost. 发送队列的第一个数据段超时，表明它可能丢失了。  

(4) If the following three conditions are true, TCP sender is in a state where no more data can be transmitted  
      and number of packets acked is big enough to assume that rest of the packets are lost in the network:  
      A: If packets in flight is less than the reordering metrics.  
      B: More than half of the packets in flight have been sacked by the receiver or number of packets sacked is more  
           than the Fast Retransmit thresh. (Fast Retransmit thresh is the number of dupacks that sender awaits before  
           fast retransmission)  
      C: The sender can not send any more packets because either it is bound by the sliding window or the application  
           has not delivered any more data to it in anticipation of ACK for already provided data.  
      我们收到很多的重复ACK，那么很可能有数据段丢失了。如果此时由于接收窗口或应用程序的限制而不能发送数据，那么我们不打算再等下去，直接进入Recovery状态。  

(5) 当检测到当前流量很小时（packets_out < 4），如果还满足以下条件：  
      A: tp->thin_dupack == 1 /* Fast retransmit on first dupack */  
           或者sysctl_tcp_thin_dupack为1，表明允许在收到第一个重复的包时就重传。  
      B: 启用SACK，且FACK或SACK的数据量大于1。  
      C: 没有未发送的数据，tcp_send_head(sk) == NULL。  
      这是一种特殊的情况，只有当流量非常小的时候才采用。  

（7）刚进入Recovery时的设置  
保存那些用于undo的数据：  
tp->prior_ssthresh = tp->snd_ssthresh; /* 保存旧阈值*/  
tp->undo_marker = tp->snd_una; /* tracking retrans started here.*/  
tp->undo_retrans = tp->retrans_out; /* Retransmitted packets out */  

保存退出点：  
tp->high_seq = tp->snd_nxt;

重置变量：  
tp->snd_ssthresh = icsk->icsk_ca_ops->ssthresh(sk);  
tp->bytes_acked = 0;  
tp->snd_cwnd_cnt = 0;  

进入Recovery状态：  
tcp_set_ca_state(sk, TCP_CA_Recovery);

#### Loss状态处理
state F

##### （1）收到partical ack
icsk->icsk_retransmits = 0; /* 超时重传的次数归零*/  
如果使用的是reno，没有使用sack，则归零tp->sacked_out。

##### （2）尝试undo
调用tcp_try_undo_loss()，当使用时间戳检测到一个不必要的重传时：  
    移除记分牌中所有段的Loss标志，从而发送新的数据而不再重传。  
    调用tcp_undo_cwr()来撤销拥塞窗口和阈值的调整。

否则：  
    tcp_moderate_cwnd()调整拥塞窗口，防止爆发式重传。  
    tcp_xmit_retransmit_queue()继续重传丢失的数据段。

#### 其它状态处理
state F

如果tcp_time_to_recover(sk)返回值为假，也就是说不能进入Recovery状态，则进行CWR、Disorder或Open状态的处理。
```
    static void tcp_try_to_open (struct sock *sk, int flag)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        tcp_verify_left_out(tp);  
      
        if (!tp->frto_conter && !tcp_any_retrans_done(sk))  
            tp->retrans_stamp = 0; /* 归零，因为不需要undo了*/  
      
        /* 判断是否需要进入CWR状态*/  
        if (flag & FLAG_ECE)  
            tcp_enter_cwr(sk, 1);  
       
        if (inet_csk(sk)->icsk_ca_state != TCP_CA_CWR) { /*没进入CWR*/  
            tcp_try_keep_open(sk); /* 尝试保持Open状态*/  
            tcp_moderate_cwnd(tp);  
      
        } else { /* 说明进入CWR状态*/  
            tcp_cwnd_down(sk, flag);/* 每2个ACK减小cwnd*/  
        }  
    }  
      
    static void tcp_try_keep_open(struct sock *sk)  
    {  
        struct tcp_sock *tp = tcp_sk(sk);  
        int state = TCP_CA_Open;  
          
        /* 是否需要进入Disorder状态*/  
        if (tcp_left_out(tp) || tcp_any_retrans_done(sk) || tp->undo_marker)  
            state = TCP_CA_Disorder;  
      
        if (inet_csk(sk)->icsk_ca_state != state) {  
            tcp_set_ca_state(sk, state);  
            tp->high_seq = tp->snd_nxt;  
        }  
    }
```

##### （1）CWR状态
Q: 什么时候进入CWR状态？  
A: 如果检测到ACK包含ECE标志，表示接收方通知发送法进行显示拥塞控制。  
```
     @tcp_try_to_open():
     if (flag & FLAG_ECE)
         tcp_enter_cwr(sk, 1);
```
tcp_enter_cwr()函数分析可见前面blog《TCP拥塞状态变迁》。  
它主要做了：  
    1. 重新设置慢启动阈值。  
    2. 清除undo需要的标志，不允许undo。  
    3. 记录此时的最高序号(high_seq = snd_nxt)，用于判断退出时机。  
    4. 添加CWR标志，用于通知接收方它已经做出反应。  
    5. 设置此时的状态为TCP_CA_CWR。

Q: 在CWR期间采取什么措施？  
A: 拥塞窗口每隔一个确认段减小一个段，即每收到2个确认将拥塞窗口减1，直到拥塞窗口等于慢启动阈值为止。  
     调用tcp_cwnd_down()。

##### （2）Disorder状态
Q: 什么时候进入Disorder状态？  
A: 如果检测到有被sacked的数据包，或者有重传的数据包，则进入Disorder状态。  
    当然，之前已经确认不能进入Loss或Recovery状态了。  
    判断条件： sacked_out、lost_out、retrans_out、undo_marker不为0。

Q: 在Disorder期间采取什么措施？  
A: 1. 设置CA状态为TCP_CA_Disorder。  
   2. 记录此时的最高序号(high_seq = snd_nxt)，用于判断退出时机。  
   3. 微调拥塞窗口，防止爆发式传输。  

In Disorder state TCP is still unsure of genuiness of loss, after receiving acks with sack there may be a clearing ack which acks many packets non dubiously in one go. Such a clearing ack may cause a packet burst in the network, to avoid this cwnd size is reduced to allow no more than max_burst (usually 3) number of packets.

##### （3）Open状态
因为Open状态是正常的状态，是状态处理的最终目的，所以不需要进行额外处理。


