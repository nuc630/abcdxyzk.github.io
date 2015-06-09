---
layout: post
title: "socket接收连接 sys_accept"
date: 2015-06-09 17:10:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://linux.chinaunix.net/techdoc/net/

http://linux.chinaunix.net/techdoc/net/2008/12/30/1055672.shtml

这一节我们开始分析如何接收TCP的socket的连接请求，象以前的分析章节一样我们先看练习中的用户界面
```
	accept(server_sockfd, （struct sockaddr *)&client_address, client_len);
```

还是以前的分析方法，这里要注意第二个参数，client_address，它是在我们的测试程序中另外声明用于保存客户端socket地址的数据结构变量。其他二个参数无需多说。还是按照以前的方式我们直接看sys_socketcall()函数的代码部分
```
	case SYS_ACCEPT:
		err = sys_accept(a0, (struct sockaddr __user *)a1,
			 (int __user *)a[2]);
		break;
```

显然是进入sys_accept()这个函数
```
	sys_socketcall()-->sys_accept()
	asmlinkage long sys_accept(int fd, struct sockaddr __user *upeer_sockaddr,
				 int __user *upeer_addrlen)
	{
		struct socket *sock, *newsock;
		struct file *newfile;
		int err, len, newfd, fput_needed;
		char address[MAX_SOCK_ADDR];
		sock = sockfd_lookup_light(fd, &err, &fput_needed);
		if (!sock)
			goto out;
		err = -ENFILE;
		if (!(newsock = sock_alloc()))
			goto out_put;
		newsock->type = sock->type;
		newsock->ops = sock->ops;
		/*
		 * We don't need try_module_get here, as the listening socket (sock)
		 * has the protocol module (sock->ops->owner) held.qinjian
		 */
		__module_get(newsock->ops->owner);
		newfd = sock_alloc_fd(&newfile);
		if (unlikely(newfd  0)) {
			err = newfd;
			sock_release(newsock);
			goto out_put;
		}
		err = sock_attach_fd(newsock, newfile);
		if (err  0)
			goto out_fd_simple;
		err = security_socket_accept(sock, newsock);
		if (err)
			goto out_fd;
		err = sock->ops->accept(sock, newsock, sock->file->f_flags);
		if (err  0)
			goto out_fd;
		if (upeer_sockaddr) {
			if (newsock->ops->getname(newsock, (struct sockaddr *)address,
						 &len, 2)  0) {
				err = -ECONNABORTED;
				goto out_fd;
			}
			err = move_addr_to_user(address, len, upeer_sockaddr,
						upeer_addrlen);
			if (err  0)
				goto out_fd;
		}
		/* File flags are not inherited via accept() unlike another OSes.QJ */
		fd_install(newfd, newfile);
		err = newfd;
		security_socket_post_accept(sock, newsock);
	out_put:
		fput_light(sock->file, fput_needed);
	out:
		return err;
	out_fd_simple:
		sock_release(newsock);
		put_filp(newfile);
		put_unused_fd(newfd);
		goto out_put;
	out_fd:
		fput(newfile);
		put_unused_fd(newfd);
		goto out_put;
	}
```
这个函数总的作用就是使服务端的socket能够创建与客户端连接的“子连接”，也就是会利用服务器端的socket创建一个新的能与客户端建立连接的socket，而且会把新连接的socket的id号，返回到我们测试程序中的client_sockfd，同时也把客户端的socket地址保存在client_address中，函数中首先会进入sockfd_lookup_light（）中找到我们服务器端的socket，这个函数前面章节中用到多次了不再进入细细分析了，接着函数中调用sock_alloc（）函数创建一个新的socket,此后为这个新创建的socket分配一个可用的文件号，然后能过sock_attach_fd使其与文件号挂钩。最重要的当属这句代码

```
	err = sock->ops->accept(sock, newsock, sock->file->f_flags);
```

这部分开始入手分析TCP的socket是如何执行的，这里会进入inet_stream_ops中执行，可能有些朋友是直接阅读本文的，最好是看一下前面的章节理清是如何进入这个函数的，我们这里不再重复了。

```
	const struct proto_ops inet_stream_ops = {
		。。。。。。
		.accept         = inet_accept,
		。。。。。。
	};
```

我们再次看一下af_inet.c中的这个数据结构，很显然进入了inet_accept()函数
```
	sys_socketcall()-->sys_accept()-->inet_accept()
	int inet_accept(struct socket *sock, struct socket *newsock, int flags)
	{
		struct sock *sk1 = sock->sk;
		int err = -EINVAL;
		struct sock *sk2 = sk1->sk_prot->accept(sk1, flags, &err);
		if (!sk2)
			goto do_err;
		lock_sock(sk2);
		BUG_TRAP((1  sk2->sk_state) &
			 (TCPF_ESTABLISHED | TCPF_CLOSE_WAIT | TCPF_CLOSE));
		sock_graft(sk2, newsock);
		newsock->state = SS_CONNECTED;
		err = 0;
		release_sock(sk2);
	do_err:
		return err;
	}
```

进入这个函数的时候已经找到了我们前面建立的socket结构，而newsock是我们新分配建立的socket结构，我们看到上面函数中执行了

```
	struct sock *sk2 = sk1->sk_prot->accept(sk1, flags, &err);
```

进而进入了钩子函数中执行，那里的struct proto tcp_prot结构变量可以看到
```
	struct proto tcp_prot = {
		。。。。。。
		.accept            = inet_csk_accept,
		。。。。。。
	};
```
很显然是执行的inet_csk_accept（）函数
```
	sys_socketcall()-->sys_accept()-->inet_accept()-->inet_csk_accept()
	struct sock *inet_csk_accept(struct sock *sk, int flags, int *err)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		struct sock *newsk;
		int error;
		lock_sock(sk);
		/* We need to make sure that this socket is listening,
		 * and that it has something pending.qinjian
		 */
		error = -EINVAL;
		if (sk->sk_state != TCP_LISTEN)
			goto out_err;
		/* Find already established connection */
		if (reqsk_queue_empty(&icsk->icsk_accept_queue)) {
			long timeo = sock_rcvtimeo(sk, flags & O_NONBLOCK);
			/* If this is a non blocking socket don't sleep */
			error = -EAGAIN;
			if (!timeo)
				goto out_err;
			error = inet_csk_wait_for_connect(sk, timeo);
			if (error)
				goto out_err;
		}
		newsk = reqsk_queue_get_child(&icsk->icsk_accept_queue, sk);
		BUG_TRAP(newsk->sk_state != TCP_SYN_RECV);
	out:
		release_sock(sk);
		return newsk;
	out_err:
		newsk = NULL;
		*err = error;
		goto out;
	}
```

象往常叙述的一样首先是在sock中取得struct inet_connection_sock结构,然后判断一下sock的状态是否已经处于监听状态，如果没有处于监听状态的话就不能接收了，只好出错返回了。接着是检查icsk中的icsk_accept_queue请求队列是否为空，因为我们练习中还未启动客户端程序，所以此时还没有连接请求到来，这个队列现在是空的，所以进入if语句，sock_rcvtimeo（）是根据是否允许“阻塞”即等待，而取得sock结构中的sk_rcvtimeo时间值，然后根据这个值进入inet_csk_wait_for_connect（）函数中

```
	sys_socketcall()-->sys_accept()-->inet_accept()-->inet_csk_accept()-->inet_csk_wait_for_connect()
	static int inet_csk_wait_for_connect(struct sock *sk, long timeo)
	{
		struct inet_connection_sock *icsk = inet_csk(sk);
		DEFINE_WAIT(wait);
		int err;
		/*
		 * True wake-one mechanism for incoming connections: only
		 * one process gets woken up, not the 'whole herd'.
		 * Since we do not 'race & poll' for established sockets
		 * anymore, the common case will execute the loop only once.
		 *
		 * Subtle issue: "add_wait_queue_exclusive()" will be added
		 * after any current non-exclusive waiters, and we know that
		 * it will always _stay_ after any new non-exclusive waiters
		 * because all non-exclusive waiters are added at the
		 * beginning of the wait-queue. As such, it's ok to "drop"
		 * our exclusiveness temporarily when we get woken up without
		 * having to remove and re-insert us on the wait queue.wumingxiaozu
		 */
		for (;;) {
			prepare_to_wait_exclusive(sk->sk_sleep, &wait,
						 TASK_INTERRUPTIBLE);
			release_sock(sk);
			if (reqsk_queue_empty(&icsk->icsk_accept_queue))
				timeo = schedule_timeout(timeo);
			lock_sock(sk);
			err = 0;
			if (!reqsk_queue_empty(&icsk->icsk_accept_queue))
				break;
			err = -EINVAL;
			if (sk->sk_state != TCP_LISTEN)
				break;
			err = sock_intr_errno(timeo);
			if (signal_pending(current))
				break;
			err = -EAGAIN;
			if (!timeo)
				break;
		}
		finish_wait(sk->sk_sleep, &wait);
		return err;
	}
```

函数首先是调用了宏来声明一个等待队列
```
	#define DEFINE_WAIT(name)                                \
	wait_queue_t name = {                                    \
		.private      = current,                             \
		.func         = autoremove_wake_function,            \
		.task_list    = LIST_HEAD_INIT((name).task_list),    \
	}
```
关于等待队列的具体概念我们留在以后专门的章节中论述，这里可以看出是根据当前进程而建立的名为wait的等待队列，接着函数中调用了

```
	sys_socketcall()-->sys_accept()-->inet_accept()-->inet_csk_accept()-->inet_csk_wait_for_connect()-->prepare_to_wait_exclusive()
	void
	prepare_to_wait_exclusive(wait_queue_head_t *q, wait_queue_t *wait, int state)
	{
		unsigned long flags;
		wait->flags |= WQ_FLAG_EXCLUSIVE;
		spin_lock_irqsave(&q->lock, flags);
		if (list_empty(&wait->task_list))
			__add_wait_queue_tail(q, wait);
		/*
		 * don't alter the task state if this is just going to
		  * queue an async wait queue callback wumingxiaozu
		 */
		if (is_sync_wait(wait))
			set_current_state(state);
		spin_unlock_irqrestore(&q->lock, flags);
	}
```

接着要把这里创建的wait，即当前进程的这里的等待队列挂入sk中的sk_sleep队列，这样我们可以理解到多个进程都可以对一个socket并发的连接，这个函数与我们所说的等待队列部分内容是密切相关的，我们只简单的叙述一下，函数中主要是将我们上面建立的等待队列插入到这里的sock结构中的sk_sleep所指定的等待队列头中，此后再次调用reqsk_queue_empty（）函数检查一下icsk_accept_queue是否为空，如果还为空就说明没有连接请求到来，开始睡眠等待了，schedule_timeout（）这个函数与时钟密切相关，所以请朋友们参考其他资料，这里是根据我们上面得到的定时时间来进入睡眠的。

当从这个函数返回时，再次锁住sock防止其他进程打扰，然后这里还是判断一下icsk_accept_queue是否为空，如果还为空的话就要跳出for循环了，醒来后还要检查一下是否是因为信号而醒来的，如果有信号就要处理信号signal_pending（），最后如果睡眠的时间已经用完了也会跳出循环，跳出循环后就要将这里的等待队列从sock中的sk_sleep中摘链。

我们回到inet_csk_accept（）函数中继续往下看，如果这时队列icsk_accept_queue不为空，即有连接请求到来怎么办呢，继续看下面的代码

```
	newsk = reqsk_queue_get_child(&icsk->icsk_accept_queue, sk);
```
这里看到是进入了reqsk_queue_get_child函数中

```
	sys_socketcall()-->sys_accept()-->inet_accept()-->inet_csk_accept()-->reqsk_queue_get_child()
	static inline struct sock *reqsk_queue_get_child(struct request_sock_queue *queue,
							 struct sock *parent)
	{
		struct request_sock *req = reqsk_queue_remove(queue);
		struct sock *child = req->sk;
		BUG_TRAP(child != NULL);
		sk_acceptq_removed(parent);
		__reqsk_free(req);
		return child;
	}
```
函数中首先是调用了reqsk_queue_remove（）从队列中摘下一个已经到来的request_sock结构

```
	sys_socketcall()-->sys_accept()-->inet_accept()-->inet_csk_accept()-->reqsk_queue_get_child()-->reqsk_queue_remove()
	static inline struct request_sock *reqsk_queue_remove(struct request_sock_queue *queue)
	{
		struct request_sock *req = queue->rskq_accept_head;
		BUG_TRAP(req != NULL);
		queue->rskq_accept_head = req->dl_next;
		if (queue->rskq_accept_head == NULL)
			queue->rskq_accept_tail = NULL;
		return req;
	}
```
很明显上面函数中是从队列的rskq_accept_head摘下一个已经到来的request_sock这个结构是从客户端请求连接时挂入的，reqsk_queue_get_child（）函数在这里把request_sock中载运的sock结构返回到inet_csk_accept中的局部变量newsk使用。而sk_acceptq_removed是递减我们服务器端sock中的sk_ack_backlog。

然后__reqsk_free释放掉request_sock结构。回到inet_csk_accept函数中，然后返回我们间接从icsk->icsk_accept_queue队列中获得了与客户端密切相关的sock结构。这个与客户端密切相关的结构是由我们服务器端在响应底层驱动的数据包过程中建立的，我们将在后边讲解完客户端的连接请求把这一过程补上，这里假设我们已经接收到了客户端的数据包并且服务器端为此专门建了这个与客户端数据包相联系的sock结构，接着返回到inet_accept()函数中，接着调用sock_graft（）函数，注意参数sock_graft(sk2, newsock);sk2是我们上边叙述的与客户端密切相关的sock结构，是从接收队列中获得的。

而newsock，则是我们服务器端为了这个代表客户端的sock结构而准备的新的socket。我们以前说过，socket结构在具体应用上分为二部分，另一部分是这里的sock结构，因为sock是与具体的协议即以前所说的规程的相关，所以变化比较大，而socket比较通用，所以我们上面通过socket_alloc()只是分配了通用部分的socket结构，并没有建立对应协议的sock结构，那么我们分配的新的socket的所需要的sock是从哪里来的呢，我们可以在代码中看到他是取的代表客户端的sock结构，与我们新建的socket挂入的，看一下这个关键的函数

```
	sys_socketcall()-->sys_accept()-->inet_accept()-->sock_graft()
	static inline void sock_graft(struct sock *sk, struct socket *parent)
	{
		write_lock_bh(&sk->sk_callback_lock);
		sk->sk_sleep = &parent->wait;
		parent->sk = sk;
		sk->sk_socket = parent;
		security_sock_graft(sk, parent);
		write_unlock_bh(&sk->sk_callback_lock);
	}
```

上面传递的参数是
```
	sock_graft(sk2, newsock);
```

sk2是代表我们客户端的sock，newsock是我们服务器端的新socket，可以看出上面的sock_graft,graft是嫁接的意思，从函数面上就可以理解了，然后其内部就是将服务器端新建的socket与客户端的sock“挂钩了”，从此以后，这个socket就是服务器端与客户端通讯的桥梁了。这样回到上面的inet_accept函数时，我们看到将newsock->state = SS_CONNECTED;也就是状态改变成了连接状态，而以前的服务器的socket并没有任何的状态改变，那个socket继续覆行他的使命“孵化”新的socket。回到我们的sys_accept()函数中下面接着看，我们在练习中看到需要获得客户端的地址，在那个章节中我们又走到了

```
	newsock->ops->getname(newsock, (struct sockaddr )address, &len, 2)
```

这要看我们在sys_accpet()函数中新创建的newsock的ops钩子结构了，很明显我们在sys_accept()函数中看到了newsock->ops = sock->ops;所以newsock是使用的已经建立的服务器端的inet_stream_ops结构变量，我们可以在这个结构中看到
```
	const struct proto_ops inet_stream_ops = {
		。。。。。。
		.getname     = inet_getname,
		。。。。。。
	};
```

因此进入了inet_getname()函数，这个函数在/net/ipv4/af_inet.c中的683行处。
```
	sys_accept()-->inet_getname()
	int inet_getname(struct socket *sock, struct sockaddr *uaddr,
				int *uaddr_len, int peer)
	{
		struct sock *sk        = sock->sk;
		struct inet_sock *inet    = inet_sk(sk);
		struct sockaddr_in *sin    = (struct sockaddr_in *)uaddr;
		sin->sin_family = AF_INET;
		if (peer) {
			if (!inet->dport ||
			 (((1  sk->sk_state) & (TCPF_CLOSE | TCPF_SYN_SENT)) &&
			 peer == 1))
				return -ENOTCONN;
			sin->sin_port = inet->dport;
			sin->sin_addr.s_addr = inet->daddr;
		} else {
			__be32 addr = inet->rcv_saddr;
			if (!addr)
				addr = inet->saddr;
			sin->sin_port = inet->sport;
			sin->sin_addr.s_addr = addr;
		}
		memset(sin->sin_zero, 0, sizeof(sin->sin_zero));
		*uaddr_len = sizeof(*sin);
		return 0;
	}
```

在上面的代码中，关键的是这二句

```
	sin->sin_port = inet->dport;
	sin->sin_addr.s_addr = inet->daddr;
```

这里直接将我们练习中的准备接收的数组address转换成tcp的地址结构struct sockaddr_in指针，然后直接用上面二句赋值了，我们看到他是使用的我们刚刚提到的从icsk->icsk_accept_queue接收队列中得到的sock进而得到了inet_sock专用于INET的sock结构

```
	struct inet_sock {
		/* sk and pinet6 has to be the first two members of inet_sock */
		struct sock        sk;
	#if defined(CONFIG_IPV6) || defined(CONFIG_IPV6_MODULE)
		struct ipv6_pinfo    *pinet6;
	#endif
		/* Socket demultiplex comparisons on incoming packets.wumingxiaozu */
		__be32               daddr;
		__be32               rcv_saddr;
		__be16               dport;
		__u16                num;
		__be32               saddr;
		__s16                uc_ttl;
		__u16                cmsg_flags;
		struct ip_options    *opt;
		__be16               sport;
		__u16                id;
		__u8                 tos;
		__u8                 mc_ttl;
		__u8                 pmtudisc;
		__u8                 recverr:1,
		                     is_icsk:1,
		                     freebind:1,
		                     hdrincl:1,
		                     mc_loop:1;
		int                  mc_index;
		__be32               mc_addr;
		struct ip_mc_socklist    *mc_list;
		struct {
			unsigned int        flags;
			unsigned int        fragsize;
			struct ip_options   *opt;
			struct dst_entry    *dst;
			int                 length; /* Total length of all frames */
			__be32              addr;
			struct flowi        fl;
		} cork;
	};
```

这个结构中的头一个变量就是sock结构，所以这里直接将sock的地址做为inet_sock结构的开始是完全可以的，这也就是inet_sk()这个函数的主要作用

```
	sys_accept()-->inet_getname()-->inet_sk()
	static inline struct inet_sock *inet_sk(const struct sock *sk)
	{
		return (struct inet_sock *)sk;
	}
```

那么可能会有朋友问我们只是从icsk->icsk_accept_queue接收队列中间接得到了sock结构指针并没有看到inet_sock结构指针啊？请朋友们相信我们在后边叙述完了客户端的连接请求过程后会把这部分给补上的，所以这里的inet_sock肯定是在服务器的底层驱动相关的部分完成的，我们将在完成客户端的连接后分析这部分的关键内容。所以我们看到这里将inet_sock结构中的请求方即客户端的端口和地址间接设置进了应用程序的地址结构变量client_address就取得了客户端的地址，这个过程是在sys_accept()中使用

```
	err = move_addr_to_user(address, len, upeer_sockaddr,
					upeer_addrlen);
```

将客户端的socket地址复制给我们的应用程序界面。我们上边已经通过inet_getname（）函数复制客户端的地址到address数组中了，这样通过move_addr_to_user()函数后，我们程序界面上client_address就得到了客户端的socket地址。接着我们看到函数执行了fd_install（）函数，即为新创建的socket分配一个文件号和file结构，有关没有详述的函数请朋友们参考深入理解LINUX内核第三版中的介绍，自己阅读暂且做为一种练习吧。 朋友们看到这里可以结合一下我们的地图，因为截止到现在我们都是围绕着地图中的服务器角度来分析的，接下来的章节我们将转换到客户端的角度来分析。

