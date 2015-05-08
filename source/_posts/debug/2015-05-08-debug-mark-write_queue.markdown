---
layout: post
title: "如果sk_write_queue异常"
date: 2015-05-08 14:14:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~mark
tags:
---
* 注意，以下情况内核都不可能产生，纯属假设


#### 一、连续的SYN/FIN
```
	|---FIN---|---SYN/FIN---|
	    skb       next_skb
```
* 内核不可能出现是因为：发送FIN包后就不再发包。所以FIN包只可能在sk_write_queue的最后一个包

假设skb和next_skb发出去后都丢了，那tcp_retransmit_skb会重传skb，
重传的时候会调用tcp_retrans_try_collapse尝试去和下一个包合并。

skb和next_skb合并过程：  
先检查一些条件，然后
```
	...
	skb_copy_from_linear_data(next_skb, skb_put(skb, next_skb_size), next_skb_size);
	...
	TCP_SKB_CB(skb)->end_seq = TCP_SKB_CB(next_skb)->end_seq;
```
也就是skb->len += next_skb->len; skb->end_seq = next_skb->end_seq;

假设:
```
	skb->len = 0;      skb->seq = 10;      skb->end_seq = 10 + FIN = 11;
	next_skb->len = 0; next_skb->seq = 11; next_skb->end_seq = 11 + SYN/FIN = 12;
```
那么合并后：
```
	skb->len = 0;      skb->seq = 10;      skb->end_seq = 12;
```
很明显不正常了，正常情况下：skb->len <= skb->end_seq - skb->seq <= skb->len+1

这时如果来了ack 11，那么会再重传合并后的skb，然后会调用tcp_trim_head(struct ws_st_sock *sk, struct sk_buff *skb, u32 len)，参数len = tp->snd_una - TCP_SKB_CB(skb)->seq = 1，但skb->len = 0;

tcp_trim_head函数中会：
```
	skb->len -= len;
```
这时skb->len = (U32)-1 = 0xFFFFFFFF，skb->len错误后，再调用skb_copy之类的就会访问越界，报BUG。
```
	 821 struct sk_buff *skb_copy(const struct sk_buff *skb, gfp_t gfp_mask)
	 822 {
			......
	 835         if (skb_copy_bits(skb, -headerlen, n->head, headerlen + skb->len))
	 836                 BUG();
```

#### 二、write_queue的skb->end_seq > next_skb->seq可能的问题

* 内核用tp->write_seq控制，保证了write_queue的skb->end_seq == next_skb->seq

```
	skb:       |------------------|
    next_skb:  |---------------------|

	假设skb已经发送出去，并被ack了，这时tp->snd_una = skb->end_seq
    此时再发送next_skb，并且mss变小了，需要对next_skb分包，分包后如下：

	skb:       |------------------|
    next_skb:  |-------|-------:-----|
                  skb1       skb2

	next_skb 被分成了两个包，skb1->len = mss, skb1->gso_segs = 1; skb2->len > mss, skb2->gso_segs = 2;
	skb1, skb2发送出去，丢了，然后重传skb1，
	此时 skb1->end_seq < tp->snd_una

	2092 int tcp_retransmit_skb(struct sock *sk, struct sk_buff *skb)
	2093 {
			......
	2111         if (before(TCP_SKB_CB(skb)->seq, tp->snd_una)) {
	2112                 if (before(TCP_SKB_CB(skb)->end_seq, tp->snd_una))
	2113                         BUG();
```

#### 三、write_queue的skb->end_seq > next_skb->seq可能的问题
```
	skb:       |------------------|
    next_skb:  |---------------------|

	skb, next_skb 发送出去丢了，重传，调用tcp_retrans_try_collapse合并。
	合并后：skb->len += next_skb->len; skb->end_seq = next_skb->end_seq;

	假设   skb->len = 100;      skb->seq = 0;      skb->end_seq = 100;
	      next_skb->len = 120  next_skb->seq = 0; next_skb->end_seq = 120;
	合并后 skb->len = 200;      skb->seq = 0;      skb->end_seq = 120;

	发送合并后的skb，再丢包，再重传，mss = 150，skb->len > mss, 会分包
	      skb->len = 150;      skb->seq = 0;      skb->end_seq = 150;
	      next_skb->len = 50;  next_skb->seq = 150; next_skb->end_seq = 120;
	也就是出现了next_skb->seq > next_skb->end_seq
	(此时如果ack skb也会把next_skb一起清了，因为next_skb->end_seq < skb->end_seq)

	这时如果skb再重传分包，分成skb3，skb4
		skb3->len = 130;   skb3->seq = 0;   skb3->end_seq = 130;
		skb4->len = 20;    skb4->seq = 130; skb4->end_seq = 150;

	这时ack了skb3，tp->snd_una = 130 (虽然next_skb->end_seq < skb3->end_seq, 但skb4->end_seq > skb3->end_seq, 所以不会把next_skb清掉)
	重传skb4，skb5，此时skb5->end_seq < tp->snd_una

	2092 int tcp_retransmit_skb(struct sock *sk, struct sk_buff *skb)
	2093 {
			......
	2111         if (before(TCP_SKB_CB(skb)->seq, tp->snd_una)) {
	2112                 if (before(TCP_SKB_CB(skb)->end_seq, tp->snd_una))
	2113                         BUG();
``` 

#### 四、write_queue的skb->end_seq > next_skb->seq可能的问题
```
	skb:       |------------------|
    next_skb:  |---------------------|

	发送 skb，next_skb
	接收到 sack:|---------------------|

	调用tcp_sacktag_walk() ---> tcp_shift_skb_data() 将多个被sack的包合并成一个。
	合并过程：
		skb->len += next_skb->len; skb->end_seq += next_skb->len;
	那么就会合并出一超出原来end_seq的包：
	           |----------------------------------------|
	然后再ack:  |----------------------|
	这时把合并出的包trim掉一部分，剩skb7:  |-----------------|

	再发包skb_new:                     |-------|
	这时tp->snd_nxt = skb_new->end_seq
	再重传skb7, 并分包:                 |----------|------|
	分包时skb7->end_seq > tp->snd_nxt, 所以不会调整tp->packets_out，
	但ack到来时(tcp_clean_rtx_queue)tp->packets_out却会减去分包后的gso_segs。
	导致tp->packets_out < 0, 但sk_write_queue却是空的。
	tcp_rearm_rto()判断tp->packets_out不为0，启动重传定时器，然后重传时取出的是list_head的地址，不是skb的地址，导致后面异常。
	代码：
	 974 int tcp_fragment(struct sock *sk, struct sk_buff *skb, u32 len,
	 975                  unsigned int mss_now)
	 976 {
		......
	1047         if (!before(tp->snd_nxt, TCP_SKB_CB(buff)->end_seq)) {
	1048                 int diff = old_factor - tcp_skb_pcount(skb) -
	1049                         tcp_skb_pcount(buff);
	1050 
	1051                 if (diff)
	1052                         tcp_adjust_pcount(sk, skb, diff);
	1053         }


```

#### 五（发现好像没错）、write_queue的skb->end_seq > next_skb->seq可能的问题

* 内核用tp->write_seq控制，保证了write_queue的skb->end_seq == next_skb->seq

```
	skb:       |------------------|
    next_skb:  |---------------------|

	假设skb已经发送出去，这时tp->snd_nxt = skb->end_seq
    发送next_skb时mss变小了，需要对next_skb分包，分包后如下：

	skb:       |------------------|
    next_skb:  |-------|-------:-----|
                  skb1       skb2
	next_skb 被分成了两个包，skb1->len = mss, skb1->gso_segs = 1; skb2->len > mss, skb2->gso_segs = 2;

	然后将skb1, skb2发送出去, tp->packets_out += 3; 这时假设ack了skb，清掉skb1和skb2的一个mss，。。。没错。。。

```

