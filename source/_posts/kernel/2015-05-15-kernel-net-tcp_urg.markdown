---
layout: post
title: "TCP的URG标志和内核实现"
date: 2015-05-15 13:51:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~net
tags:
---
[TCP的URG标志和内核实现之一：协议](http://blog.csdn.net/phenix_lord/article/details/42012931)  
[TCP的URG标志和内核实现之二：发送的实现](http://blog.csdn.net/phenix_lord/article/details/42046125)  
[TCP的URG标志和内核实现之三：接收的实现](http://blog.csdn.net/phenix_lord/article/details/42065897)  

----------
### TCP的URG标志和内核实现之一：协议

定义urgent数据的目的：  
urgent机制，是用于通知应用层需要接收urgent data，在urgent data接收完成后，通知应用层urgent data数据接收完毕。相关协议文本RFC793 RFC1122 RFC6093

#### 哪些数据是urgent data？

##### 协议规定

在TCP报头的URG位有效的时候，通过TCP报头中的urgent pointer来标识urgent data的位置，但是在urgent pointer的解析方式上各个协议文本的描述有差异：

解读一：RFC793  P17，描述是“The urgent pointer points to the sequence number of the octet following the urgent data.”，在P41有描述“This mechanism permits a point in the data stream to be designated as the end of urgent information. Whenever this point is in advance of the receive sequence number (RCV.NXT) at the receiving TCP, that TCP must tell the user to go into "urgent mode"; when the receive sequence number catches up to the urgent pointer, the TCP must tell user to go”，可以认为是：当前接收的报文中SEQ在SEG.SEQ+Urgent Pointer之前的都是,而urgent pointer是第一个非urgent data（ TCP已经接受，但是还没有提交给应用的数据是不是呢？）

解读二：在P56的描述是“If the urgent flag is set, then SND.UP <-SND.NXT-1 and set the urgent pointer in the outgoing segments”，也就是urgent pointer是最后一个urgent data字节。而在RFC1122中消除了这一歧义：在P84中说明“the urgent pointer points to the sequence number of the LAST octet (not LAST+1) in a sequence of urgent data”

##### linux实现

虽然在RFC1122中消除了这一歧义，linux仍然使用了解读一的解析方式，如果要使用解读二定义的方式，需要使用tcp_stdurg这个配置项。

#### urgent data数据能有多长？

##### 协议规定

按照RFC793 P41的描述，长度不受限，RFC1122 P84中，更是明确了“A TCP MUST support a sequence of urgent data of any length”

##### linux实现

其实，linux只支持1BYTE的urgent data

#### urgent data与OOB数据

OOB数据说的是带外数据，也就是这些数据不是放到TCP流供读取的，而是通过额外的接口来获取，linux默认把urgent data实现为OOB数据；而按照协议的规定，urgent data不是out of band data

由于OOB数据的协议和实现上存在很多不确定因素，因此现在已经不建议使用了

----------
### TCP的URG标志和内核实现之二：发送的实现

Linxu内核在默认情况下，把urgent data实现为OOB数据

#### 发送URG数据的接口

在内核态，使用kernel_sendmsg/kernel_sendpage完成发送，只不过需要加上MSG_OOB标志，表示要发送的URG数据。

#### URG数据发送接口的实现

分片主要在kernel_sendmsg中完成，在OOB数据的处理上，它和kernel_sendpage是一致
```
	int tcp_sendmsg(struct kiocb *iocb, struct sock *sk, struct msghdr *msg,  
			size_t size)  
	{  
		。。。。。。。。。。。。。。  
		/*如果flags设置了MSG_OOB该接口其实返回的mss_now关闭了TSO功能*/  
		mss_now = tcp_send_mss(sk, &size_goal, flags);  
		。。。。。。。。。。。。。。  
		while (--iovlen >= 0) {  
			size_t seglen = iov->iov_len;  
			unsigned char __user *from = iov->iov_base;  

			iov++;  

			while (seglen > 0) {  
				int copy = 0;  
				int max = size_goal;  

				skb = tcp_write_queue_tail(sk);  
				if (tcp_send_head(sk)) {  
					if (skb->ip_summed == CHECKSUM_NONE)  
						max = mss_now;  
					copy = max - skb->len;  
				}  

				if (copy <= 0) {  
	new_segment:  
					/* Allocate new segment. If the interface is SG, 
					 * allocate skb fitting to single page. 
					 */  
					if (!sk_stream_memory_free(sk))  
						goto wait_for_sndbuf;  

					skb = sk_stream_alloc_skb(sk,  
								  select_size(sk, sg),  
								  sk->sk_allocation);  
					if (!skb)  
						goto wait_for_memory;  

					/* 
					 * Check whether we can use HW checksum. 
					 */  
					if (sk->sk_route_caps & NETIF_F_ALL_CSUM)  
						skb->ip_summed = CHECKSUM_PARTIAL;  

					skb_entail(sk, skb);  
					copy = size_goal;  
					max = size_goal;  
				}  

				/* Try to append data to the end of skb. */  
				if (copy > seglen)  
					copy = seglen;  

				/* Where to copy to? */  
				if (skb_availroom(skb) > 0) {  
					/* We have some space in skb head. Superb! */  
					copy = min_t(int, copy, skb_availroom(skb));  
					err = skb_add_data_nocache(sk, skb, from, copy);  
					if (err)  
						goto do_fault;  
				} else {  
					int merge = 0;  
					int i = skb_shinfo(skb)->nr_frags;  
					struct page *page = sk->sk_sndmsg_page;  
					int off;  

					if (page && page_count(page) == 1)  
						sk->sk_sndmsg_off = 0;  

					off = sk->sk_sndmsg_off;  

					if (skb_can_coalesce(skb, i, page, off) &&  
						off != PAGE_SIZE) {  
						/* We can extend the last page 
						 * fragment. */  
						merge = 1;  
					} else if (i == MAX_SKB_FRAGS || !sg) {  
						/* Need to add new fragment and cannot 
						 * do this because interface is non-SG, 
						 * or because all the page slots are 
						 * busy. */  
						tcp_mark_push(tp, skb);  
						goto new_segment;  
					} else if (page) {  
						if (off == PAGE_SIZE) {  
							put_page(page);  
							sk->sk_sndmsg_page = page = NULL;  
							off = 0;  
						}  
					} else  
						off = 0;  

					if (copy > PAGE_SIZE - off)  
						copy = PAGE_SIZE - off;  
					if (!sk_wmem_schedule(sk, copy))  
						goto wait_for_memory;  

					if (!page) {  
						/* Allocate new cache page. */  
						if (!(page = sk_stream_alloc_page(sk)))  
							goto wait_for_memory;  
					}  

					/* Time to copy data. We are close to 
					 * the end! */  
					err = skb_copy_to_page_nocache(sk, from, skb,  
									   page, off, copy);  
					if (err) {  
						/* If this page was new, give it to the 
						 * socket so it does not get leaked. 
						 */  
						if (!sk->sk_sndmsg_page) {  
							sk->sk_sndmsg_page = page;  
							sk->sk_sndmsg_off = 0;  
						}  
						goto do_error;  
					}  

					/* Update the skb. */  
					if (merge) {  
						skb_frag_size_add(&skb_shinfo(skb)->frags[i - 1], copy);  
					} else {  
						skb_fill_page_desc(skb, i, page, off, copy);  
						if (sk->sk_sndmsg_page) {  
							get_page(page);  
						} else if (off + copy < PAGE_SIZE) {  
							get_page(page);  
							sk->sk_sndmsg_page = page;  
						}  
					}  

					sk->sk_sndmsg_off = off + copy;  
				}  

				if (!copied)  
					TCP_SKB_CB(skb)->tcp_flags &= ~TCPHDR_PSH;  

				tp->write_seq += copy;  
				TCP_SKB_CB(skb)->end_seq += copy;  
				skb_shinfo(skb)->gso_segs = 0;  

				from += copy;  
				copied += copy;  
				if ((seglen -= copy) == 0 && iovlen == 0)  
					goto out;  
				/*对于OOB数据，即使一个分片用光，如果还有 
				send_buff和OOB数据，就继续积累分片*/  
				if (skb->len < max || (flags & MSG_OOB))  
					continue;  

				if (forced_push(tp)) {  
					tcp_mark_push(tp, skb);  
					__tcp_push_pending_frames(sk, mss_now, TCP_NAGLE_PUSH);  
				} else if (skb == tcp_send_head(sk))  
					tcp_push_one(sk, mss_now);  
				continue;  

	wait_for_sndbuf:  
				set_bit(SOCK_NOSPACE, &sk->sk_socket->flags);  
	wait_for_memory:  
				if (copied)  
					tcp_push(sk, flags & ~MSG_MORE, mss_now, TCP_NAGLE_PUSH);  

				if ((err = sk_stream_wait_memory(sk, &timeo)) != 0)  
					goto do_error;  

				mss_now = tcp_send_mss(sk, &size_goal, flags);  
			}  
		}  

	out:  
		if (copied)  
			tcp_push(sk, flags, mss_now, tp->nonagle);  
		release_sock(sk);  
		return copied;  

	do_fault:  
		if (!skb->len) {  
			tcp_unlink_write_queue(skb, sk);  
			/* It is the one place in all of TCP, except connection 
			 * reset, where we can be unlinking the send_head. 
			 */  
			tcp_check_send_head(sk, skb);  
			sk_wmem_free_skb(sk, skb);  
		}  

	do_error:  
		if (copied)  
			goto out;  
	out_err:  
		err = sk_stream_error(sk, flags, err);  
		release_sock(sk);  
		return err;  
	}  
```

tcp_sendmsg中，涉及对OOB数据的处理主要有：

##### 1、在调用tcp_send_mss确定分片大小的时候：
```
	static int tcp_send_mss(struct sock *sk,int *size_goal, int flags)
	{
		intmss_now;
		mss_now= tcp_current_mss(sk);

		/*如果是OOB数据，large_allowed=0，关闭TSO*/
		*size_goal= tcp_xmit_size_goal(sk, mss_now, !(flags & MSG_OOB));
		returnmss_now;
	}
```
如果是OOB数据，其实是关闭了TSO功能，这样做的原因是：天知道各个网卡芯片在执行分片的时候咋个处理TCP报头中的URG标志和urgent point

##### 2、在确定何时开始执行分片的发送的时候：

如果是OOB数据，即使当前已经积累了一整个分片，也不会想普通的数据一样执行发送(tcp_push)，而是继续积累直到用户下发的数据全部分片或者snd_buf/内存用尽。

##### 3、执行tcp_push的时候：

在用户下发的数据全部分片或者snd_buf/内存用尽后，进入tcp_push执行发送操作(所有的OOB数据，都会通过这个接口来执行发送)
```
	static inline void tcp_push(struct sock*sk, int flags, int mss_now,
							 int nonagle)
	{
		if(tcp_send_head(sk)) {
			structtcp_sock *tp = tcp_sk(sk);
			if(!(flags & MSG_MORE) || forced_push(tp))
				tcp_mark_push(tp,tcp_write_queue_tail(sk));	   
				  /*tcp_mark_urg设置tp->snd_up，标识进入OOB数据发送模式，设置urgent point
				  指向urgentdata接受后的第一个字符*/
			tcp_mark_urg(tp,flags);
			__tcp_push_pending_frames(sk,mss_now,
						  (flags & MSG_MORE) ? TCP_NAGLE_CORK :nonagle);
		}
	}
```

#### 发送处理

使用struct tcp_sock中的snd_up来标识当前的urgent point，同时也使用该数据来判断当前是否处于urgent data发送模式，在普通数据的发送模式中tcp_sock::snd_up总是和tcp_sock::snd_una相等，只有在有urgent data发送的时候，才在tcp_push--->tcp_mark_urg中设置为urgentpoint，进入到urgent data的处理模式

在tcp_transmit_skb中的以下代码段负责urgent data相关的处理：
```
	if (unlikely(tcp_urg_mode(tp) && before(tcb->seq, tp->snd_up))) {  
		if (before(tp->snd_up, tcb->seq + 0x10000)) {  
			th->urg_ptr = htons(tp->snd_up - tcb->seq);  
			th->urg = 1;  
		} else if (after(tcb->seq + 0xFFFF, tp->snd_nxt)) {  
			th->urg_ptr = htons(0xFFFF);  
			th->urg = 1;  
		}  
	}  
```

只要当前待发送的skb的seq在tcp_sock记录的urgent point前面，就需要在报头中对URG标志置位，同时如果tcp_sock记录的urgent point。如果该报文的seq距离大于16为能表示的最大值，就置TCP报头中的urgent point为65535。

#### 切换回普通模式：

在收到对方ACK的处理流程tcp_ack--->tcp_clean_rtx_queue中：
```
	if (likely(between(tp->snd_up, prior_snd_una, tp->snd_una)))  
		tp->snd_up = tp->snd_una;  
```

#### 报文体现
根据对发送代码的分析，可以看到：如果用户使用MSG_OOB数据发送一段比较长(若干个MSS)的数据，那么线路上的报文应该是分成了若干组，每组由若干个长度为MSS的报文构成，组内的每个报文有一样的urgent pointer，指向下一组报文的起始seq，每一组的长度最长为65535。

----------
### TCP的URG标志和内核实现之三：接收的实现

大致的处理过程

TCP的接收流程：在tcp_v4_do_rcv中的相关处理(网卡收到报文触发)中，会首先通过tcp_check_urg设置tcp_sock的urg_data为TCP_URG_NOTYET(urgent point指向的可能不是本报文，而是后续报文或者前面收到的乱序报文)，并保存最新的urgent data的sequence和对于的1 BYTE urgent data到tcp_sock的urg_data (如果之前的urgent data没有读取，就会被覆盖)。

用户接收流程：在tcp_recvmsg流程中，如果发现当前的skb的数据中有urgent data，首先拷贝urgent data之前的数据，然后tcp_recvmsg退出，提示用户来接收OOB数据；在用户下一次调用tcp_recvmsg来接收数据的时候，会跳过urgent data，并设置urgent data数据接收完成。
相关的数据结构和定义

tcp_sock结构：

1、 urg_data成员，其高8bit为urgent data的接收状态；其低8位为保存的1BYTE urgent数据。urgent data的接收状态对应的宏的含义描述：
```
	#defineTCP_URG_VALID	0x0100  /*urgent data已经读到了tcp_sock::urg_data*/

	#defineTCP_URG_NOTYET   0x0200  /*已经发现有urgent data，还没有读取到tcp_sock::urg_data*/

	#defineTCP_URG_READ	    0x0400  /*urgent data已经被用户通过MSG_OOB读取了*/
```

2、 urg_seq成员，为当前的urgent data的sequence

流程详情

#### TCP的接收过程

在tcp_rcv_established的slow_path中

```
	slow_path:  
		if (len < (th->doff << 2) || tcp_checksum_complete_user(sk, skb))  
			goto csum_error;  
		/* 
		 *  Standard slow path. 
		 */  
		if (!tcp_validate_incoming(sk, skb, th, 1))  
			return 0;  
	step5:  
		if (th->ack &&  
			tcp_ack(sk, skb, FLAG_SLOWPATH | FLAG_UPDATE_TS_RECENT) < 0)  
			goto discard;  
		tcp_rcv_rtt_measure_ts(sk, skb);  
		/* 处理紧急数据. */  
		tcp_urg(sk, skb, th);  
```

也就是在报文的CRC验证和sequence验证完成后，就会通过tcp_urg来处理接收到的urgent data ：

```
	static void tcp_urg(struct sock *sk, struct sk_buff *skb, const struct tcphdr *th)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
	  
		/*收到了urgent data,则检查和设置urg_data和urg_seq成员*/  
		if (th->urg)  
			tcp_check_urg(sk, th);  
	  
		/* Do we wait for any urgent data? - normally not... 
		发现了有urgent data，但是还没有保存到tp->urg_data*/  
		if (tp->urg_data == TCP_URG_NOTYET) {  
			u32 ptr = tp->urg_seq - ntohl(th->seq) + (th->doff * 4) -  
				  th->syn;  
	  
			/* Is the urgent pointer pointing into this packet? */  
			if (ptr < skb->len) {  
				u8 tmp;  
				if (skb_copy_bits(skb, ptr, &tmp, 1))  
					BUG();  
				tp->urg_data = TCP_URG_VALID | tmp;  
				if (!sock_flag(sk, SOCK_DEAD))  
					sk->sk_data_ready(sk, 0);  
			}  
		}  
	}  
```

检查和设置urg_data和urg_seq成员的处理函数tcp_check_urg的具体流程

```
	static void tcp_check_urg(struct sock *sk, const struct tcphdr *th)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
		u32 ptr = ntohs(th->urg_ptr);  
		/*两种urgent point的解析方式: 
		一是指向urgent data之后的第一个字节 
		二是执行urgent data的结束字节(RFC1122) 
		sysctl_tcp_stdurg被设置表示当前采用的是第二种模式 
		不需要把urgent point -1来指向urgent data的结束字节*/  
		if (ptr && !sysctl_tcp_stdurg)  
			ptr--;  
		ptr += ntohl(th->seq);  
	  
		/* Ignore urgent data that we've already seen and read.  
		如果copied_seq已经大于urgent point，那么对于从tcp_rcv_established 
		来执行的，前面的tcp_validate_incoming已经拒绝了这种报文( 
		接收窗口外)，这里要处理的是哪种情形?*/  
		if (after(tp->copied_seq, ptr))  
			return;  
	  
		/* Do not replay urg ptr. 
		 * 
		 * NOTE: interesting situation not covered by specs. 
		 * Misbehaving sender may send urg ptr, pointing to segment, 
		 * which we already have in ofo queue. We are not able to fetch 
		 * such data and will stay in TCP_URG_NOTYET until will be eaten 
		 * by recvmsg(). Seems, we are not obliged to handle such wicked 
		 * situations. But it is worth to think about possibility of some 
		 * DoSes using some hypothetical application level deadlock. 
		 */  
		/*  这种情况什么时候发生?没搞明白*/  
		if (before(ptr, tp->rcv_nxt))  
			return;  
	  
		/* Do we already have a newer (or duplicate) urgent pointer?  
		如果当前已经进入urg数据读取模式，且urgent point不大于当前 
		保存的值，那么之前已经开始了读取tp->urg_seq对应的 
		urgent 数据，无需重复处理了*/  
		if (tp->urg_data && !after(ptr, tp->urg_seq))  
			return;  
	  
		/* Tell the world about our new urgent pointer.*/  
		sk_send_sigurg(sk);  
	  
		/* We may be adding urgent data when the last byte read was 
		 * urgent. To do this requires some care. We cannot just ignore 
		 * tp->copied_seq since we would read the last urgent byte again 
		 * as data, nor can we alter copied_seq until this data arrives 
		 * or we break the semantics of SIOCATMARK (and thus sockatmark()) 
		 * 
		 * NOTE. Double Dutch. Rendering to plain English: author of comment 
		 * above did something sort of  send("A", MSG_OOB); send("B", MSG_OOB); 
		 * and expect that both A and B disappear from stream. This is _wrong_. 
		 * Though this happens in BSD with high probability, this is occasional. 
		 * Any application relying on this is buggy. Note also, that fix "works" 
		 * only in this artificial test. Insert some normal data between A and B and we will 
		 * decline of BSD again. Verdict: it is better to remove to trap 
		 * buggy users. 
		 */  
		 /*用户下一次要读取的数据就是用户还没有读取的urgent数据 
		且当前存在新的用户未读取数据*/  
		if (tp->urg_seq == tp->copied_seq && tp->urg_data &&  
			!sock_flag(sk, SOCK_URGINLINE) && tp->copied_seq != tp->rcv_nxt) {  
			struct sk_buff *skb = skb_peek(&sk->sk_receive_queue);  
			tp->copied_seq++;  
			if (skb && !before(tp->copied_seq, TCP_SKB_CB(skb)->end_seq)) {  
				__skb_unlink(skb, &sk->sk_receive_queue);  
				__kfree_skb(skb);  
			}  
		}  
	  
		tp->urg_data = TCP_URG_NOTYET;  
		tp->urg_seq = ptr;  
	  
		/* Disable header prediction. */  
		tp->pred_flags = 0;  
	}  
```

#### 用户接收数据接口
##### 用户接收URG数据的接口
在用户接收数据的tcp_recvmsg函数中，如果用户通过MSG_OOB来接收数据，会进入tcp_recv_urg处理
```
	static int tcp_recv_urg(struct sock *sk, struct msghdr *msg, int len, int flags)  
	{  
		struct tcp_sock *tp = tcp_sk(sk);  
	  
		/* No URG data to read.  
		用户已经读取过了*/  
		if (sock_flag(sk, SOCK_URGINLINE) || !tp->urg_data ||  
			tp->urg_data == TCP_URG_READ)  
			return -EINVAL; /* Yes this is right ! */  
	  
		if (sk->sk_state == TCP_CLOSE && !sock_flag(sk, SOCK_DONE))  
			return -ENOTCONN;  
		/*当前的tp->urg_data为合法的数据，可以读取*/  
		if (tp->urg_data & TCP_URG_VALID) {  
			int err = 0;  
			char c = tp->urg_data;  
			/*标识urgent data已读*/  
			if (!(flags & MSG_PEEK))  
				tp->urg_data = TCP_URG_READ;  
	  
			/* Read urgent data. */  
			msg->msg_flags |= MSG_OOB;  
	  
			if (len > 0) {  
				if (!(flags & MSG_TRUNC))  
					err = memcpy_toiovec(msg->msg_iov, &c, 1);  
				len = 1;  
			} else  
				msg->msg_flags |= MSG_TRUNC;  
	  
			return err ? -EFAULT : len;  
		}  
	  
		if (sk->sk_state == TCP_CLOSE || (sk->sk_shutdown & RCV_SHUTDOWN))  
			return 0;  
	  
		/* Fixed the recv(..., MSG_OOB) behaviour.  BSD docs and 
		 * the available implementations agree in this case: 
		 * this call should never block, independent of the 
		 * blocking state of the socket. 
		 * Mike <pall@rz.uni-karlsruhe.de> 
		 */  
		return -EAGAIN;  
	}  
```

##### 用户接收普通数据的接口中的相关处理

在用户接收数据的tcp_recvmsg函数中，在查找到待拷贝的skb后，首先拷贝urgent data数据前的数据，然后退出接收过程，在用户下一次执行tcp_recvmsg的时候跳过urgent data，设置urgent data读取结束

查找到准备拷贝的skb后的处理：
```
	found_ok_skb:  
	/* Ok so how much can we use? */  
	used = skb->len - offset;  
	if (len < used)  
		used = len;  
	  
	/* 当前有urg_data数据*/  
	if (tp->urg_data) {  
		u32 urg_offset = tp->urg_seq - *seq;  
		/*urgent data在当前待拷贝的数据范围内*/  
		if (urg_offset < used) {  
			if (!urg_offset) {/*待拷贝的数据就是urgent data，跨过该urgent data， 
			只给用户读取后面的数据*/  
				if (!sock_flag(sk, SOCK_URGINLINE)) {  
					++*seq;  
					urg_hole++;  
					offset++;  
					used--;  
					if (!used)  
						goto skip_copy;  
				}  
			}   
			} else/*指定只拷贝urgent data数据之前的，完成后在下一次循环 
			开始的位置，会退出循环，返回用户；下一次用户调用tcp_recvmsg 
			就进入到上面的分支了*/  
				used = urg_offset;  
		}  
	}   
```

```
	skip_copy:  
			/*用户读取的数据跨过了urgent point，设置读取结束 
			开启fast path*/  
			if (tp->urg_data && after(tp->copied_seq, tp->urg_seq)) {  
				tp->urg_data = 0;  
				tcp_fast_path_check(sk);  
			}  
			if (used + offset < skb->len)  
				continue;  
```

在接收完urgent data数据前的所有数据之后， tcp_recvmsg的以下代码片段得到执行，这段代码退出当前接收过程，提示用户有urgent data数据到来，需要用MSG_OOB来接收
```
	if (tp->urg_data && tp->urg_seq == *seq) {  
		if (copied)  
			break;  
		if (signal_pending(current)) {  
			copied = timeo ? sock_intr_errno(timeo) : -EAGAIN;  
			break;  
		}  
	}  
```

### 后记

TCP的urg数据，由于定义和实现上的混乱，当前已经不建议使用，但是为了兼容之前已经已经存在的实现，该机制会长期在内核中存在，如果不了解该机制及其内核行为，有可能就很难解释一些奇怪的问题：比如某段代码不小心地造成send接口事实上设置了MSG_OOB，就会造成接收端少了一个BYTE。

