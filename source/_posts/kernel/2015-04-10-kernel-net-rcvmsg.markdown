---
layout: post
title: "Linux TCP数据包接收处理 tcp_recvmsg"
date: 2015-04-10 15:29:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/mrpre/article/details/33347221

```
	/* 
	 *	This routine copies from a sock struct into the user buffer.
	 *
	 *	Technical note: in 2.3 we work on _locked_ socket, so that
	 *	tricks with *seq access order and skb->users are not required.
	 *	Probably, code can be easily improved even more.
	 */

	int tcp_recvmsg(struct kiocb *iocb, struct sock *sk, struct msghdr *msg,
			size_t len, int nonblock, int flags, int *addr_len)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		int copied = 0;
		u32 peek_seq;
		u32 *seq;
		unsigned long used;
		int err;
		int target;	 /* Read at least this many bytes */
		long timeo;
		struct task_struct *user_recv = NULL;
		int copied_early = 0;
		struct sk_buff *skb;
		u32 urg_hole = 0;

		//功能：“锁住sk”，并非真正的加锁，而是执行sk->sk_lock.owned = 1 
		//目的：这样软中断上下文能够通过owned ，判断该sk是否处于进程上下文。
		//提供一种同步机制。
		lock_sock(sk);

		TCP_CHECK_TIMER(sk);

		err = -ENOTCONN;
		if (sk->sk_state == TCP_LISTEN)
			goto out;

		//获取延迟，如果用户设置为非阻塞，那么timeo ==0000 0000 0000 0000
		//如果用户使用默认recv系统调用
		//则为阻塞，此时timeo ==0111 1111 1111 1111
		//timeo 就2个值
		timeo = sock_rcvtimeo(sk, nonblock);

		/* Urgent data needs to be handled specially. */
		if (flags & MSG_OOB)
			goto recv_urg;

		//待拷贝的下一个序列号
		seq = &tp->copied_seq;

		//设置了MSG_PEEK，表示不让数据从缓冲区移除，目的是下一次调用recv函数
		//仍然能够读到相同数据
		if (flags & MSG_PEEK) {
			peek_seq = tp->copied_seq;
			seq = &peek_seq;
		}

		//如果设置了MSG_WAITALL，则target  ==len，即recv函数中的参数len
		//如果没设置MSG_WAITALL，则target  == 1
		target = sock_rcvlowat(sk, flags & MSG_WAITALL, len);

		//大循环
		do {
			u32 offset;

			/* Are we at urgent data? Stop if we have read anything or have SIGURG pending. */
			if (tp->urg_data && tp->urg_seq == *seq) {
				if (copied)
					break;
				if (signal_pending(current)) {
					copied = timeo ? sock_intr_errno(timeo) : -EAGAIN;
					break;
				}
			}

			/* Next get a buffer. */

			//小循环
			skb_queue_walk(&sk->sk_receive_queue, skb) {
				/* Now that we have two receive queues this
					* shouldn't happen.
					*/
				if (WARN(before(*seq, TCP_SKB_CB(skb)->seq),
									KERN_INFO "recvmsg bug: copied %X "
												"seq %X rcvnxt %X fl %X\n", *seq,
												TCP_SKB_CB(skb)->seq, tp->rcv_nxt,
												flags))
					break;

				//如果用户的缓冲区(即用户malloc的buf)长度够大，offset一般是0。
				//即 “下次准备拷贝数据的序列号”==此时获取报文的起始序列号
				//什么情况下offset >0呢？很简答，如果用户缓冲区12字节，而这个skb有120字节
				//那么一次recv系统调用，只能获取skb中的前12个字节，下一次执行recv系统调用
				//offset就是12了，offset表示从第12个字节开始读取数据，前12个字节已经读取了。
				//那这个"已经读取12字节"这个消息，存在哪呢？
				//在*seq = &tp->copied_seq;中
				offset = *seq - TCP_SKB_CB(skb)->seq;
				if (tcp_hdr(skb)->syn)
					offset--;
				if (offset < skb->len)
					goto found_ok_skb;
				if (tcp_hdr(skb)->fin)
					goto found_fin_ok;
				WARN(!(flags & MSG_PEEK), KERN_INFO "recvmsg bug 2: "
						"copied %X seq %X rcvnxt %X fl %X\n",
						*seq, TCP_SKB_CB(skb)->seq,
						tp->rcv_nxt, flags);
			}

			//执行到了这里，表明小循环中break了，既然break了，说明sk_receive_queue中
			//已经没有skb可以读取了
			//如果没有执行到这里说明前面的小循环中执行了goto，读到有用的skb，或者读到fin都会goto。
			//没有skb可以读取，说明什么？
			//可能性1：当用户第一次调用recv时，压根没有数据到来
			//可能性2：skb->len一共20字节，假设用户调用一次 recv，读取12字节，再调用recv，
			//读取12字节，此时skb由于上次已经被读取了12字节，只剩下8字节。
			//于是代码的逻辑上，再会要求获取skb，来读取剩下的8字节。

			//可能性1的情况下，copied == 0，肯定不会进这个if。后续将执行休眠
			//可能性2的情况下，情况比较复杂。可能性2表明数据没有读够用户想要的len长度
			//虽然进程上下文中，没有读够数据，但是可能我们在读数据的时候
			//软中断把数据放到backlog队列中了，而backlog对队列中的数据或许恰好让我们读够数
			//据。

			//copied了数据的，copied肯定>=1，而target 是1或者len
			//copied只能取0(可能性1)，或者0~len(可能性2)
			//copied >= target 表示我们取得我们想要的数据了，何必进行休眠，直接return
			//如果copied 没有达到我们想要的数据，则看看sk_backlog是否为空
			//空的话，尽力了，只能尝试休眠
			//非空的话，还有一线希望，我们去sk_backlog找找数据，看看是否能够达到我们想要的
			//数据大小

			//我觉得copied == target是会出现的，但是出现的话，也不会进现在这个流程
			//，如有不对，请各位大神指正，告诉我
			//说明情况下copied == target

			/* Well, if we have backlog, try to process it now yet. */
			if (copied >= target && !sk->sk_backlog.tail)
				break;


			if (copied) {
				//可能性2，拷贝了数据，但是没有拷贝到指定大小
				if (sk->sk_err ||
								sk->sk_state == TCP_CLOSE ||
								(sk->sk_shutdown & RCV_SHUTDOWN) ||
								!timeo ||
								signal_pending(current))
					break;
			} else {
				//可能性1
				if (sock_flag(sk, SOCK_DONE))
					break;

				if (sk->sk_err) {
					copied = sock_error(sk);
					break;
				}

				if (sk->sk_shutdown & RCV_SHUTDOWN)
					break;

				if (sk->sk_state == TCP_CLOSE) {
					if (!sock_flag(sk, SOCK_DONE)) {
						/* This occurs when user tries to read
							* from never connected socket.
							*/
						copied = -ENOTCONN;
						break;
					}
					break;
				}

				//是否是阻塞的，不是，就return了。
				if (!timeo) {
					copied = -EAGAIN;
					break;
				}

				if (signal_pending(current)) {
					copied = sock_intr_errno(timeo);
					break;
				}
			}

			tcp_cleanup_rbuf(sk, copied);

			//sysctl_tcp_low_latency 默认0tp->ucopy.task == user_recv肯定也成立

			if (!sysctl_tcp_low_latency && tp->ucopy.task == user_recv) {
				/* Install new reader */
				if (!user_recv && !(flags & (MSG_TRUNC | MSG_PEEK))) {
					user_recv = current;
					tp->ucopy.task = user_recv;
					tp->ucopy.iov = msg->msg_iov;
				}

				tp->ucopy.len = len;

				WARN_ON(tp->copied_seq != tp->rcv_nxt &&
					!(flags & (MSG_PEEK | MSG_TRUNC)));

				/* Ugly... If prequeue is not empty, we have to
					* process it before releasing socket, otherwise
					* order will be broken at second iteration.
					* More elegant solution is required!!!
					*
					* Look: we have the following (pseudo)queues:
					*
					* 1. packets in flight
					* 2. backlog
					* 3. prequeue
					* 4. receive_queue
					*
					* Each queue can be processed only if the next ones
					* are empty. At this point we have empty receive_queue.
					* But prequeue _can_ be not empty after 2nd iteration,
					* when we jumped to start of loop because backlog
					* processing added something to receive_queue.
					* We cannot release_sock(), because backlog contains
					* packets arrived _after_ prequeued ones.
					*
					* Shortly, algorithm is clear --- to process all
					* the queues in order. We could make it more directly,
					* requeueing packets from backlog to prequeue, if
					* is not empty. It is more elegant, but eats cycles,
					* unfortunately.
					*/

				if (!skb_queue_empty(&tp->ucopy.prequeue))
					goto do_prequeue;

				/* __ Set realtime policy in scheduler __ */
			}

			if (copied >= target) {
				/* Do not sleep, just process backlog. */
				release_sock(sk);
				lock_sock(sk);
			} else
						sk_wait_data(sk, &timeo); 
			//在此处睡眠了，将在tcp_prequeue函数中调用wake_up_interruptible_poll唤醒
			
			//软中断会判断用户是正在读取检查并且睡眠了，如果是的话，就直接把数据拷贝
			//到prequeue队列，然后唤醒睡眠的进程。因为进程睡眠，表示没有读到想要的字节数
			//此时，软中断有数据到来，直接给进程，这样进程就能以最快的速度被唤醒。


			if (user_recv) {
				int chunk;

				/* __ Restore normal policy in scheduler __ */

				if ((chunk = len - tp->ucopy.len) != 0) {
					NET_ADD_STATS_USER(sock_net(sk), LINUX_MIB_TCPDIRECTCOPYFROMBACKLOG, chunk);
					len -= chunk;
					copied += chunk;
				}

				if (tp->rcv_nxt == tp->copied_seq &&
								!skb_queue_empty(&tp->ucopy.prequeue)) {
	do_prequeue:
					tcp_prequeue_process(sk);

					if ((chunk = len - tp->ucopy.len) != 0) {
						NET_ADD_STATS_USER(sock_net(sk), LINUX_MIB_TCPDIRECTCOPYFROMPREQUEUE, chunk);
						len -= chunk;
						copied += chunk;
					}
				}
			}
			if ((flags & MSG_PEEK) &&
							(peek_seq - copied - urg_hole != tp->copied_seq)) {
				if (net_ratelimit())
					printk(KERN_DEBUG "TCP(%s:%d): Application bug, race in MSG_PEEK.\n",
												current->comm, task_pid_nr(current));
				peek_seq = tp->copied_seq;
			}
			continue;

		found_ok_skb:
			/* Ok so how much can we use? */
			//skb中还有多少聚聚没有拷贝。
			//正如前面所说的，offset是上次已经拷贝了的，这次从offset开始接下去拷贝
					used = skb->len - offset;
			//很有可能used的大小，即skb剩余长度，依然大于用户的缓冲区大小(len)。所以依然
			//只能拷贝len长度。一般来说，用户还得执行一次recv系统调用。直到skb中的数据读完
			if (len < used)
				used = len;

			/* Do we have urgent data here? */
			if (tp->urg_data) {
				u32 urg_offset = tp->urg_seq - *seq;
				if (urg_offset < used) {
					if (!urg_offset) {
						if (!sock_flag(sk, SOCK_URGINLINE)) {
							++*seq;
							urg_hole++;
							offset++;
							used--;
							if (!used)
								goto skip_copy;
						}
					} else
						used = urg_offset;
				}
			}

			if (!(flags & MSG_TRUNC)) {
				{
					//一般都会进这个if，进行数据的拷贝，把能够读到的数据，放到用户的缓冲区
					err = skb_copy_datagram_iovec(skb, offset,
							msg->msg_iov, used);
					if (err) {
						/* Exception. Bailout! */
						if (!copied)
							copied = -EFAULT;
						break;
					}
				}
			}

			//更新标志位，seq 是指针，指向了tp->copied_seq
			//used是我们有能力拷贝的数据大小，即已经拷贝到用户缓冲区的大小
			//正如前面所说，如果用户的缓冲区很小，一次recv拷贝不玩skb中的数据，
			//我们需要保存已经拷贝了的大小，下次recv时，从这个大小处继续拷贝。
			//所以需要更新copied_seq。
			*seq += used;
			copied += used;
			len -= used;

			tcp_rcv_space_adjust(sk);

	skip_copy:
			if (tp->urg_data && after(tp->copied_seq, tp->urg_seq)) {
				tp->urg_data = 0;
				tcp_fast_path_check(sk);
			}

			//这个就是判断我们是否拷贝完了skb中的数据，如果没有continue
			//这种情况下，len经过 len -= used; ，已经变成0，所以continue的效果相当于
			//退出了这个大循环。可以理解，你只能拷贝len长度，拷贝完之后，那就return了。

			//还有一种情况used + offset ==  skb->len，表示skb拷贝完了。这时我们只需要释放skb
			//下面会讲到
			if (used + offset < skb->len)
				continue;

			//看看这个数据报文是否含有fin，含有fin，则goto到found_fin_ok
			if (tcp_hdr(skb)->fin)
				goto found_fin_ok;

			//执行到这里，标明used + offset ==  skb->len，报文也拷贝完了，那就把skb摘链释放
			if (!(flags & MSG_PEEK)) {
				sk_eat_skb(sk, skb, copied_early);
				copied_early = 0;
			}
			//这个cintinue不一定是退出大循环，可能还会执行循环。
			//假设用户设置缓冲区12字节，你skb->len长度20字节。
			//第一次recv读取了12字节，skb剩下8，下一次调用recv再想读取12，
			//但是只能读取到这8字节了。
			//此时len 变量长度为4，那么这个continue依旧在这个循环中，
			//函数还是再次从do开始，使用skb_queue_walk，找skb
			//如果sk_receive_queue中skb仍旧有，那么继续读，直到len == 0
			//如果没有skb了，我们怎么办？我们的len还有4字节怎么办？
			//这得看用户设置的recv函数阻塞与否，即和timeo变量相关了。
			continue;

		found_fin_ok:
			/* Process the FIN. */
			++*seq;
			if (!(flags & MSG_PEEK)) {
				//把skb从sk_receive_queue中摘链
				sk_eat_skb(sk, skb, copied_early);
				copied_early = 0;
			}
			break;
		} while (len > 0);

		//到这里是大循环退出
		//休眠过的进程，然后退出大循环 ，才满足 if (user_recv) 条件
		if (user_recv) {
			if (!skb_queue_empty(&tp->ucopy.prequeue)) {
				int chunk;

				tp->ucopy.len = copied > 0 ? len : 0;

				tcp_prequeue_process(sk);

				if (copied > 0 && (chunk = len - tp->ucopy.len) != 0) {
					NET_ADD_STATS_USER(sock_net(sk), LINUX_MIB_TCPDIRECTCOPYFROMPREQUEUE, chunk);
					len -= chunk;
					copied += chunk;
				}
			}

			//数据读取完毕，清零
			tp->ucopy.task = NULL;
			tp->ucopy.len = 0;
		}

		/* According to UNIX98, msg_name/msg_namelen are ignored
			* on connected socket. I was just happy when found this 8) --ANK
			*/

		/* Clean up data we have read: This will do ACK frames. */
		//很重要，将更新缓存，并且适当的时候发送ack
		tcp_cleanup_rbuf(sk, copied);

		TCP_CHECK_TIMER(sk);
		release_sock(sk);
		return copied;

	out:
		TCP_CHECK_TIMER(sk);
		release_sock(sk);
		return err;

	recv_urg:
		err = tcp_recv_urg(sk, msg, len, flags);
		goto out;
	}
```

