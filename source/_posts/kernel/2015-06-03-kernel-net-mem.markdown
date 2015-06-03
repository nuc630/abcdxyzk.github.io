---
layout: post
title: "内核协议栈tcp层的内存管理"
date: 2015-06-03 14:25:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://simohayha.iteye.com/blog/532450

http://www.ibm.com/developerworks/cn/linux/l-hisock.html#table1

http://blog.csdn.net/russell_tao/article/details/18711023

我们先来看tcp内存管理相关的几个内核参数,这些都能通过proc文件系统来修改:
```
	// 内核写buf的最大值.
	extern __u32 sysctl_wmem_max;
	// 协议栈读buf的最大值
	extern __u32 sysctl_rmem_max;
```

这两个值在/proc/sys/net/core 下。这里要注意，这两个值的单位是字节。

它们的初始化在sk_init里面,这里可以看到这两个值的大小是依赖于num_physpages的，而这个值应该是物理页数。也就是说这两个值依赖于物理内存：

```
	void __init sk_init(void)
	{
		if (num_physpages <= 4096) {
			sysctl_wmem_max = 32767;
			sysctl_rmem_max = 32767;
			sysctl_wmem_default = 32767;
			sysctl_rmem_default = 32767;
		} else if (num_physpages >= 131072) {
			sysctl_wmem_max = 131071;
			sysctl_rmem_max = 131071;
		}
	}
```

而我通过搜索源码，只有设置套接口选项的时候，才会用到这两个值，也就是setsockopt，optname为SO_SNDBUF或者SO_RCVBUF时，来限制设置的值:

```
	case SO_SNDBUF:
			if (val > sysctl_wmem_max)
				val = sysctl_wmem_max;
```

接下来就是整个tcp协议栈的socket的buf限制(也就是所有的socket).
这里要注意，这个东西的单位都是以页为单位的，我们下面就会看到。
```
	其中sysctl_tcp_mem[0]表示整个tcp sock的buf限制.
	sysctl_tcp_mem[1]也就是tcp sock内存使用的警戒线.
	sysctl_tcp_mem[2]也就是tcp sock内存使用的hard limit,当超过这个限制,我们就要禁止再分配buf.
	extern int sysctl_tcp_mem[3];
```

接下来就是针对每个sock的读写buf限制。
```
	// 其中依次为最小buf,中等buf,以及最大buf.
	extern int sysctl_tcp_wmem[3];
	extern int sysctl_tcp_rmem[3];
```

#### tcp_init

这几个值的初始化在tcp_init里面，这里就能清晰的看到sysctl_tcp_mem的单位是页。而sysctl_tcp_wmem和sysctl_tcp_rmem的单位是字节。

```
	void __init tcp_init(void)
	{
		.................................
		// nr_pages就是页。
		nr_pages = totalram_pages - totalhigh_pages;
		limit = min(nr_pages, 1UL<<(28-PAGE_SHIFT)) >> (20-PAGE_SHIFT);
		limit = (limit * (nr_pages >> (20-PAGE_SHIFT))) >> (PAGE_SHIFT-11);
		limit = max(limit, 128UL);
		sysctl_tcp_mem[0] = limit / 4 * 3;
		sysctl_tcp_mem[1] = limit;
		sysctl_tcp_mem[2] = sysctl_tcp_mem[0] * 2;

		/* Set per-socket limits to no more than 1/128 the pressure threshold */
		// 转换为字节。
		limit = ((unsigned long)sysctl_tcp_mem[1]) << (PAGE_SHIFT - 7);
		max_share = min(4UL*1024*1024, limit);

		sysctl_tcp_wmem[0] = SK_MEM_QUANTUM;
		sysctl_tcp_wmem[1] = 16*1024;
		sysctl_tcp_wmem[2] = max(64*1024, max_share);

		sysctl_tcp_rmem[0] = SK_MEM_QUANTUM;
		sysctl_tcp_rmem[1] = 87380;
		sysctl_tcp_rmem[2] = max(87380, max_share);
		................................
	}
```


然后就是读写buf的最小值
```
	#define SOCK_MIN_SNDBUF 2048
	#define SOCK_MIN_RCVBUF 256
```

最后就是当前tcp协议栈已经分配了的buf的总大小。这里要注意，这个值也是以页为单位的。
```
	atomic_t tcp_memory_allocated
```

而上面的这些值如何与协议栈关联起来呢，我们来看tcp_prot结构，可以看到这些值的地址都被放到对应的tcp_prot的域。

```
	struct proto tcp_prot = {
		.name = "TCP",
		.owner = THIS_MODULE,
		...................................................
		.enter_memory_pressure = tcp_enter_memory_pressure,
		.sockets_allocated = &tcp_sockets_allocated,
		.orphan_count = &tcp_orphan_count,
		.memory_allocated = &tcp_memory_allocated,
		.memory_pressure = &tcp_memory_pressure,
		.sysctl_mem = sysctl_tcp_mem,
		.sysctl_wmem = sysctl_tcp_wmem,
		.sysctl_rmem = sysctl_tcp_rmem,
		........................................................
	};
```


而对应的sock域中的几个值，这几个域非常重要，我们来看他们表示的含义

sk_rcvbuf和sk_sndbuf,这两个值分别代表每个sock的读写buf的最大限制

sk_rmem_alloc和sk_wmem_alloc这两个值分别代表已经提交的数据包的字节数。

读buf意味着进入tcp层的数据大小，而当数据提交给用户空间之后，这个值会相应的减去提交的大小（也就类似写buf的sk_wmem_queued)。

写buf意味着提交给ip层。可以看到这个值的增加是在tcp_transmit_skb中进行的。

而sk_wmem_queued也就代表skb的写队列write_queue的大小。

还有一个sk_forward_alloc，这个值表示一个预分配置，也就是整个tcp协议栈的内存cache，第一次为一个缓冲区分配buf的时候，我们不会直接分配精确的大小，而是按页来分配，而分配的大小就是这个值，下面我们会看到这个。并且这个值初始是0.


```
	struct sock {
		int sk_rcvbuf;
		atomic_t sk_rmem_alloc;
		atomic_t sk_wmem_alloc;
		int sk_forward_alloc;
		..........................
		int sk_sndbuf;
		// 这个表示写buf已经分配的字节长度
		int sk_wmem_queued;
		...........................
	}
```

sk_sndbuf和sk_rcvbuf,这两个的初始化在这里：
```
	static int tcp_v4_init_sock(struct sock *sk)
	{
		..................................
		sk->sk_sndbuf = sysctl_tcp_wmem[1];
		sk->sk_rcvbuf = sysctl_tcp_rmem[1];
		..........................
	}
```

而当进入establish状态之后,sock会自己调整sndbuf和rcvbuf.他是通过tcp_init_buffer_space来进行调整的.这个函数会调用tcp_fixup_rcvbuf和tcp_fixup_sndbuf来调整读写buf的大小.

这里有用到sk_userlock这个标记，这个标记主要就是用来标记SO_SNDBUF 和SO_RCVBUF套接口选项是否被设置。而是否设置对应的值为：

```
	#define SOCK_SNDBUF_LOCK	1
	#define SOCK_RCVBUF_LOCK	2
```

我们可以看下面的设置SO_SNDBUF 和SO_RCVBUF的代码片断：

```
	// 首先设置sk_userlocks.
	sk->sk_userlocks |= SOCK_SNDBUF_LOCK;
	if ((val * 2) < SOCK_MIN_SNDBUF)
		sk->sk_sndbuf = SOCK_MIN_SNDBUF;
	else
		sk->sk_sndbuf = val * 2;
```


因此内核里面的处理是这样的，如果用户已经通过套接字选项设置了读或者写buf的大小，那么这里将不会调整读写buf的大小，否则就进入tcp_fixup_XXX来调整大小。

还有一个要注意的就是MAX_TCP_HEADER，这个值表示了TCP + IP + link layer headers 以及option的长度。

我们来看代码。

```
	static void tcp_init_buffer_space(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		int maxwin;

		// 判断sk_userlocks，来决定是否需要fix缓冲区大小。
		if (!(sk->sk_userlocks & SOCK_RCVBUF_LOCK))
			tcp_fixup_rcvbuf(sk);
		if (!(sk->sk_userlocks & SOCK_SNDBUF_LOCK))
			tcp_fixup_sndbuf(sk);
	......................................

	}
```

接下来来看这两个函数如何来调整读写buf的大小，不过这里还有些疑问，就是为什么是要和3*sndmem以及4*rcvmem：

```
	static void tcp_fixup_sndbuf(struct sock *sk)
	{
		// 首先通过mss，tcp头，以及sk_buff的大小，得到一个最小范围的sndmem。
		int sndmem = tcp_sk(sk)->rx_opt.mss_clamp + MAX_TCP_HEADER + 16 +sizeof(struct sk_buff);

		// 然后取sysctl_tcp_wmem[2]和3倍的sndmem之间的最小值。
		if (sk->sk_sndbuf < 3 * sndmem)
			sk->sk_sndbuf = min(3 * sndmem, sysctl_tcp_wmem[2]);
	}

	static void tcp_fixup_rcvbuf(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		// 这里和上面类似，也是先得到最小的一个rcvmem段。
		int rcvmem = tp->advmss + MAX_TCP_HEADER + 16 + sizeof(struct sk_buff);

		/* Try to select rcvbuf so that 4 mss-sized segments
		 * will fit to window and corresponding skbs will fit to our rcvbuf.
		 * (was 3; 4 is minimum to allow fast retransmit to work.)
		 */
		// 这里则是通过sysctl_tcp_adv_win_scale来调整rcvmem的值。
		while (tcp_win_from_space(rcvmem) < tp->advmss)
			rcvmem += 128;
		if (sk->sk_rcvbuf < 4 * rcvmem)
			sk->sk_rcvbuf = min(4 * rcvmem, sysctl_tcp_rmem[2]);
	}
```

ok，看完初始化，我们来看协议栈具体如何管理内存的，先来看发送端，发送端的主要实现是在tcp_sendmsg里面，这个函数我们前面已经详细的分析过了，我们这次只分析里面几个与内存相关的东西。

来看代码片断：

```
	int tcp_sendmsg(struct kiocb *iocb, struct socket *sock, struct msghdr *msg,
			size_t size)
	{
		..................................

		if (copy <= 0) {
	new_segment:
			if (!sk_stream_memory_free(sk))
				goto wait_for_sndbuf;

			skb = sk_stream_alloc_skb(sk, select_size(sk),
			sk->sk_allocation);
			if (sk->sk_route_caps & NETIF_F_ALL_CSUM)
				skb->ip_summed = CHECKSUM_PARTIAL;

			skb_entail(sk, skb);
			copy = size_goal;
			max = size_goal;
		..................
	}
```


可以看到这里第一个sk_stream_memory_free用来判断是否还有空间来供我们分配，如果没有则跳到wait_for_sndbuf来等待buf的释放。

然后如果有空间供我们分配，则调用sk_stream_alloc_skb来分配一个skb，然后这个大小的选择是通过select_size。

最后调用skb_entail来更新相关的域。

现在我们就来详细看上面的四个函数,先来看第一个：

```
	static inline int sk_stream_memory_free(struct sock *sk)
	{
		return sk->sk_wmem_queued < sk->sk_sndbuf;
	}
```


sk_stream_memory_free实现很简单，就是判断当前已经分配的写缓冲区的大小(sk_wmem_queued)是否小于当前写缓冲区(sk_sndbuf)的最大限制。

然后是skb_entail，这个函数主要是当我们分配完buf后，进行一些相关域的更新，以及添加skb到writequeue。

```
	static inline void skb_entail(struct sock *sk, struct sk_buff *skb)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct tcp_skb_cb *tcb = TCP_SKB_CB(skb);
		............................
		skb_header_release(skb);
		tcp_add_write_queue_tail(sk, skb);
		// 增加sk_wmem_queued.
		sk->sk_wmem_queued += skb->truesize;
		// 这里调整sk_forward_alloc的大小，也就是预分配buf的大小(减小).
		sk_mem_charge(sk, skb->truesize);
		if (tp->nonagle & TCP_NAGLE_PUSH)
			tp->nonagle &= ~TCP_NAGLE_PUSH;
	}
	// 这个函数很简单，就是将sk_forward_alloc - size.
	static inline void sk_mem_charge(struct sock *sk, int size)
	{
		if (!sk_has_account(sk))
			return;
		sk->sk_forward_alloc -= size;
	}
```


然后是select_size，在看这个之前我们先来坎SKB_MAX_HEAD的实现.
SKB_MAX_HEAD主要是得到要分配的tcp数据段（不包括头)在一页中最大为多少。

```
	#define SKB_WITH_OVERHEAD(X)	\
		((X) - SKB_DATA_ALIGN(sizeof(struct skb_shared_info)))
	#define SKB_MAX_ORDER(X, ORDER) \
		SKB_WITH_OVERHEAD((PAGE_SIZE << (ORDER)) - (X))
	#define SKB_MAX_HEAD(X)	 (SKB_MAX_ORDER((X), 0))
```


我们带入代码来看，我们下面的代码是SKB_MAX_HEAD(MAX_TCP_HEADER)，展开这个宏可以看到就是PAGE_SIZE-MAX_TCP_HEADER-SKB_DATA_ALIGN(sizeof(struct skb_shared_info).其实也就是一页还能容纳多少tcp的数据。

```
	static inline int select_size(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		// 首先取得存储的mss。
		int tmp = tp->mss_cache;

		// 然后判断是否使用scatter–gather(前面blog有介绍)
		if (sk->sk_route_caps & NETIF_F_SG) {
			if (sk_can_gso(sk))
				tmp = 0;
			else {
				// 然后开始计算buf的长度。
				int pgbreak = SKB_MAX_HEAD(MAX_TCP_HEADER);

				// 如果mss大于pgbreak,那么说明我们一页放不下当前需要的tcp数据，因此我们将会在skb的页区域分配，而skb的页区域是有限制的，因此tmp必须小于这个值。
				if (tmp >= pgbreak &&
						tmp <= pgbreak + (MAX_SKB_FRAGS - 1) * PAGE_SIZE)
					tmp = pgbreak;
			}
		}

		return tmp;
	}
```


#### sk_stream_alloc_skb

接下来来看sk_stream_alloc_skb的实现。

1 它会调用alloc_skb_fclone来分配内存，这个函数就不详细分析了，我们只需要知道它会从slab里分配一块内存，而大小为size+max_header(上面的分析我们知道slect_size只计算数据段).

2 如果分配成功，则调用sk_wmem_schedule来判断我们所分配的skb的大小是否精确，是的话，就调整指针，然后返回。

3 否则调用tcp_enter_memory_pressure设置标志进入TCP memory pressure zone。然后再调用sk_stream_moderate_sndbuf调整sndbuf(缩小sndbuf)。

```
	struct sk_buff *sk_stream_alloc_skb(struct sock *sk, int size, gfp_t gfp)
	{
		struct sk_buff *skb;

		// 4字节对其
		size = ALIGN(size, 4);
		// 分配skb。
		skb = alloc_skb_fclone(size + sk->sk_prot->max_header, gfp);
		if (skb) {
			// 得到精确的大小。
			if (sk_wmem_schedule(sk, skb->truesize)) {
				// 返回skb。
				skb_reserve(skb, skb_tailroom(skb) - size);
					return skb;
			}
			__kfree_skb(skb);
		} else {
			// 否则设置全局标记进入pressure zone
			sk->sk_prot->enter_memory_pressure(sk);
			sk_stream_moderate_sndbuf(sk);
		}
		return NULL;
	}
```


ok,现在就来看上面的几个函数的实现。先来看几个简单的。

首先是tcp_enter_memory_pressure,这个函数很简单，就是判断全局标记tcp_memory_pressure,然后设置这个标记。这个标记主要是用来通知其他模块调整的，比如窗口大小等等，详细的话自己搜索这个值，就知道了。
```
	void tcp_enter_memory_pressure(struct sock *sk)
	{
		if (!tcp_memory_pressure) {
			NET_INC_STATS(sock_net(sk), LINUX_MIB_TCPMEMORYPRESSURES);
			// 设置压力标志。
			tcp_memory_pressure = 1;
		}
	}
```

然后是sk_stream_moderate_sndbuf，这个函数也是要使用sk_userlocks,来判断是否已经被用户设置了。可以看到如果我们自己设置过了snd_buf的话，内核就不会帮我们调整它的大小了。

```
	static inline void sk_stream_moderate_sndbuf(struct sock *sk)
	{
		if (!(sk->sk_userlocks & SOCK_SNDBUF_LOCK)) {
			// 它的大小调整为大于最小值，小于sk->sk_wmem_queued >> 1。
			sk->sk_sndbuf = min(sk->sk_sndbuf, sk->sk_wmem_queued >> 1);
			sk->sk_sndbuf = max(sk->sk_sndbuf, SOCK_MIN_SNDBUF);
		}
	}
```

#### sk_wmem_schedule

最后来看最核心的一个函数sk_wmem_schedule，这个函数只是对`__sk_mem_schedule`的简单封装。这里要知道传递进来的size是skb->truesize，也就是所分配的skb的真实大小。并且第一次进入这个函数，也就是分配第一个缓冲区包时，sk_forward_alloc是为0的，也就是说，第一次必然会执行`__sk_mem_schedule`函数。

```
	static inline int sk_wmem_schedule(struct sock *sk, int size)
	{
		if (!sk_has_account(sk))
			return 1;
		// 先比较size(也就是skb->truesize)和预分配的内存大小。如果小于等于预分配的大小，则直接返回，否则调用__sk_mem_schedule进行调整。
		return size <= sk->sk_forward_alloc ||
			__sk_mem_schedule(sk, size, SK_MEM_SEND);
	}
```


来看`__sk_mem_schedule`，这个函数的功能注释写的很清楚：

increase sk_forward_alloc and memory_allocated


然后来看源码。这里在看之前，我们要知道，协议栈通过读写buf的使用量，划分了3个区域，或者说标志。不同标志进行不同处理。这里的区域的划分是通过sysctl_tcp_mem，也就是prot->sysctl_mem这个数组进行的。

```
	// 页的大小
	#define SK_MEM_QUANTUM ((int)PAGE_SIZE)

	int __sk_mem_schedule(struct sock *sk, int size, int kind)
	{
		struct proto *prot = sk->sk_prot;
		// 首先得到size占用几个内存页。
		int amt = sk_mem_pages(size);
		int allocated;
		// 更新sk_forward_alloc，可以看到这个值是页的大小的倍数。
		sk->sk_forward_alloc += amt * SK_MEM_QUANTUM;

		// amt+memory_allocated也就是当前的总得内存使用量加上将要分配的内存的话，现在的tcp协议栈的总得内存使用量。（可以看到是以页为单位的。
		allocated = atomic_add_return(amt, prot->memory_allocated);

		// 然后开始判断，将会落入哪一个区域。通过上面的分析我们知道sysctl_mem也就是sysctl_tcp_mem.

		// 先判断是否小于等于内存最小使用限额。
		if (allocated <= prot->sysctl_mem[0]) {
			// 这里取消memory_pressure，然后返回。
			if (prot->memory_pressure && *prot->memory_pressure)
				*prot->memory_pressure = 0;
			return 1;
		}

		// 然后判断Under pressure。
		if (allocated > prot->sysctl_mem[1])
			// 大于sysctl_mem[1]说明，已经进入pressure，一次你需要调用tcp_enter_memory_pressure来设置标志。
			if (prot->enter_memory_pressure)
				prot->enter_memory_pressure(sk);

		// 如果超过的hard limit。则进入另外的处理。
		if (allocated > prot->sysctl_mem[2])
			goto suppress_allocation;

		// 判断类型，这里只有两种类型，读和写。总的内存大小判断完，这里开始判断单独的sock的读写内存。
		if (kind == SK_MEM_RECV) {
			if (atomic_read(&sk->sk_rmem_alloc) < prot->sysctl_rmem[0])
				return 1;
		} else { /* SK_MEM_SEND */
			// 这里当为tcp的时候，写队列的大小只有当对端数据确认后才会更新，因此我们要用sk_wmem_queued来判断。
			if (sk->sk_type == SOCK_STREAM) {
				if (sk->sk_wmem_queued < prot->sysctl_wmem[0])
					return 1;
			} else if (atomic_read(&sk->sk_wmem_alloc) <
				   prot->sysctl_wmem[0])
					return 1;
		}

		// 程序到达这里说明总的内存大小在sysctl_mem[0]和sysctl_mem[2]之间，因此我们再次判断memory_pressure
		if (prot->memory_pressure) {
			int alloc;

			// 如果没有在memory_pressure区域，则我们直接返回1。
			if (!*prot->memory_pressure)
				return 1;
			// 这个其实也就是计算整个系统分配的socket的多少。
			alloc = percpu_counter_read_positive(prot->sockets_allocated);
			// 这里假设其余的每个sock所占用的buf都和当前的sock一样大的时候，如果他们的总和小于sysctl_mem[2],也就是hard limit。那么我们也认为这次内存请求是成功的。
			if (prot->sysctl_mem[2] > alloc *
				sk_mem_pages(sk->sk_wmem_queued +
				 atomic_read(&sk->sk_rmem_alloc) +
					 sk->sk_forward_alloc))
				return 1;
		}

	suppress_allocation:

		// 到达这里说明，我们超过了hard limit或者说处于presure 区域。
		if (kind == SK_MEM_SEND && sk->sk_type == SOCK_STREAM) {
			// 调整sk_sndbuf(减小).这个函数前面已经分析过了。
			sk_stream_moderate_sndbuf(sk);
			// 然后比较和sk_sndbuf的大小，如果大于的话，就说明下次我们再次要分配buf的时候会在tcp_memory_free阻塞住，因此这次我们返回1.
			if (sk->sk_wmem_queued + size >= sk->sk_sndbuf)
				return 1;
		}

		/* Alas. Undo changes. */
		// 到达这里说明，请求内存是不被接受的，因此undo所有的操作。然后返回0.
		sk->sk_forward_alloc -= amt * SK_MEM_QUANTUM;
		atomic_sub(amt, prot->memory_allocated);
		return 0;
	}
```


接下来来看个很重要的函数skb_set_owner_w。

顾名思义，这个函数也就是将一个skb和scok关联起来。只不过关联的时候更新sock相应的域。我们来看源码：

```
	static inline void skb_set_owner_w(struct sk_buff *skb, struct sock *sk)
	{
		skb_orphan(skb);
		// 与传递进来的sock关联起来
		skb->sk = sk;
		// 设置skb的析构函数
		skb->destructor = sock_wfree;
		// 更新sk_wmem_alloc域，就是sk_wmem_alloc+truesize.
		atomic_add(skb->truesize, &sk->sk_wmem_alloc);
	}
```


ok，接下来来看个scok_wfree函数，这个函数做得基本和上面函数相反。这个函数都是被kfree_skb自动调用的。

```
	void sock_wfree(struct sk_buff *skb)
	{
		struct sock *sk = skb->sk;
		int res;

		// 更新sk_wmem_alloc,减去skb的大小。
		res = atomic_sub_return(skb->truesize, &sk->sk_wmem_alloc);
		if (!sock_flag(sk, SOCK_USE_WRITE_QUEUE))
		// 唤醒等待队列，也就是唤醒等待内存分配。
			sk->sk_write_space(sk);
		if (res == 0)
			__sk_free(sk);
	}
```


而skb_set_owner_w是什么时候被调用呢，我们通过搜索代码可以看到，它是在tcp_transmit_skb中被调用的。而tcp_transmit_skb我们知道是传递数据包到ip层的函数。

而kfree_skb被调用也就是在对端已经确认完我们发送的包后才会被调用来释放skb。

#### tcp_rcv_established

接下来来看接收数据的内存管理。我们主要来看tcp_rcv_established这个函数，我前面的blog已经断断续续的分析过了，因此这里我们只看一些重要的代码片断。

这里我们要知道，代码能到达下面的位置，则说明，数据并没有直接拷贝到用户空间。否则的话，是不会进入下面的片断的。

```
	if (!eaten) {
		..........................................

		// 如果skb的大小大于预分配的值,如果大于则要另外处理。
		if ((int)skb->truesize > sk->sk_forward_alloc)
				goto step5;
		__skb_pull(skb, tcp_header_len);
		__skb_queue_tail(&sk->sk_receive_queue, skb);
		// 这里关联skb和对应的sk，并且更新相关的域，我们下面会分析这个函数。
		skb_set_owner_r(skb, sk);
		tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;
	}
	...............................................

	step5:
		if (th->ack && tcp_ack(sk, skb, FLAG_SLOWPATH) < 0)
			goto discard;

		tcp_rcv_rtt_measure_ts(sk, skb);

		/* Process urgent data. */
		tcp_urg(sk, skb, th);

		/* step 7: process the segment text */
		// 最核心的函数就是这个。我们接下来会详细分析这个函数。
		tcp_data_queue(sk, skb);

		tcp_data_snd_check(sk);
		tcp_ack_snd_check(sk);
		return 0;
```


先来看skb_set_owner_r函数，这个函数关联skb和sk其实它和skb_set_owner_w类似：

```
	static inline void skb_set_owner_r(struct sk_buff *skb, struct sock *sk)
	{
		skb_orphan(skb);
		// 关联sk
		skb->sk = sk;
		// 设置析构函数
		skb->destructor = sock_rfree;
		// 更新rmem_alloc
		atomic_add(skb->truesize, &sk->sk_rmem_alloc);
		// 改变forward_alloc.
		sk_mem_charge(sk, skb->truesize);
	}
```

#### tcp_data_queue

然后是tcp_data_queue，这个函数主要用来排队接收数据，并update相关的读buf。由于这个函数比较复杂，我们只关心我们感兴趣的部分：

```
	static void tcp_data_queue(struct sock *sk, struct sk_buff *skb)
	{
		struct tcphdr *th = tcp_hdr(skb);
		struct tcp_sock *tp = tcp_sk(sk);
		int eaten = -1;
		.......................................
		// 首先判断skb的开始序列号和我们想要接收的序列号。如果相等开始处理这个数据包(也就是拷贝到用户空间).
		if (TCP_SKB_CB(skb)->seq == tp->rcv_nxt) {
			if (tcp_receive_window(tp) == 0)
				goto out_of_window;

			// tp的ucopy我前面的blog已经详细分析过了。这里就不解释了。
			if (tp->ucopy.task == current &&
				tp->copied_seq == tp->rcv_nxt && tp->ucopy.len &&sock_owned_by_user(sk) && !tp->urg_data)
			{
				// 计算将要拷贝给用户空间的大小。
				int chunk = min_t(unsigned int, skb->len,tp->ucopy.len);

				// 设置状态，说明我们处于进程上下文。
				__set_current_state(TASK_RUNNING);

				local_bh_enable();
				// 拷贝skb
				if (!skb_copy_datagram_iovec(skb, 0, tp->ucopy.iov, chunk)) {
					tp->ucopy.len -= chunk;
					tp->copied_seq += chunk;
					// 更新eaten，它的默认值为-1.
					eaten = (chunk == skb->len && !th->fin);
					tcp_rcv_space_adjust(sk);
				}
				local_bh_disable();
			}

			// 如果小于0则说明没有拷贝成功，或者说就没有进行拷贝。此时需要更新sock的相关域。
			if (eaten <= 0) {
	queue_and_out:
				// 最关键的tcp_try_rmem_schedule函数。接下来会详细分析。
				if (eaten < 0 &&
			 			tcp_try_rmem_schedule(sk, skb->truesize))
					goto drop;

				// 关联skb和sk。到达这里说明tcp_try_rmem_schedule成功，也就是返回0.
				skb_set_owner_r(skb, sk);
				// 加skb到receive_queue.
				__skb_queue_tail(&sk->sk_receive_queue, skb);
			}
			// 更新期待序列号。
			tp->rcv_nxt = TCP_SKB_CB(skb)->end_seq;
			..............................................

			.....................................

			tcp_fast_path_check(sk);

			if (eaten > 0)
				__kfree_skb(skb);
			else if (!sock_flag(sk, SOCK_DEAD))
				sk->sk_data_ready(sk, 0);
			return;
		}
		// 下面就是处理乱序包。以后会详细分析。
		......................................
	}
```

#### tcp_try_rmem_schedule

接下来我们就来看tcp_try_rmem_schedule这个函数,这个函数如果返回0则说明sk_rmem_schedule返回1,而sk_rmem_schedule和sk_wmem_schedule是一样的。也就是看当前的skb加入后有没有超过读buf的限制。并更新相关的域。：

```
	static inline int tcp_try_rmem_schedule(struct sock *sk, unsigned int size)
	{
		// 首先判断rmem_alloc(当前的读buf字节数)是否大于最大buf字节数，如果大于则调用tcp_prune_queue调整分配的buf。否则调用sk_rmem_schedule来调整相关域（sk_forward_alloc）。
		if (atomic_read(&sk->sk_rmem_alloc) > sk->sk_rcvbuf ||!sk_rmem_schedule(sk, size)) {

			// 调整分配的buf。
			if (tcp_prune_queue(sk) < 0)
				return -1;
			// 更新sk的相关域。
			if (!sk_rmem_schedule(sk, size)) {
				if (!tcp_prune_ofo_queue(sk))
					return -1;

				if (!sk_rmem_schedule(sk, size))
					return -1;
			}
		}
		return 0;
	}
```


来看sk_rmem_schedule，这个函数很简单，就是封装了`__sk_mem_schedule`。而这个函数我们上面已经分析过了。
```
	static inline int sk_rmem_schedule(struct sock *sk, int size)
	{
		if (!sk_has_account(sk))
			return 1;
		return size <= sk->sk_forward_alloc ||
			__sk_mem_schedule(sk, size, SK_MEM_RECV);
	}
```

#### tcp_prune_queue

最后是tcp_prune_queue，这个函数主要是用来丢掉一些skb，因为到这个函数就说明我们的内存使用已经到极限了，因此我们要合并一些buf。这个合并也就是将序列号连续的段进行合并。

这里我们要知道tcp的包是有序的，因此内核中tcp专门有一个队列来保存那些Out of order segments。因此我们这里会先处理这个队列里面的skb。

然后调用tcp_collapse来处理接收队列里面的skb。和上面的类似。

这里要注意，合并的话都是按页来合并，也就是先分配一页大小的内存，然后将老的skb复制进去，最后free掉老的buf。
```
	static int tcp_prune_queue(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		..................................
		// 如果rmem_alloc过于大，则重新计算窗口的大小。一半都会缩小窗口。
		if (atomic_read(&sk->sk_rmem_alloc) >= sk->sk_rcvbuf)
			tcp_clamp_window(sk);
		// 如果处于pressure区域，则调整窗口大小。这里也是缩小窗口。
		else if (tcp_memory_pressure)
			tp->rcv_ssthresh = min(tp->rcv_ssthresh, 4U * tp->advmss);

		// 处理ofo队列。
		tcp_collapse_ofo_queue(sk);
		// 如果接收队列为非空，则调用tcp_collapse来处理sk_receive_queue
		if (!skb_queue_empty(&sk->sk_receive_queue))
			tcp_collapse(sk, &sk->sk_receive_queue,
					 skb_peek(&sk->sk_receive_queue),
					 NULL,
					 tp->copied_seq, tp->rcv_nxt);
		// 更新全局的已分配内存的大小，也就是memory_allocated，接下来会详细介绍这个函数。
		sk_mem_reclaim(sk);

		// 如果调整后小于sk_rcvbuf,则返回0.
		if (atomic_read(&sk->sk_rmem_alloc) <= sk->sk_rcvbuf)
			return 0;

		......................................
		return -1;
	}
```

#### tcp_collapse_ofo_queue 尝试减小ofo queue占内存的大小
```
	/* Collapse ofo queue. Algorithm: select contiguous sequence of skbs
	 * and tcp_collapse() them until all the queue is collapsed.
	 */
	static void tcp_collapse_ofo_queue(struct sock *sk)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct sk_buff *skb = skb_peek(&tp->out_of_order_queue);
		struct sk_buff *head;
		u32 start, end;

		if (skb == NULL)
			return;

		start = TCP_SKB_CB(skb)->seq;
		end = TCP_SKB_CB(skb)->end_seq;
		head = skb;

		for (;;) {
			struct sk_buff *next = NULL;

			if (!skb_queue_is_last(&tp->out_of_order_queue, skb))
				next = skb_queue_next(&tp->out_of_order_queue, skb);
			skb = next;

			/* Segment is terminated when we see gap or when
			 * we are at the end of all the queue. */
			if (!skb ||
				after(TCP_SKB_CB(skb)->seq, end) ||
				before(TCP_SKB_CB(skb)->end_seq, start)) {  // 找到ofo queue中连续的一段skb，即 prev->end_seq >= next->seq
				tcp_collapse(sk, &tp->out_of_order_queue,
						 head, skb, start, end);            // 尝试减小这一段连续skb占用的内存
				head = skb;
				if (!skb)
					break;
				/* Start new segment */
				start = TCP_SKB_CB(skb)->seq;               // 下个skb就是新的一段的开始
				end = TCP_SKB_CB(skb)->end_seq;
			} else {
				if (before(TCP_SKB_CB(skb)->seq, start))    // 这种情况只可能是tcp_collapse中大包拆成小包，拆到一半内存不够，没拆完导致。
					start = TCP_SKB_CB(skb)->seq;
				if (after(TCP_SKB_CB(skb)->end_seq, end))
					end = TCP_SKB_CB(skb)->end_seq;
			}
		}
	}
```

#### tcp_collapse，gro上来的包有可能是大于4k的包，所以这个函数有时是在拆包，利弊难定
```
	// 删除一个skb，返回下个skb
	static struct sk_buff *tcp_collapse_one(struct sock *sk, struct sk_buff *skb,
						struct sk_buff_head *list)
	{
		struct sk_buff *next = NULL;

		if (!skb_queue_is_last(list, skb))
			next = skb_queue_next(list, skb);

		__skb_unlink(skb, list);
		__kfree_skb(skb);
		NET_INC_STATS_BH(sock_net(sk), LINUX_MIB_TCPRCVCOLLAPSED);

		return next;
	}

	/* Collapse contiguous sequence of skbs head..tail with
	 * sequence numbers start..end.
	 *
	 * If tail is NULL, this means until the end of the list.
	 *
	 * Segments with FIN/SYN are not collapsed (only because this
	 * simplifies code)
	 */
	static void
	tcp_collapse(struct sock *sk, struct sk_buff_head *list,
			 struct sk_buff *head, struct sk_buff *tail,
			 u32 start, u32 end)
	{
		struct sk_buff *skb, *n;
		bool end_of_skbs;

		/* First, check that queue is collapsible and find
		 * the point where collapsing can be useful. */
		skb = head;
	restart:
		end_of_skbs = true;
		skb_queue_walk_from_safe(list, skb, n) {
			if (skb == tail)
				break;
			/* No new bits? It is possible on ofo queue. */
			if (!before(start, TCP_SKB_CB(skb)->end_seq)) { // 这种情况现在是不会出现的，以前代码有可能出现？？
				skb = tcp_collapse_one(sk, skb, list);
				if (!skb)
					break;
				goto restart;
			}

			/* The first skb to collapse is:
			 * - not SYN/FIN and
			 * - bloated or contains data before "start" or
			 *   overlaps to the next one.
			 */
			if (!tcp_hdr(skb)->syn && !tcp_hdr(skb)->fin &&         // SYN，FIN 不合并，简化操作
				(tcp_win_from_space(skb->truesize) > skb->len ||    // 合并后可能减小空间的情况才合并
				 before(TCP_SKB_CB(skb)->seq, start))) {            // seq到start的数据已经被读走了，有减小空间的可能
				end_of_skbs = false;
				break;
			}

			if (!skb_queue_is_last(list, skb)) {
				struct sk_buff *next = skb_queue_next(list, skb);
				if (next != tail &&
					TCP_SKB_CB(skb)->end_seq != TCP_SKB_CB(next)->seq) { // 两个skb之间有交集，有减小空间可能
					end_of_skbs = false;
					break;
				}
			}

			/* Decided to skip this, advance start seq. */
			start = TCP_SKB_CB(skb)->end_seq;     // 否则向后继续找可能减小空间的第一个skb
		}
		if (end_of_skbs || tcp_hdr(skb)->syn || tcp_hdr(skb)->fin)
			return;

		while (before(start, end)) {  // 落在在start到end的包就是这次要合并的
			struct sk_buff *nskb;
			unsigned int header = skb_headroom(skb); // skb中协议头的大小
			int copy = SKB_MAX_ORDER(header, 0);     // 一个页（4k）中出去协议头空间的大小，也就是能容下的数据大小

			/* Too big header? This can happen with IPv6. */
			if (copy < 0)
				return;
			if (end - start < copy)
				copy = end - start;
			nskb = alloc_skb(copy + header, GFP_ATOMIC);
			if (!nskb)
				return;

			skb_set_mac_header(nskb, skb_mac_header(skb) - skb->head);
			skb_set_network_header(nskb, (skb_network_header(skb) -
							  skb->head));
			skb_set_transport_header(nskb, (skb_transport_header(skb) -
							skb->head));
			skb_reserve(nskb, header);
			memcpy(nskb->head, skb->head, header);
			memcpy(nskb->cb, skb->cb, sizeof(skb->cb));
			TCP_SKB_CB(nskb)->seq = TCP_SKB_CB(nskb)->end_seq = start;
			__skb_queue_before(list, skb, nskb);
			skb_set_owner_r(nskb, sk);

			/* Copy data, releasing collapsed skbs. */
			while (copy > 0) {    // 如果copy = 0，这里就会出BUG，但如果没有认为改，是不会的。ipv6会吗？？？。后面版本改进这函数了，也不会出现copy=0了
				int offset = start - TCP_SKB_CB(skb)->seq;
				int size = TCP_SKB_CB(skb)->end_seq - start;

				BUG_ON(offset < 0);
				if (size > 0) { // copy旧的skb数据到新的skb上
					size = min(copy, size);
					if (skb_copy_bits(skb, offset, skb_put(nskb, size), size))
						BUG();
					TCP_SKB_CB(nskb)->end_seq += size;
					copy -= size;
					start += size;
				}
				if (!before(start, TCP_SKB_CB(skb)->end_seq)) { // 旧的skb被copy完了就删掉
					skb = tcp_collapse_one(sk, skb, list);
					if (!skb ||
						skb == tail ||
						tcp_hdr(skb)->syn ||
						tcp_hdr(skb)->fin)
						return;
				}
			}
		}
	}
```

来看sk_mem_reclaim函数，它只是简单的封装了`__sk_mem_reclaim`：

```
	static inline void sk_mem_reclaim(struct sock *sk)
	{
		if (!sk_has_account(sk))
			return;
		// 如果sk_forward_alloc大于1页则调用__sk_mem_reclaim，我们知道sk_forward_alloc是以页为单位的，因此这里也就是和大于0一样。
		if (sk->sk_forward_alloc >= SK_MEM_QUANTUM)
			__sk_mem_reclaim(sk);
	}
```

`__sk_mem_reclaim`就是真正操作的函数，它会更新memory_allocated：

```
	void __sk_mem_reclaim(struct sock *sk)
	{
		struct proto *prot = sk->sk_prot;
		// 更新memory_allocated，这里我们知道memory_allocated也是以页为单位的，因此需要将sk_forward_alloc转化为页。
		atomic_sub(sk->sk_forward_alloc >> SK_MEM_QUANTUM_SHIFT,prot->memory_allocated);

		// 更新这个sk的sk_forward_alloc为一页。
		sk->sk_forward_alloc &= SK_MEM_QUANTUM - 1;
		// 判断是否处于pressure区域，是的话更新memory_pressure变量。
		if (prot->memory_pressure && *prot->memory_pressure &&(atomic_read(prot->memory_allocated) < （prot->sysctl_mem[0]))
			*prot->memory_pressure = 0;
	}
```


最后看一下读buf的释放。这个函数会在kfree_skb中被调用。

```
	void sock_rfree(struct sk_buff *skb)
	{

		struct sock *sk = skb->sk;
		// 更新rmem_alloc
		atomic_sub(skb->truesize, &sk->sk_rmem_alloc);
		// 更新forward_alloc.
		sk_mem_uncharge(skb->sk, skb->truesize);
	}
```

