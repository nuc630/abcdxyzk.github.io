---
layout: post
title: "socket绑定连接 sys_bind"
date: 2015-06-09 17:41:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/justlinux2010/article/details/8593539

bind()系统调用是给套接字分配一个本地协议地址，对于网际协议，协议地址是32位IPv4地址或128位IPv6地址与16位的TCP或UDP端口号的组合。如果没有通过bind()来指定本地的协议地址，在和远端通信时，内核会随机给套接字分配一个IP地址和端口号。bind()系统调用通常是在网络程序的服务器端调用，而且是必须的。如果TCP服务器不这么做，让内核来选择临时端口号而不是捆绑众所周知的端口，客户端如何发起与服务器的连接？

#### 一、sys_bind()

  bind()系统调用对应的内核实现是sys_bind()，其源码及分析如下：

```
	/* 
	 *  Bind a name to a socket. Nothing much to do here since it's 
	 *  the protocol's responsibility to handle the local address. 
	 * 
	 *  We move the socket address to kernel space before we call 
	 *  the protocol layer (having also checked the address is ok). 
	 */  
	  
	SYSCALL_DEFINE3(bind, int, fd, struct sockaddr __user *, umyaddr, int, addrlen)  
	{  
		struct socket *sock;  
		struct sockaddr_storage address;  
		int err, fput_needed;  
	  
		/* 
		 * 以fd为索引从当前进程的文件描述符表中 
		 * 找到对应的file实例，然后从file实例的private_data中 
		 * 获取socket实例。 
		 */  
		sock = sockfd_lookup_light(fd, &err, &fput_needed);  
		if (sock) {  
			/* 
			 * 将用户空间的地址拷贝到内核空间的缓冲区中。 
			 */  
			err = move_addr_to_kernel(umyaddr, addrlen, (struct sockaddr *)&address);  
			if (err >= 0) {  
				/* 
				 * SELinux相关，不需要关心。 
				 */  
				err = security_socket_bind(sock,  
							   (struct sockaddr *)&address,  
							   addrlen);  
				/* 
				 * 如果是TCP套接字，sock->ops指向的是inet_stream_ops， 
				 * sock->ops是在inet_create()函数中初始化，所以bind接口 
				 * 调用的是inet_bind()函数。 
				 */  
				if (!err)  
					err = sock->ops->bind(sock,  
								  (struct sockaddr *)  
								  &address, addrlen);  
			}  
			fput_light(sock->file, fput_needed);  
		}  
		return err;  
	}  
```

  sys_bind()的代码流程如下图所示：
```
		sys_bind()
			|
			|----> sockfd_loockup_light()
			|
			|----> move_addr_to_kernel()
			|
			 ----> inet_bind()
```
  sys_bind()首先调用sockfd_lookup_light()查找套接字对应的socket实例，如果没有找到，则返回EBADF错误。在进行绑定操作之前，要先将用户传入的本地协议地址从用户空间拷贝到内核缓冲区中，在拷贝过程中会检查用户传入的地址是否正确。如果指定的长度参数小于0或者大于sockaddr_storage的大小，则返回EINVAL错误；如果在调用copy_from_user()执行拷贝操作过程中出现错误，则返回EFAULT错误。在上述的准备工作都完成后，调用inet_bind()函数（即sock->ops->bind指向的函数，参见注释）来完成绑定操作。

#### 二、inet_bind()

inet_bind()比较简单，不做过多的分析，注释的已经很清楚了。代码及注释如下所示：

```
	int inet_bind(struct socket *sock, struct sockaddr *uaddr, int addr_len)  
	{  
		struct sockaddr_in *addr = (struct sockaddr_in *)uaddr;  
		struct sock *sk = sock->sk;  
		struct inet_sock *inet = inet_sk(sk);  
		unsigned short snum;  
		int chk_addr_ret;  
		int err;  
	  
		/* If the socket has its own bind function then use it. (RAW) */  
		/* 
		 * 如果是TCP套接字，sk->sk_prot指向的是tcp_prot，在 
		 * inet_create()中调用的sk_alloc()函数中初始化。由于 
		 * tcp_prot中没有设置bind接口，因此判断条件不成立。 
		 */  
		if (sk->sk_prot->bind) {  
			err = sk->sk_prot->bind(sk, uaddr, addr_len);  
			goto out;  
		}  
		err = -EINVAL;  
		if (addr_len < sizeof(struct sockaddr_in))  
			goto out;  
	  
		/* 
		 * 判断传入的地址类型。 
		 */  
		chk_addr_ret = inet_addr_type(sock_net(sk), addr->sin_addr.s_addr);  
	  
		/* Not specified by any standard per-se, however it breaks too 
		 * many applications when removed.  It is unfortunate since 
		 * allowing applications to make a non-local bind solves 
		 * several problems with systems using dynamic addressing. 
		 * (ie. your servers still start up even if your ISDN link 
		 *  is temporarily down) 
		 */  
		err = -EADDRNOTAVAIL;  
		/* 
		 * 如果系统不支持绑定本地地址，或者 
		 * 传入的地址类型有误，则返回EADDRNOTAVAIL 
		 * 错误。 
		 */  
		if (!sysctl_ip_nonlocal_bind &&  
			!(inet->freebind || inet->transparent) &&  
			addr->sin_addr.s_addr != htonl(INADDR_ANY) &&  
			chk_addr_ret != RTN_LOCAL &&  
			chk_addr_ret != RTN_MULTICAST &&  
			chk_addr_ret != RTN_BROADCAST)  
			goto out;  
	  
		snum = ntohs(addr->sin_port);  
		err = -EACCES;  
		/* 
		 * 如果绑定的端口号小于1024(保留端口号)，但是 
		 * 当前用户没有CAP_NET_BIND_SERVICE权限，则返回EACCESS错误。 
		 */  
		if (snum && snum < PROT_SOCK && !capable(CAP_NET_BIND_SERVICE))  
			goto out;  
	  
		/*      We keep a pair of addresses. rcv_saddr is the one 
		 *      used by hash lookups, and saddr is used for transmit. 
		 * 
		 *      In the BSD API these are the same except where it 
		 *      would be illegal to use them (multicast/broadcast) in 
		 *      which case the sending device address is used. 
		 */  
		lock_sock(sk);  
	  
		/* Check these errors (active socket, double bind). */  
		err = -EINVAL;  
		/* 
		 * 如果套接字状态不是TCP_CLOSE(套接字的初始状态，参见 
		 * sock_init_data()函数)，或者已经绑定过，则返回EINVAL错误。 
		 */  
		if (sk->sk_state != TCP_CLOSE || inet->num)  
			goto out_release_sock;  
	  
		inet->rcv_saddr = inet->saddr = addr->sin_addr.s_addr;  
		if (chk_addr_ret == RTN_MULTICAST || chk_addr_ret == RTN_BROADCAST)  
			inet->saddr = 0;  /* Use device */  
	  
		/* Make sure we are allowed to bind here. */  
		/* 
		 * 这里实际调用的是inet_csk_get_port()函数。 
		 * 检查要绑定的端口号是否已经使用，如果已经使用， 
		 * 则检查是否允许复用。如果检查失败，则返回 
		 * EADDRINUSE错误。 
		 */  
		if (sk->sk_prot->get_port(sk, snum)) {  
			inet->saddr = inet->rcv_saddr = 0;  
			err = -EADDRINUSE;  
			goto out_release_sock;  
		}  
	  
		/* 
		 * rcv_saddr存储的是已绑定的本地地址，接收数据时使用。 
		 * 如果已绑定的地址不为0，则设置SOCK_BINDADDR_LOCK标志， 
		 * 表示已绑定本地地址。 
		 */  
		if (inet->rcv_saddr)  
			sk->sk_userlocks |= SOCK_BINDADDR_LOCK;  
		/* 
		 * 如果绑定的端口号不为0，则设置SOCK_BINDPORT_LOCK标志， 
		 * 表示已绑定本地端口号。 
		 */  
		if (snum)  
			sk->sk_userlocks |= SOCK_BINDPORT_LOCK;  
		inet->sport = htons(inet->num);  
		inet->daddr = 0;  
		inet->dport = 0;  
		/* 
		 * 重新初始化目的路由缓存项，如果之前已设置，则 
		 * 调用dst_release()释放老的路由缓存项。 
		 */  
		sk_dst_reset(sk);  
		err = 0;  
	out_release_sock:  
		release_sock(sk);  
	out:  
		return err;  
	}
```
