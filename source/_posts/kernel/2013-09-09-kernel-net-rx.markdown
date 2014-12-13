---
layout: post
title: "接收包的主流程"
date: 2013-09-09 18:10:00 +0800
comments: false
categories:
- 2013
- 2013~09
- kernel
- kernel~net
tags:
---
```
	int tcp_v4_rcv(struct sk_buff *skb)    linux/net/ipv4/tcp_ipv4.c #1611
```
  //tcp刚刚收到从ipv4发上来的包  
  （struct tcphdr: 定义在/include/net/tcp.h中，即包的tcp首部，不包括options部分）  
  （struct sock ：定义在/include/net/sock.h中，即表示socket）  
  检查skb->pkt_type != PACKET_HOST 则丢弃  
  检查th->doff < sizeof(struct tcphdr) / 4，即首部大小不合理，则丢弃  
  检查checksum  

  （TCP_SKB_CB(skb)：定义在tcp.h是获取一个实际指向skb->cb[0]的tcp_skb_cb类型指针；将到达的首部剥离后，从中拷贝一些信息到这个变量，供tcp控制功能使用；tcp_skb_cb是在tcp刚收到时填写在包中的）  
  注意：  
        1. tcp_skb_cb->end_seq = seq + th->fin + th->fin + len-doff*4  
        2. when 和 sacked 没有被赋值

  sk = __inet_lookup(...) 从一个hash表中获取该收包对应的sock结构，根据源IP地址+端口，目的IP地址+端口，inet_iif检查sk->sk_state == TCP_TIME_WAIT，TCP在该状态下则丢弃任何接收到的包并转入后续的特殊处理（未看，和关闭连接的状态迁移有关需要后续来看$），马上准备进入CLOSED状态了；  
  检查sk_filter(sk,skb)，则被过滤器阻拦，丢弃  
  检查!sock_owned_by_user(sk)，不明白sock->sk_lock的意义是什么，只有检查满足才能进入接收，否则 sk_add_backlog(sk, skb)将该sk_buff记录进sk_backlog队列；（注意这部操作加锁了！）  
（struct tcp_sock *tp = tcp_sk(sk)：tcp_sock定义在tcp.h中，通过tcp_sk直接将sock指针转换为tcp_sock型）

  ret = tcp_v4_do_rcv(sk, skb) 进入进一步接收处理！  
（之后的异常操作未看）

----------

```
	int tcp_v4_do_rcv(struct sock *sk, struct sk_buff *skb)    linux/net/ipv4/tcp_ipv4.c #1542
```
  //在正常状态下由tcp_v4_rcv调用，进一步进行针对接收包的处理  
  检查sk->sk_state == TCP_ESTABLISHED  
    则tcp_rcv_established(sk, skb, skb->h.th, skb->len)，连接已经建立，则进入进一步接收处理！  
  检查sk->sk_state == TCP_LISTEN，  
    则struct sock *nsk = tcp_v4_hnd_req(sk, skb);    //该函数中判断能否找到已有的连接请求，如果有则说明接收到的是一个ack并在其中创建一个新的sock即nsk；如果没有则说明接收到的是 syn，nsk即为sk；  
  if(nsk!=sk) tcp_child_process(sk,nsk,skb)    //当nsk==sk时，接收的是SYN，不进行此步直接进入tcp_rcv_state_process；否则是ack说明已经创建好了的nsk，在 tcp_child_process对nsk进行tcp_rcv_state_process状态转移处理；  
  tcp_rcv_state_process(sk, skb, skb->h.th, skb->len); 非常重要函数！处理tcp的状态转移  
  reset: tcp_v4_send_reset(rsk, skb);    reset，未看$  
  discard: kfree_skb(skb);  

-----------

```
	int tcp_rcv_established(struct sock *sk, struct sk_buff *skb,struct tcphdr *th, unsigned len)    linux/net/ipv4/tcp_input.c #3881
```

Header Prediction：基于效率的考虑，将包的处理后续阶段分为fast path和slow path两种，前者用于普通的包，后者用于特殊的包；该header prediction即用于区分两种包的流向。  
1.(tcp_flag_word(th) & TCP_HP_BITS) == tp->pred_flags 判断标志位是不是正常情况；tcp_flag_word返回指向tcphdr的第三个32位基址（即length前面），而TCP_HP_BITS是把 PSH标志位给屏蔽掉即该位值不影响流向；所以总的来说pred_flag应该等于0xS?10 << 16 + snd_wnd（那么pred_flag是在tcp_fast_path_check或tcp_fast_path_on中更新值的）  
2.TCP_SKB_CB(skb)->seq == tp->rcv_nxt 判断所收包是否为我们正想要接收的，非乱序包  
3.*ptr != htonl((TCPOPT_NOP << 24) | (TCPOPT_NOP << 16) | (TCPOPT_TIMESTAMP << 8) | TCPOLEN_TIMESTAMP) 若包中没有正常的timestamp选项则转入slow path
 timestamp选项处理： 从包中的ts选项中获取数据，以此刷新tp->rx_opt的saw_tstamp,rcv_tsval,rcv_tsecr域；ts选项含三个 32bit，其中后两个分别记录着tsval和tsecr；（注意，ts_recent并不在此处更新，在后面的tcp_store_ts_recent 中更新）  
  struct tcp_options_received: 定义在tcp.h中，其中saw_tstamp表明timestamp选项是否有效，ts_recent_stamp是我们最近一次更新 ts_recent的时间，ts_recent是下一次回显的时戳一般等于下次发包中的rcv_tsecr；rcv_tsval是该data从发端发出时的时戳值，rcv_tsecr是回显时间戳（即该ack对应的data或者该data对应的上次ack中的ts_tsval值），（注意两端时钟无需同步；当ack被收端推迟时，所回复的ack中的timestamp指向所回复包群中的第一个确认包 “When an incoming segment belongs to the current window, but arrives out of order (which implies that an earlier segment was lost), the timestamp of the earlier segment is returned as soon as it arrives, rather than the timestamp of the segment that arrived out of order.”这条细节未看明白$）从包中的时间戳选项中记录这两个值

4.PAWS check：(s32)(tp->rx_opt.rcv_tsval - tp->rx_opt.ts_recent) < 0，则转入slow path  
  （PAWS:Protection Against Wrapped Sequence Numbers, SeqNo有可能会有回环交叠（因为它最大只有32bit），两个相同序号的包实际上是不同的两个包，此时判断tsval是否小于ts_recent即判断该包是否是一个过去时间的一个多余的包，然后将其作为一个重复包丢弃）

##### Fast Path：  
  1.当len == tcp_header_len，即这是一个纯ack（区别于piggyback），注意这是个纯ack，所以它通过长度来进行判断而不是标识！  
    tcp_store_ts_recent(tp): tp->rx_opt.ts_recent = tp->rx_opt.rcv_tsval;  
    tcp_ack(sk, skb, 0) 处理ack，进一步处理，未看！  
    `__kfree_skb(skb)` 释放该包  
     tcp_data_snd_check(sk,tp) 检查有无更进一步的data包处理  
  2.当len < tcp_header_len，说明该包的首部太小，清除之；  
  3.当len > tcp_header_len，它是一个data包，tcp_copy_to_iovec函数未看，它决定该payload是否可以直接拷贝给用户空间：  
    可，tcp_store_ts_recent(tp);  
      tcp_rcv_rtt_measure_ts(sk,skb); //计算RTT  
      `__skb_pull(skb, tcp_header_len);` //剥tcp首部  
       tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq; //更新rcv_next  
($ 那么将data拷贝到用户空间的操作在何处体现？难道是在tcp_copy_to_iovec中？)  
    不可，除了以上的操作之外，还要  
      `__skb_queue_tail(&sk->sk_receive_queue, skb);` //将该包加入到接收sk_buff队列尾部  
    tcp_event_data_recv()：management tasks处理  
    若TCP_SKB_CB(skb)->ack_seq != tp->snd_una，说明这是一个有效的ack包  
      tcp_ack(sk, skb, FLAG_DATA); //FLAG_DATA说明这是一个背在data上的ack  
      tcp_data_snd_check(sk, tp); //该函数调用tcp_push_pending_frames函数，如果sk->sk_send_head存在则最终调用 tcp_write_xmit函数发包  
      `__tcp_ack_snd_check(sk, 0);` //检查基于该收包事件，有无进一步的ack包处理（Delayed ACK，Quick ACK）  

##### Slow Path：  
  tcp_checksum_complete_user(sk, skb)：checksum检查  
  tcp_fast_parse_options(skb, th, tp)：timestamp选项检查；tcp_paws_discard(sk, skb)：PAWS检查  
  tcp_sequence(tp, TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq)：检查是否乱序，并在其中激活QuickACK模式  
    上面两行中，都会再检查RST标志，若没激活则tcp_send_dupack，作用不明，貌似是针对该错包回复一个冗余的ack  
  检查RST标志，tcp_reset(sk) 该函数没什么操作，填写一些错误信息后进入tcp_done函数(该函数进行一些关闭tcp连接的收尾操作)  
  tcp_replace_ts_recent(tp, TCP_SKB_CB(skb)->seq)：更新timestamp信息  
  检查SYN标志，在连接已建立的状态下，收到SYN是错误的，因此tcp_reset(sk)  
  检查ACK标志，tcp_ack(sk, skb, FLAG_SLOWPATH)  
  tcp_rcv_rtt_measure_ts(sk, skb)：更新RTT  
  tcp_urg(sk, skb, th)：处理URG标志  
  tcp_data_queue(sk, skb)：处理接收包所含数据，未看  
  tcp_data_snd_check(sk, tp) & tcp_ack_snd_check(sk)：检查有无进一步的data或ack发送  

-------
```
	static void tcp_event_data_recv(struct sock *sk, struct tcp_sock *tp, struct sk_buff *skb)    linux/net/ipv4/tcp_input.c #502
```
  //
  inet_csk_schedule_ack(sk)：将icsk_pending置为ICSK_ACK_SCHED，但具体意义不明  
  （struct inet_connection_sock：/linux/include/net/inet_connection_sock，面向INET连接的 socket结构，记录着和tcp连接有关的很多变量，比如本函数要处理的ATO（Acknowledgement timeout）信息；tcp_sock是其上的拓展，它的具体意义尚待发掘）  
  tcp_measure_rcv_mss(sk, skb)：更新rcv_mss，说是与delayed ACK有关，但是具体是怎么运作的？  
  tcp_rcv_rtt_measure(tp)：更新RTT，为什么又更新一遍$  
  接下来的一些列操作是更新inet_connection_sock中的ATO信息，具体操作代码中有注释，但这些信息的运作方式还不明  


----------

```
static int tcp_ack(struct sock *sk, struct sk_buff *skb, int flag)    /linux/net/ipv4/tcp_input.c #2491
```
  //处理接受到的ack，内容非常复杂
  首先介绍一下ack可以携带的各个FLAG：
```
	FLAG_DATA：              Incoming frame contained data.
	FLAG_WIN_UPDATE：        Incoming ACK was a window update
	FLAG_DATA_ACKED：        This ACK acknowledged new data.
	FLAG_RETRANS_DATA_ACKED：Some of which was retransmitted.
	FLAG_SYN_ACKED：         This ACK acknowledged SYN.
	FLAG_DATA_SACKED：       New SACK.
	FLAG_ECE：               ECE in this ACK.
	FLAG_DATA_LOST：         SACK detected data lossage.
	FLAG_SLOWPATH：          Do not skip RFC checks for window update.
	FLAG_ACKED：             (FLAG_DATA_ACKED|FLAG_SYN_ACKED)
	FLAG_NOT_DUP：           (FLAG_DATA|FLAG_WIN_UPDATE|FLAG_ACKED)
	FLAG_CA_ALERT：          (FLAG_DATA_SACKED|FLAG_ECE)
	FLAG_FORWARD_PROGRESS： (FLAG_ACKED|FLAG_DATA_SACKED)
```
  prior_snd_una = tp->snd_una;ack_seq = TCP_SKB_CB(skb)->seq; ack = TCP_SKB_CB(skb)->ack_seq;  
  //1记录着上一次被确认的data序号；2记录着所收ack包的序号；3记录着所收ack包确认对象的data序号；  
  首先判断若ack在tp->snd_nxt之后或者在prio_snd_una之前，则说明该ack非法或者过时（在过时的情况下，若sacked打开则还需tcp_sacktag_write_queue处理） 24
```
	if (!(flag&FLAG_SLOWPATH) && after(ack, prior_snd_una))
		tcp_update_wl（即tp->snd_wl1 = ack_seq）; tp->snd_una=ack; //为什么此种情况下并不更新窗口？
	else
		flag |= tcp_ack_update_window(sk, tp, skb, ack, ack_seq);
		//nwin = ntohs(skb->h.th->window)从ack中记录通告窗口
		如果检查需要更新发送窗口，则tp->snd_wl1 = ack_seq; tp->snd_wnd = nwin;
		tp->snd_una = ack;
		if (TCP_SKB_CB(skb)->sacked) flag |= tcp_sacktag_write_queue(sk, skb, prior_snd_una); //该函数未看

		tp->rcv_tstamp = tcp_time_stamp; //rcv_tstamp记录着最近一次收到ack的时戳
		prior_in_flight = tcp_packets_in_flight(tp);
		if(!tp->packets_out) icsk->icsk_prbes_out = 0;
		if (sk->sk_send_head) tcp_ack_probe(sk);    //若此时网络中没有data，直接进入zero-window probe的ack处理;通告窗口的数据已经得到处理，所以tcp_ack_probe中仅仅是重置probe计时器，即 icsk->icsk_retransmit_timer

		flag |= tcp_clean_rtx_queue(sk, &seq_rtt);   //从重传队列中移除被确认的data包

		if (tcp_ack_is_dubious(sk, flag)) { //该函数判断此ack是否可疑，判真情况下具体是flag不为FLAG_NOT_DUP，或flag是FLAG_CA_ALERT，或 icsk_ca_state不为TCP_CA_OPEN状态
		if ((flag & FLAG_DATA_ACKED) && tcp_may_raise_cwnd(sk, flag))
		//如果这个包是一个对新数据包的ack，那么通过tcp_may_raise_cwnd函数来判断是否要进行窗口操作，判真情况下具体是flag不是 FLAG_ECE或snd_cwnd<snd_ssthresh（慢启动？）且icsk_ca_state不为TCP_CA_RECOVERY和 TCP_CA_CWR状态（所以，为什么TCP_CA_LOSS状态可以增窗呢？）
			tcp_cong_avoid(sk, ack, seq_rtt, prior_in_flight, 0);  
		//该函数会调用icsk->icsk_ca_ops->cong_avoid(sk, ack, rtt, in_flight, good)， 这是个函数指针；另外会更新snd_cwnd_stamp
		tcp_fastretrans_alert(sk, prior_snd_una, prior_packets, flag); //未看，极其重要的函数
	}else{
		if ((flag & FLAG_DATA_ACKED)) tcp_cong_avoid(sk, ack, seq_rtt, prior_in_flight, 1);
	}
```
tcp_ack中有很多新的内容，都还未涉及，要注意！！！！！！

---------

```
	static void tcp_data_queue(struct sock *sk, struct sk_buff *skb)    /linux/net/ipv4/tcp_input.c #3139
```
  //将数据拷贝至用户空间  
若TCP_SKB_CB(skb)->seq == TCP_SKB_CB(skb)->end_seq 则空包丢弃  
__skb_pull(skb, th->doff*4) //剥离tcp首部  

##### 1.若TCP_SKB_CB(skb)->seq == tp->rcv_nxt且tcp_receive_window(tp)!=0，非乱序且处于接受窗口中，正常的情况  
若tp->ucopy.task == current, tp->copied_seq == tp->rcv_nxt, tp->ucopy.len等条件满足，则可以拷贝至用户空间  
  //current是什么不明？ucopy.len貌似是用户最先设定的数据包的量，每次收包之后减小直至零  
    skb_copy_datagram_iovec(skb, 0, tp->ucopy.iov, chunk) //向ucopy.iov拷贝数据  
    tcp_rcv_space_adjust(sk) //计算TCP接受buffer空间大小，拷贝完  
tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;  
if(th->fin) tcp_fin(skb, sk, th); //原来fin的处理在这里！  
若!skb_queue_empty(&tp->out_of_order_queue)  
	tcp_ofo_queue(sk); //看out_of_order_queue中有没有可以移到receive_queue中  
	tcp_sack_remove(tp) //RCV.NXT advances, some SACKs should be eaten  
	tcp_fast_path_check(sk,tp)   //tp->pred_flag值的更新  
  清除skb并return  

##### 2.若!after(TCP_SKB_CB(skb)->end_seq, tp->rcv_nxt) 说明这是一个重传的包
  tcp_dsack_set(tp, TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq);   //在其中打开并填写dsack信息,在dyokucate_sack[0]中从seq到end_seq，修改dsack和eff_sacks值  
  tcp_enter_quickack_mode(sk); //进入quick ack模式  
  清除skb并return  
若!before(TCP_SKB_CB(skb)->seq, tp->rcv_nxt + tcp_receive_window(tp))  
  清除skb并return  
若before(TCP_SKB_CB(skb)->seq, tp->rcv_nxt) 说明这是一个Partial包，即seq<rcv_next<end_seq  
  tcp_dsack_set(tp, TCP_SKB_CB(skb)->seq, tp->rcv_nxt); //填写dsack信息，从seq到rcv_nxt

##### 3. 其他情况，说明收到了一个乱序包
若out_of_order_queue为空，则  
（注：out_of_order_queue是一个sk_buff_head结构，它的prev/next指针分别指向最后一个和第一个sk_buff结构，块的排放顺序对应其序号的大小顺序）  
  初始化sack相关域，num_sacks/eff_sacks为1，dsack为0，selective_acks[0]从seq到end_seq；  
  `__skb_queue_head(&tp->out_of_order_queue,skb);` //将收包加入out_of_order_queue的头部  

若out_of_order_queue不为空，则首先获取skb1 = tp->out_of_order_queue.prev即最新的一个乱序块  
  若seq == TCP_SKB_CB(skb1)->end_seq，说明收包能够接在最新乱序块的右边  
    `__skb_append(skb1, skb, &tp->out_of_order_queue);`  
    tp->selective_acks[0].end_seq = end_seq; //将新收包接在skb1的右边，看来第一个selective_acks块对应的是最新的乱序序列  
  循环执行skb1=skb1->prev，直到找到!after(TCP_SKB_CB(skb1)->seq, seq)表明需要将收包插在此块之后，或skb1=(struct sk_buff*)&tp->out_of_order_queue表明收包比队列中的所与块的序列都要小  
    循环内需要找到收包与队列已有包中的重复部分，然后tcp_dsack_set设置该部分为dsack内容  
  `__skb_insert(skb, skb1, skb1->next, &tp->out_of_order_queue);` //将收包对应的块插入到队列中  
  再次循环执行skb1=skb1->next，直到找到!after(end_seq, TCP_SKB_CB(skb1)->seq)表明需要将从收包到该包之间的所有包全部从队列中移除，或者skb1=(struct sk_buff*)&tp->out_of_order_queue表明需要将收包之后的所有包都移出  
    循环内需要将当前的队列包与收包的交叠部分设置为dsack值（当然随着循环的推进，dsack处于不断更新的状况），还要通过 `__skb_unlink(skb1, &tp->out_of_order_queue)，__kfree_skb(skb1);`将当前的队列包移除  
  （该处的两部循环，旨在通过比较队列中块的序号和所收包的序号范围，将队列中的包连续化，即消除孔洞）

-----

