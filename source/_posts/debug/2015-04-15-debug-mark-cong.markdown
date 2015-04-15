---
layout: post
title: "拥塞控制模块注意"
date: 2015-04-15 14:24:00 +0800
comments: false
categories:
- 2015
- 2015~04
- debug
- debug~mark
tags:
---
#### 应用改变sock的拥塞控制算法

```
	#define SOL_TCP 6
	#define TCP_CONGESTION  13

	strcpy(name, "cubic");
	setsockopt (connfd, SOL_TCP, TCP_CONGESTION, name, strlen(name));
```

##### net/socket.c
```
	SYSCALL_DEFINE5(setsockopt, int, fd, int, level, int, optname,
			char __user *, optval, int, optlen)
	{
		...
				err =
					sock->ops->setsockopt(sock, level, optname, optval,
							  optlen);
		...
	}
```

对于ipv4的tcp，sock->ops指向 net/ipv4/af_inet.c 中的 inet_stream_ops，所以setsockopt等于sock_common_setsockopt。

##### net/core/sock.c
```
	int sock_common_setsockopt(struct socket *sock, int level, int optname,
				   char __user *optval, unsigned int optlen)
	{
		struct sock *sk = sock->sk;

		return sk->sk_prot->setsockopt(sk, level, optname, optval, optlen);
	}
```

sk_prot 指向 net/ipv4/tcp_ipv4.c 中的 tcp_prot，所以setsockopt等于tcp_setsockopt

##### net/ipv4/tcp.c
```
	int tcp_setsockopt(struct sock *sk, int level, int optname, char __user *optval,
			   unsigned int optlen)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);

		if (level != SOL_TCP)
			return icsk->icsk_af_ops->setsockopt(sk, level, optname,
								 optval, optlen);
		return do_tcp_setsockopt(sk, level, optname, optval, optlen);
	}
```

因为level = SOL_TCP, optname = TCP_CONGESTION, 所以直接到do_tcp_setsockopt的第一个if里。

```
	static int do_tcp_setsockopt(struct sock *sk, int level,
			int optname, char __user *optval, unsigned int optlen)
	{
		struct tcp_sock *tp = tcp_sk(sk);
		struct inet_connection_sock *icsk = inet_csk(sk); 
		int val;	  
		int err = 0;
	
		/* This is a string value all the others are int's */
		if (optname == TCP_CONGESTION) {	  
			char name[TCP_CA_NAME_MAX]; 

			if (optlen < 1)
				return -EINVAL;

			val = strncpy_from_user(name, optval,
						min_t(long, TCP_CA_NAME_MAX-1, optlen));
			if (val < 0)
				return -EFAULT;
			name[val] = 0;

			lock_sock(sk);
			err = tcp_set_congestion_control(sk, name);
			release_sock(sk);
			return err;
		}

	...

```

#### net/ipv4/tcp_cong.c
```
	/* Change congestion control for socket */
	int tcp_set_congestion_control(struct sock *sk, const char *name)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct tcp_congestion_ops *ca;
		int err = 0;

		rcu_read_lock();
		ca = tcp_ca_find(name);

		/* no change asking for existing value */
		if (ca == icsk->icsk_ca_ops)
			goto out;

	#ifdef CONFIG_MODULES
		/* not found attempt to autoload module */
		if (!ca && capable(CAP_NET_ADMIN)) {
			rcu_read_unlock();
			request_module("tcp_%s", name);
			rcu_read_lock();
			ca = tcp_ca_find(name);
		}
	#endif
		if (!ca)
			err = -ENOENT;

		else if (!((ca->flags & TCP_CONG_NON_RESTRICTED) || capable(CAP_NET_ADMIN)))
			err = -EPERM;

		else if (!try_module_get(ca->owner))
			err = -EBUSY;

		else {
			tcp_cleanup_congestion_control(sk);
			icsk->icsk_ca_ops = ca;

			if (sk->sk_state != TCP_CLOSE && icsk->icsk_ca_ops->init) // 如果sk->sk_state = TCP_CLOSE, 那么不会调用拥塞控制模块的初始化
				icsk->icsk_ca_ops->init(sk);
		}
	 out:
		rcu_read_unlock();
		return err;
	}
```

可以看到，如果sk->sk_state = TCP_CLOSE, 那么不会调用拥塞控制模块的初始化。

----------------

#### 那么什么时候sk->sk_state == TCP_CLOSE，并且还能调用setsockopt呢？

##### 举一种情况：当收到RST包的时候，tcp_rcv_established()->tcp_validate_incoming()->tcp_reset()->tcp_done()将sk置为TCP_CLOSE。

##### 如果拥塞控制模块中init有申请内存，release中释放内存。那么在上述情况下将会出现没有申请而直接释放的情况，导致panic。

```
	BUG: unable to handle kernel paging request at ffffeba4000002a0

	[<ffffffff8115b17e>] kfree+0x6e/0x240
	[<ffffffffa0068055>] cong_release+0x35/0x50 [cong]
	[<ffffffff81467953>] tcp_cleanup_congestion_control+0x23/0x40
	[<ffffffff81465bb9>] tcp_v4_destroy_sock+0x29/0x2d0
	[<ffffffff8144e9e3>] inet_csk_destroy_sock+0x53/0x140
	[<ffffffff814504c0>] tcp_close+0x340/0x4a0
	[<ffffffff814748de>] inet_release+0x5e/0x90
	[<ffffffff813f4359>] sock_release+0x29/0x90
	[<ffffffff813f43d7>] sock_close+0x17/0x40
	[<ffffffff81173ed3>] __fput+0xf3/0x220
	[<ffffffff8117401c>] fput+0x1c/0x30
	[<ffffffff8116df2d>] filp_close+0x5d/0x90
	[<ffffffff8117090c>] sys_close+0xac/0x110
	[<ffffffff8100af72>] system_call_fastpath+0x16/0x1b
```

#### 测试代码

[congestion_mod_panic](/download/debug/congestion_mod_panic.tar.gz)  


