---
layout: post
title: "tcp三个接收队列"
date: 2015-05-11 15:46:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~net
tags:
---
http://www.cnblogs.com/alreadyskb/p/4386565.html

#### 三个接收队列

* tcp协议栈数据接收实现了三个接收缓存分别是prequeue、sk_write_queue、sk_backlog。

之所以需要三个接收缓存的原因如下：  
tcp协议栈接收到数据包时struct sock *sk 可能被进程下上文或者中断上下文占用：

  1、如果处于进程上下文sk_lock.owned=1，软中断因为sk_lock.owned=1，所以数据只能暂存在后备队列中（backlog），当进程上下文逻辑处理完成后会回调tcp_v4_do_rcv处理backlog队列作为补偿，具体看tcp_sendmsg 函数 release_sock的实现。

  2、如果当前处于中断上下文，sk_lock.owned=0，那么数据可能被放置到receive_queue或者prequeue，数据优先放置到prequeue中，如果prequeue满了则会放置到receive_queue中，理论上这里有一个队列就行了，但是TCP协议栈为什么要设计两个呢？其实是为了快点结束软中断数据处理流程，软中断处理函数中禁止了进程抢占和其他软中断发生，效率应该是很低下的，如果数据被放置到prequeue中，那么软中断流程很快就结束了，如果放置到receive_queue那么会有很复杂的逻辑需要处理。receive_queue队列的处理在软中断中，prequeue队列的处理则是在进程上下文中。总的来说就是为了提高TCP协议栈的效率。

#### 后备队列的处理逻辑
##### 1、什么时候使用后备队列
tcp协议栈对struct sock *sk有两把锁，第一把是sk_lock.slock，第二把则是sk_lock.owned。sk_lock.slock用于获取struct sock *sk对象的成员的修改权限；sk_lock.owned用于区分当前是进程上下文或是软中断上下文，为进程上下文时sk_lock.owned会被置1，中断上下文为0。

如果是要对sk修改，首先是必须拿锁sk_lock.slock，其后是判断当前是软中断或是进程上下文，如果是进程上下文，那么接收到的skb则只能先放置到后备队列中sk_backlog中。如果是软中断上下文则可以放置到prequeue和sk_write_queue中。

代码片段如下：
```
		bh_lock_sock_nested(sk);               // 获取第一把锁。
		ret = 0;
		if (!sock_owned_by_user(sk)) {         // 判断第二把锁，区分是处于进程上下文还是软中断上下文。
	#ifdef CONFIG_NET_DMA
			struct tcp_sock *tp = tcp_sk(sk);
			if (!tp->ucopy.dma_chan && tp->ucopy.pinned_list)
				tp->ucopy.dma_chan = dma_find_channel(DMA_MEMCPY);
			if (tp->ucopy.dma_chan)
				ret = tcp_v4_do_rcv(sk, skb);
			else
	#endif
			{
				if (!tcp_prequeue(sk, skb))    // 如果处于中断上下文，则优先放置到prequeue中，如果prequeue满则放置到sk_write_queue中。
					ret = tcp_v4_do_rcv(sk, skb);
			}
		} else if (unlikely(sk_add_backlog(sk, skb,  // 如果是处于进程上下文则直接放置到后备队列中(sk_backlog中)。
							sk->sk_rcvbuf + sk->sk_sndbuf))) {
			bh_unlock_sock(sk);
			NET_INC_STATS_BH(net, LINUX_MIB_TCPBACKLOGDROP);
			goto discard_and_relse;
		}
		bh_unlock_sock(sk);
```

##### 2、skb怎么add到sk_backlog中

sk_add_backlog函数用于add sbk到sk_backlog中，所以下面我们分析次函数。
```
	/* The per-socket spinlock must be held here. */
	static inline __must_check int sk_add_backlog(struct sock *sk, struct sk_buff *skb,
							   unsigned int limit)
	{
		if (sk_rcvqueues_full(sk, skb, limit))  // 判断接收缓存是否已经用完了，很明显sk_backlog的缓存大小也算在了总接收缓存中。
			return -ENOBUFS;

		__sk_add_backlog(sk, skb);              // 将skb添加到sk_backlog队列中。
		sk_extended(sk)->sk_backlog.len += skb->truesize;  // 更新sk_backlog中已经挂载的数据量。
		return 0;
	}
```

```
	/* OOB backlog add */
	static inline void __sk_add_backlog(struct sock *sk, struct sk_buff *skb)
	{
		if (!sk->sk_backlog.tail) {   // 如果当前sk_backlog为NULL，此时head和tail都指向skb。
			sk->sk_backlog.head = sk->sk_backlog.tail = skb;
		} else {                      // 分支表示sk_backlog中已经有数据了，那么skb直接挂在tail的尾部，之后tail指针后移到skb。
			sk->sk_backlog.tail->next = skb;
			sk->sk_backlog.tail = skb;
		}
		skb->next = NULL;             // 这种很重要，在sk_backlog处理时会用来判断skb是否处理完毕。
	}
```

##### 3、sk_backlog中skb的处理

很明显sk_backlog的处理必然中进程上下文进行，对于数据接收，进程上下文的接口是tcp_recvmmsg，所以sk_backlog肯定要在tcp_recvmmsg中处理。

tcp_recvmmsg sk_backlog的代码处理片段如下：
``` 
	tcp_cleanup_rbuf(sk, copied);
	TCP_CHECK_TIMER(sk);
	release_sock(sk);
```

release_sock(sk)涉及到sk_backlog处理。

```
	void release_sock(struct sock *sk)
	{
		/*
		* The sk_lock has mutex_unlock() semantics:
		*/
		mutex_release(&sk->sk_lock.dep_map, 1, _RET_IP_);

		spin_lock_bh(&sk->sk_lock.slock);   // 获取第一把锁。
		if (sk->sk_backlog.tail)            // 如果后备队列不为NULL，则开始处理。
			__release_sock(sk);

		if (proto_has_rhel_ext(sk->sk_prot, RHEL_PROTO_HAS_RELEASE_CB) &&
				sk->sk_prot->release_cb)
			sk->sk_prot->release_cb(sk);

		sk->sk_lock.owned = 0;              // 进成上下文skb处理完了，释放第二把锁。
		if (waitqueue_active(&sk->sk_lock.wq))
			wake_up(&sk->sk_lock.wq);
		spin_unlock_bh(&sk->sk_lock.slock); // 释放第一把锁。
	}
```

`__release_sock(sk)`是后备队列的真正处理函数。

``` 
	static void __release_sock(struct sock *sk)
	{
		struct sk_buff *skb = sk->sk_backlog.head;

		do {
			sk->sk_backlog.head = sk->sk_backlog.tail = NULL;
			bh_unlock_sock(sk);

			do {
				struct sk_buff *next = skb->next;

				skb->next = NULL;
				sk_backlog_rcv(sk, skb);    // skb的处理函数，其实调用的是tcp_v4_do_rcv函数。

				/*
				 * We are in process context here with softirqs
				 * disabled, use cond_resched_softirq() to preempt.
				 * This is safe to do because we've taken the backlog
				 * queue private:
				 */
				cond_resched_softirq();

				skb = next;
			} while (skb != NULL);          // 如果skb=NULL，那么说明之前的sk_backlog已经处理完了。

			bh_lock_sock(sk);
		} while ((skb = sk->sk_backlog.head) != NULL); // 在处理上一个sk_backlog时，可能被软中断中断了，建立了新的sk_backlog，新建立的sk_backlog也将一并被处理。

		/*
		* Doing the zeroing here guarantee we can not loop forever
		* while a wild producer attempts to flood us.
		*/
		sk_extended(sk)->sk_backlog.len = 0;
	}
```
  一开始重置sk->sk_backlog.head ，sk->sk_backlog.tail为NULL。sk_backlog是一个双链表，head指向了链表头部的skb，而tail则指向了链表尾部的skb。这里之所以置NULL head 和tail，是因为struct sk_buff *skb = sk->sk_backlog.head 提前取到了head指向的skb，之后就可以通过skb->next来获取下一个skb处理，结束的条件是skb->next=NULL，这个是在`__sk_add_backlog`函数中置位的，也就说对于sk_backlog的处理head和tail指针已经没有用了。

  为什么要置NULLsk->sk_backlog.head ，sk->sk_backlog.tail呢？第一想法是它可能要被重新使用了。那么在什么情况下会被重新使用呢？试想一下当前是在进程上下文，并且sk->sk_lock.slock没有被锁住，那是不是可能被软中断打断呢？如果被软中断打断了是不是要接收数据呢，tcp协议栈为了效率考虑肯定是要接收数据的，前面分析道这种情况的数据必须放置到后备队列中(sk_backlog)，所以可以肯定置NULL sk->sk_backlog.head ，sk->sk_backlog.tail是为了在处理上一个sk_backlog时，能重用sk_backlog，建立一条新的sk_backlog，或许有人会问为什么不直接添加到原先的sk_backlog tail末尾呢？这个问题我也没有想太清楚，或许是同步不好做吧。

##### 4、skb被处理到哪去了
  很明显接收的数据最终都将被传递到应用层，在传递到应用层前必须要保证三个接收队列中的数据有序，那么这三个队列是怎么保证数据字节流有序的被递交给应用层呢？三个队列都会调用tcp_v4_do_rcv函数，prequeue和sk_backlog是在tcp_recvmsg中调用tcp_v4_do_rcv函数，也就是进程上下文中调用tcp_v4_do_rcv函数。

  如果仔细分析tcp_v4_do_rcv函数能发现，这个函数能保证数据有序的排列在一起，所以无论是在处理sk_backlog还是prequeue，最终都会调用tcp_v4_do_rcv函数将数据有效地插入到sk_write_queue中，最后被应用层取走。


