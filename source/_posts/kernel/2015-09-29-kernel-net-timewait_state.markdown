---
layout: post
title: "TIME_WAIT状态下对接收到的数据包如何处理"
date: 2015-09-29 17:53:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~net
tags:
---
http://www.educity.cn/linux/1605134.html

正常情况下主动关闭连接的一端在连接正常终止后，会进入TIME_WAIT状态，存在这个状态有以下两个原因（参考《Unix网络编程》）：

《UNIX网络编程.卷2：进程间通信(第2版)》[PDF]下载

1、保证TCP连接关闭的可靠性。如果最终发送的ACK丢失，被动关闭的一端会重传最终的FIN包，如果执行主动关闭的一端没有维护这个连接的状态信息，会发送RST包响应，导致连接不正常关闭。

2、允许老的重复分组在网络中消逝。假设在一个连接关闭后，发起建立连接的一端（客户端）立即重用原来的端口、IP地址和服务端建立新的连接。老的连接上的分组可能在新的连接建立后到达服务端，TCP必须防止来自某个连接的老的重复分组在连接终止后再现，从而被误解为同一个连接的化身。要实现这种功能，TCP不能给处于TIME_WAIT状态的连接启动新的连接。TIME_WAIT的持续时间是2MSL，保证在建立新的连接之前老的重复分组在网络中消逝。这个规则有一个例外：如果到达的SYN的序列号大于前一个连接的结束序列号，源自Berkeley的实现将给当前处于TIME_WAIT状态的连接启动新的化身。

最初在看《Unix网络编程》 的时候看到这个状态，但是在项目中发现对这个状态的理解有误，特别是第二个理由。原本认为在TIME_WAIT状态下肯定不会再使用相同的五元组（协议类型，源目的IP、源目的端口号）建立一个新的连接，看书还是不认真啊！为了加深理解，决定结合内核代码，好好来看下内核在TIME_WAIT状态下的处理。其实TIME_WAIT存在的第二个原因的解释更多的是从被动关闭一方的角度来说明的。如果是执行主动关闭的是客户端，客户端户进入TIME_WAIT状态，假设客户端重用端口号来和服务器建立连接，内核会不会允许客户端来建立连接？内核如何来处理这种情况？书本中不会对这些点讲的那么详细，要从内核源码中来找答案。

我们先来看服务器段进入TIME_WAIT后内核的处理，即服务器主动关闭连接。TCP层的接收函数是tcp_v4_rcv()，和TIME_WAIT状态相关的主要代码如下所示：

```
	int tcp_v4_rcv(struct sk_buff *skb)
	{
		......

		sk = __inet_lookup_skb(&tcp_hashinfo, skb, th->source, th->dest);
		if (!sk)
			goto no_tcp_socket;
	process:
		if (sk->sk_state == TCP_TIME_WAIT)
			goto do_time_wait;   
			......

	discard_it:
		/* Discard frame. */
		kfree_skb(skb);
		return 0;
		......
	do_time_wait:
		......

	switch (tcp_timewait_state_process(inet_twsk(sk), skb, th)) {
		case TCP_TW_SYN: {
			struct sock *sk2 = inet_lookup_listener(dev_net(skb->dev),
								&tcp_hashinfo,
								iph->daddr, th->dest,
								inet_iif(skb));
			if (sk2) {
				inet_twsk_deschedule(inet_twsk(sk), &tcp_death_row);
				inet_twsk_put(inet_twsk(sk));
				sk = sk2;
				goto process;
			}
			/* Fall through to ACK */
		}
		case TCP_TW_ACK:
			tcp_v4_timewait_ack(sk, skb);
			break;
		case TCP_TW_RST:
			goto no_tcp_socket;
		case TCP_TW_SUCCESS:;
		}
		goto discard_it;
	}
```

接收到SKb包后，会调用__inet_lookup_skb()查找对应的sock结构。如果套接字状态是TIME_WAIT状态，会跳转到do_time_wait标签处处理。从代码中可以看到，主要由tcp_timewait_state_process()函数来处理SKB包，处理后根据返回值来做相应的处理。

在看tcp_timewait_state_process()函数中的处理之前，需要先看一看不同的返回值会对应什么样的处理。

如果返回值是TCP_TW_SYN，则说明接收到的是一个“合法”的SYN包（也就是说这个SYN包可以接受），这时会首先查找内核中是否有对应的监听套接字，如果存在相应的监听套接字，则会释放TIME_WAIT状态的传输控制结构，跳转到process处开始处理，开始建立一个新的连接。如果没有找到监听套接字会执行到TCP_TW_ACK分支。

如果返回值是TCP_TW_ACK，则会调用tcp_v4_timewait_ack()发送ACK，然后跳转到discard_it标签处，丢掉数据包。

如果返回值是TCP_TW_RST，则会调用tcp_v4_send_reset()给对端发送RST包，然后丢掉数据包。

如果返回值是TCP_TW_SUCCESS，则会直接丢掉数据包。

接下来我们通过tcp_timewait_state_process()函数来看TIME_WAIT状态下的数据包处理。

为了方便讨论，假设数据包中没有时间戳选项，在这个前提下，tcp_timewait_state_process()中的局部变量paws_reject的值为0。

如果需要保持在FIN_WAIT_2状态的时间小于等于TCP_TIMEWAIT_LEN，则会从FIN_WAIT_2状态直接迁移到TIME_WAIT状态，也就是使用描述TIME_WAIT状态的sock结构代替当前的传输控制块。虽然这时的sock结构处于TIME_WAIT结构，但是还要区分内部状态，这个内部状态存储在inet_timewait_sock结构的tw_substate成员中。

如果内部状态为FIN_WAIT_2，tcp_timewait_state_process()中处理的关键代码片段如下所示：

```
	if (tw->tw_substate == TCP_FIN_WAIT2) {
		/* Just repeat all the checks of tcp_rcv_state_process() */

		/* Out of window, send ACK */
		if (paws_reject ||
			!tcp_in_window(TCP_SKB_CB(skb)->seq, TCP_SKB_CB(skb)->end_seq,
				  tcptw->tw_rcv_nxt,
				  tcptw->tw_rcv_nxt + tcptw->tw_rcv_wnd))
			return TCP_TW_ACK;

		if (th->rst)
			goto kill;

		if (th->syn && !before(TCP_SKB_CB(skb)->seq, tcptw->tw_rcv_nxt))
			goto kill_with_rst;

		/* Dup ACK? */
		if (!th->ack ||
			!after(TCP_SKB_CB(skb)->end_seq, tcptw->tw_rcv_nxt) ||
			TCP_SKB_CB(skb)->end_seq == TCP_SKB_CB(skb)->seq) {
			inet_twsk_put(tw);
			return TCP_TW_SUCCESS;
		}

		/* New data or FIN. If new data arrive after half-duplex close,
		 * reset.
		 */
		if (!th->fin ||
			TCP_SKB_CB(skb)->end_seq != tcptw->tw_rcv_nxt + 1) {
	kill_with_rst:
			inet_twsk_deschedule(tw, &tcp_death_row);
			inet_twsk_put(tw);
			return TCP_TW_RST;
		}

		/* FIN arrived, enter true time-wait state. */
		tw->tw_substate      = TCP_TIME_WAIT;
		tcptw->tw_rcv_nxt = TCP_SKB_CB(skb)->end_seq;
		if (tmp_opt.saw_tstamp) {
			tcptw->tw_ts_recent_stamp = get_seconds();
			tcptw->tw_ts_recent      = tmp_opt.rcv_tsval;
		}

		/* I am shamed, but failed to make it more elegant.
		 * Yes, it is direct reference to IP, which is impossible
		 * to generalize to IPv6. Taking into account that IPv6
		 * do not understand recycling in any case, it not
		 * a big problem in practice. --ANK 
		 */
		if (tw->tw_family == AF_INET &&
			tcp_death_row.sysctl_tw_recycle && tcptw->tw_ts_recent_stamp &&
			tcp_v4_tw_remember_stamp(tw))
			inet_twsk_schedule(tw, &tcp_death_row, tw->tw_timeout,
					  TCP_TIMEWAIT_LEN);
		else
			inet_twsk_schedule(tw, &tcp_death_row, TCP_TIMEWAIT_LEN,
					  TCP_TIMEWAIT_LEN);

		return TCP_TW_ACK;
	}
```

如果TCP段序号不完全在接收窗口内，则返回TCP_TW_ACK，表示需要给对端发送ACK。

如果在FIN_WAIT_2状态下接收到的是RST包，则跳转到kill标签处处理，立即释放timewait控制块，并返回TCP_TW_SUCCESS。

如果是SYN包，但是SYN包的序列号在要接收的序列号之前，则表示这是一个过期的SYN包，则跳转到kill_with_rst标签处处理，此时不仅会释放TIME_WAIT传输控制块，还会返回TCP_TW_RST，要给对端发送RST包。

如果接收到DACK，则释放timewait控制块，并返回TCP_TW_SUCCESS。在这种情况下有一个判断条件是看包的结束序列号和起始序列号相同时，会作为DACK处理，所以之后的处理是在数据包中的数据不为空的情况下处理。前面的处理中已经处理了SYN包、RST包的情况，接下来就剩以下三种情况：

1、不带FIN标志的数据包

2、带FIN标志，但是还包含数据

3、FIN包，不包含数据

如果是前两种情况，则会调用inet_twsk_deschedule()释放time_wait控制块。inet_twsk_deschedule()中会调用到inet_twsk_put()减少time_wait控制块的引用，在外层函数中再次调用inet_twsk_put()函数时，就会真正释放time_wait控制块。

如果接收的是对端的FIN包，即第3种情况，则将time_wait控制块的子状态设置为TCP_TIME_WAIT，此时才是进入真正的TIME_WAIT状态。然后根据TIME_WAIT的持续时间的长短来确定是加入到twcal_row队列还是启动一个定时器，最后会返回TCP_TW_ACK，给对端发送TCP连接关闭时最后的ACK包。

到这里，我们看到了对FIN_WAIT_2状态（传输控制块状态为TIME_WAIT状态下，但是子状态为FIN_WAIT_2）的完整处理。

接下来的处理才是对真正的TIME_WAIT状态的处理，即子状态也是TIME_WAIT。

如果在TIME_WAIT状态下，接收到ACK包（不带数据）或RST包，并且包的序列号刚好是下一个要接收的序列号，由以下代码片段处理：

```
	if (!paws_reject &&
		(TCP_SKB_CB(skb)->seq == tcptw->tw_rcv_nxt &&
		(TCP_SKB_CB(skb)->seq == TCP_SKB_CB(skb)->end_seq || th->rst))) {
		/* In window segment, it may be only reset or bare ack. */
		if (th->rst) {
			/* This is TIME_WAIT assassination, in two flavors.
			* Oh well... nobody has a sufficient solution to this
			* protocol bug yet.
			*/
			if (sysctl_tcp_rfc1337 == 0) {
	kill:
				inet_twsk_deschedule(tw, &tcp_death_row);
				inet_twsk_put(tw);
				return TCP_TW_SUCCESS;
			}
		}
		inet_twsk_schedule(tw, &tcp_death_row, TCP_TIMEWAIT_LEN,
				  TCP_TIMEWAIT_LEN);

		if (tmp_opt.saw_tstamp) {
			tcptw->tw_ts_recent      = tmp_opt.rcv_tsval;
			tcptw->tw_ts_recent_stamp = get_seconds();
		}

		inet_twsk_put(tw);
		return TCP_TW_SUCCESS;
	}
```

如果是RST包的话，并且系统配置sysctl_tcp_rfc1337（默认情况下为0，参见/proc/sys/net/ipv4/tcp_rfc1337）的值为0，这时会立即释放time_wait传输控制块，丢掉接收的RST包。

如果是ACK包，则会启动TIME_WAIT定时器后丢掉接收到的ACK包。

接下来是对SYN包的处理。前面提到了，如果在TIME_WAIT状态下接收到序列号比上一个连接的结束序列号大的SYN包，可以接受，并建立新的连接，下面这段代码就是来处理这样的情况：

```
	if (th->syn && !th->rst && !th->ack && !paws_reject &&
		(after(TCP_SKB_CB(skb)->seq, tcptw->tw_rcv_nxt) ||
		(tmp_opt.saw_tstamp &&
		  (s32)(tcptw->tw_ts_recent - tmp_opt.rcv_tsval) < 0))) {
		u32 isn = tcptw->tw_snd_nxt + 65535 + 2;
		if (isn == 0)
			isn++;
		TCP_SKB_CB(skb)->when = isn;
		return TCP_TW_SYN;
	}
```

当返回TCP_TW_SYN时，在tcp_v4_rcv()中会立即释放time_wait控制块，并且开始进行正常的连接建立过程。

如果数据包不是上述几种类型的包，可能的情况有：

1、不是有效的SYN包。不考虑时间戳的话，就是序列号在上一次连接的结束序列号之前

2、ACK包，起始序列号不是下一个要接收的序列号

3、RST包，起始序列号不是下一个要接收的序列号

4、带数据的SKB包

这几种情况由以下代码处理：

```
	if (!th->rst) {
		/* In this case we must reset the TIMEWAIT timer.
		 *
		 * If it is ACKless SYN it may be both old duplicate
		 * and new good SYN with random sequence number <rcv_nxt.
		 * Do not reschedule in the last case.
		 */
		if (paws_reject || th->ack)
			inet_twsk_schedule(tw, &tcp_death_row, TCP_TIMEWAIT_LEN,
					  TCP_TIMEWAIT_LEN);

		/* Send ACK. Note, we do not put the bucket,
		 * it will be released by caller.
		 */
		return TCP_TW_ACK;
	}
	inet_twsk_put(tw);
	return TCP_TW_SUCCESS;
```

如果是RST包，即第3种情况，则直接返回TCP_TW_SUCCESS，丢掉RST包。

如果带有ACK标志的话，则会启动TIME_WAIT定时器，然后给对端发送ACK。我们知道SYN包正常情况下不会设置ACK标志，所以如果是SYN包不会启动TIME_WAIT定时器，只会给对端发送ACK，告诉对端已经收到SYN包，避免重传，但连接应该不会继续建立。

还有一个细节需要提醒下，就是我们看到在返回TCP_TW_ACK时，没有调用inet_twsk_put()释放对time_wait控制块的引用。这时因为在tcp_v4_rcv()中调用tcp_v4_timewait_ack()发送ACK时会用到time_wait控制块，所以需要保持对time_wait控制块的引用。在tcp_v4_timewait_ack()中发送完ACK后，会调用inet_twsk_put()释放对time_wait控制块的引用。

OK，现在我们对TIME_WAIT状态下接收到数据包的情况有了一个了解，知道内核会如何来处理这些包。但是看到的这些更多的是以服务器端的角度来看的，如果客户端主动关闭连接的话，进入TIME_WAIT状态的是客户端。如果客户端在TIME_WAIT状态下重用端口号来和服务器建立连接，内核会如何处理呢？

我编写了一个测试程序：创建一个套接字，设置SO_REUSEADDR选项，建立连接后立即关闭，关闭后立即又重复同样的过程，发现在第二次调用connect()的时候返回EADDRNOTAVAIL错误。这个测试程序很容易理解，写起来也很容易，就不贴出来了。

要找到这个错误是怎么返回的，需要从TCP层的连接函数tcp_4_connect()开始。在tcp_v4_connect()中没有显示返回EADDRNOTAVAIL错误的地方，可能的地方就是在调用inet_hash_connect()返回的。为了确定是不是在inet_hash_connect()中返回的，使用systemtap编写了一个脚本，发现确实是在这个函数中返回的-99错误（EADDRNOTAVAIL的值为99）。其实这个通过代码也可以看出来，在这个函数之前会先查找目的主机的路由缓存项，调用的是ip_route_connect（）函数，跟着这个函数的调用轨迹，没有发现返回EADDRNOTAVAIL错误的地方。

inet_hash_connect()函数只是对`__inet_hash_connect()`函数进行了简单的封装。在`__inet_hash_connect()`中如果已绑定了端口号，并且是和其他传输控制块共享绑定的端口号，则会调用check_established参数指向的函数来检查这个绑定的端口号是否可用，代码如下所示：

```
	int __inet_hash_connect(struct inet_timewait_death_row *death_row,
			struct sock *sk, u32 port_offset,
			int (*check_established)(struct inet_timewait_death_row *,
				struct sock *, __u16, struct inet_timewait_sock **),
			void (*hash)(struct sock *sk))
	{
		struct inet_hashinfo *hinfo = death_row->hashinfo;
		const unsigned short snum = inet_sk(sk)->num;
		struct inet_bind_hashbucket *head;
		struct inet_bind_bucket *tb;
		int ret;
		struct net *net = sock_net(sk);

		if (!snum) {
			......
		}

		head = &hinfo->bhash[inet_bhashfn(net, snum, hinfo->bhash_size)];
		tb  = inet_csk(sk)->icsk_bind_hash;
		spin_lock_bh(&head->lock);
		if (sk_head(&tb->owners) == sk && !sk->sk_bind_node.next) {
			hash(sk);
			spin_unlock_bh(&head->lock);
			return 0;
		} else {
			spin_unlock(&head->lock);
			/* No definite answer... Walk to established hash table */
			ret = check_established(death_row, sk, snum, NULL);
	out:
			local_bh_enable();
			return ret;
		}
	}
```

(sk_head(&tb->owners) == sk && !sk->sk_bind_node.next)这个判断条件就是用来判断是不是只有当前传输控制块在使用已绑定的端口，条件为false时，会执行else分支，检查是否可用。这么看来，调用bind()成功并不意味着这个端口就真的可以用。

check_established参数对应的函数是__inet_check_established()，在inet_hash_connect()中可以看到。在上面的代码中我们还注意到调用check_established()时第三个参数为NULL，这在后面的分析中会用到。

`__inet_check_established()`函数中，会分别在TIME_WAIT传输控制块和除TIME_WIAT、LISTEN状态外的传输控制块中查找是已绑定的端口是否已经使用，代码片段如下所示：

```
	/* called with local bh disabled */
	static int __inet_check_established(struct inet_timewait_death_row *death_row,
						struct sock *sk, __u16 lport,
						struct inet_timewait_sock **twp)
	{
		struct inet_hashinfo *hinfo = death_row->hashinfo;
		struct inet_sock *inet = inet_sk(sk);
		__be32 daddr = inet->rcv_saddr;
		__be32 saddr = inet->daddr;
		int dif = sk->sk_bound_dev_if;
		INET_ADDR_COOKIE(acookie, saddr, daddr)
		const __portpair ports = INET_COMBINED_PORTS(inet->dport, lport);
		struct net *net = sock_net(sk);
		unsigned int hash = inet_ehashfn(net, daddr, lport, saddr, inet->dport);
		struct inet_ehash_bucket *head = inet_ehash_bucket(hinfo, hash);
		spinlock_t *lock = inet_ehash_lockp(hinfo, hash);
		struct sock *sk2;
		const struct hlist_nulls_node *node;
		struct inet_timewait_sock *tw;

		spin_lock(lock);

		/* Check TIME-WAIT sockets first. */
		sk_nulls_for_each(sk2, node, &head->twchain) {
			tw = inet_twsk(sk2);

		if (INET_TW_MATCH(sk2, net, hash, acookie,
						saddr, daddr, ports, dif)) {
				if (twsk_unique(sk, sk2, twp))
					goto unique;
				else
					goto not_unique;
			}
		}
		tw = NULL;

		/* And established part... */
		sk_nulls_for_each(sk2, node, &head->chain) {
			if (INET_MATCH(sk2, net, hash, acookie,
						saddr, daddr, ports, dif))
				goto not_unique;
		}

	unique:
		......
		return 0;

	not_unique:
		spin_unlock(lock);
		return -EADDRNOTAVAIL;
	}
```

可以看到返回EADDRNOTVAIL错误的有两种情况：

1、在TIME_WAIT传输控制块中找到匹配的端口，并且twsk_unique()返回true时

2、在除TIME_WAIT和LISTEN状态外的传输块中存在匹配的端口。

第二种情况很好容易理解了，只要状态在FIN_WAIT_1、ESTABLISHED等的传输控制块使用的端口和要查找的匹配，就会返回EADDRNOTVAIL错误。第一种情况还要取决于twsk_uniqueue()的返回值，所以接下来我们看twsk_uniqueue()中什么情况下会返回true。

如果是TCP套接字，twsk_uniqueue()中会调用tcp_twsk_uniqueue()来判断，返回true的条件如下所示：

```
	int tcp_twsk_unique(struct sock *sk, struct sock *sktw, void *twp)
	{
		const struct tcp_timewait_sock *tcptw = tcp_twsk(sktw);
		struct tcp_sock *tp = tcp_sk(sk);

		if (tcptw->tw_ts_recent_stamp &&
			(twp == NULL || (sysctl_tcp_tw_reuse &&
					get_seconds() - tcptw->tw_ts_recent_stamp > 1))) {
			......
			return 1;
		}

		return 0;
	}
```

我们前面提到过，`__inet_hash_connect()`函数调用check_established指向的函数时第三个参数为NULL，所以现在我们只需要关心tcptw->tw_ts_recent_stamp是否非零，只要这个值非零，tcp_twsk_unique()就会返回true， 在上层connect（）函数中就会返回EADDRNOTVAIL错误。tcptw->tw_ts_recent_stamp存储的是最近接收到段的时间戳值，所以正常情况下这个值不会为零。当然也可以通过调整系统的参数，让这个值可以为零，这不是本文讨论的重点，感兴趣的可以参考tcp_v4_connect()中的代码进行修改。

在导致返回EADDRNOTVAIL的两种情况中，第一种情况可以有办法避免，但是如果的第二次建立连接的时间和第一次关闭连接之间的时间间隔太小的话，此时第一个连接可能处在FIN_WAIT_1、FIN_WAIT_2等状态，此时没有系统参数可以用来避免返回EADDRNOTVAIL。如果你还是想无论如何都要在很短的时间内重用客户端的端口，这样也有办法，要么是用kprobe机制，要么用systemtap脚本，改变`__inet_check_established()`函数的返回值。


