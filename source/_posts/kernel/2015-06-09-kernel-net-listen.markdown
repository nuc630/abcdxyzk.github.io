---
layout: post
title: "socket监听连接 sys_listen"
date: 2015-06-09 17:50:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/justlinux2010/article/details/8597498

listen()函数仅在TCP服务器端调用，它做两个事情：将套接字转换到LISTEN状态和设置套接上的最大连接队列。listen()对应的内核实现为sys_listen()，下面开始对其实现作具体的分析。

#### 一、sys_listen()函数

sys_listen()的源码实现及分析如下所示：

```
	/* 
	 *  Perform a listen. Basically, we allow the protocol to do anything 
	 *  necessary for a listen, and if that works, we mark the socket as 
	 *  ready for listening. 
	 */  

	SYSCALL_DEFINE2(listen, int, fd, int, backlog)  
	{  
		struct socket *sock;  
		int err, fput_needed;  
		int somaxconn;  
	  
		sock = sockfd_lookup_light(fd, &err, &fput_needed);  
		if (sock) {  
			/* 
			 * sysctl_somaxconn存储的是服务器监听时，允许每个套接字连接队列长度  
			 * 的最大值，默认值是SOMAXCONN，即128，在sysctl_core_net_init()函数中初始化。 
			 * 在proc文件系统中可以通过修改/proc/sys/net/core/somaxconn文件来修改这个值。 
			 */  
			somaxconn = sock_net(sock->sk)->core.sysctl_somaxconn;  
			/* 
			 * 如果指定的最大连接数超过系统限制，则使用系统当前允许的连接队列 
			 * 中连接的最大数。 
			 */  
			if ((unsigned)backlog > somaxconn)  
				backlog = somaxconn;  
	  
			err = security_socket_listen(sock, backlog);  
			if (!err)  
				/* 
				 * 如果是TCP套接字，sock->ops指向的是inet_stream_ops， 
				 * sock->ops是在inet_create()函数中初始化，所以listen接口 
				 * 调用的是inet_listen()函数。 
				 */  
				err = sock->ops->listen(sock, backlog);  
	  
			fput_light(sock->file, fput_needed);  
		}  
		return err;  
	}  
```

sys_listen()的代码流程图如下所示：

```
		sys_listen()
			|
			|---> sockfd_lookup_light()
			|
			|---> 确定最大连接队列
			|
			 ---> inet_listen()
```

sys_listen()的代码流程和sys_bind()很像，都是先调用sockfd_lookup_light()获取描述符对应的socket实例，然后通过调用sock->ops中的操作接口来完成真正的操作。接下来看这段代码：

```
	if ((unsigned)backlog > somaxconn)  
				backlog = somaxconn;  
```

这里可以看出，如果指定的最大连接队列数超过系统限制，会使用系统中设置的最大连接队列数。所以，如果想扩大套接字的连接队列，只调整listen()的backlog参数是没用的，还要修改系统的设置才行。

#### 二、inet_listen()函数

inet_listen()的源码实现及分析如下所示：
```
	/* 
	 *  Move a socket into listening state. 
	 */  
	/* 
	 * inet_listen()函数为listen系统调用套接字层的实现。 
	 */  
	int inet_listen(struct socket *sock, int backlog)  
	{  
		struct sock *sk = sock->sk;  
		unsigned char old_state;  
		int err;  
	  
		lock_sock(sk);  
	  
		err = -EINVAL;  
		/* 
		 * 检测调用listen的套接字的当前状态和类型。如果套接字状态 
		 * 不是SS_UNCONNECTED，或套接字类型不是SOCK_STREAM，则不 
		 * 允许进行监听操作，返回相应错误码 
		 */  
		if (sock->state != SS_UNCONNECTED || sock->type != SOCK_STREAM)  
			goto out;  
	  
		old_state = sk->sk_state;  
		/* 
		 * 检查进行listen调用的传输控制块的状态。如果该传输控制块不在 
		 * 在TCPF_CLOSE或TCPF_LISTEN状态，则不能进行监听操作，返回 
		 * 相应错误码 
		 */  
		if (!((1 << old_state) & (TCPF_CLOSE | TCPF_LISTEN)))  
			goto out;  
	  
		/* Really, if the socket is already in listen state 
		 * we can only allow the backlog to be adjusted. 
		 */  
		/* 
		 * 如果传输控制块不在LISTEN状态，则调用inet_csk_listen_start() 
		 * 进行监听操作。最后，无论是否在LISTEN状态都需要设置传输控制块 
		 * 的连接队列长度的上限。从这里可以看出，可以通过调用listen() 
		 * 来修改最大连接队列的长度。 
		 */  
		if (old_state != TCP_LISTEN) {  
			err = inet_csk_listen_start(sk, backlog);  
			if (err)  
				goto out;  
		}  
		sk->sk_max_ack_backlog = backlog;  
		err = 0;  
	  
	out:  
		release_sock(sk);  
		return err;  
	}  
```

inet_listen()首先检查套接字的状态及类型，如果状态和类型不适合进行listen操作，则返回EINVAL错误。如果套接字的当前状态不是LISTEN状态，则调用inet_csk_listen_start()来分配管理接收队列的内存，并且将套接字状态转换为LISTEN状态。如果套接字状态已经是LISTEN状态，则只修改套接字中sk_max_ack_backlog成员，即连接队列的上限。从这里可以看出，可以通过调用listen()来修改连接队列的上限。但是这里有一个问题，假设套接的当前状态是LISTEN状态，连接队列的长度是100，这时调用listen()来将连接队列的长度修改为1024（假设已修改/proc/sys/net/core/somaxconn文件提高系统限制），但从代码看来并没有调用inet_csk_listen_start()来重新分配管理连接队列的内存，管理连接队列的内存没有变化，是不是会没有效果呢？其实不然，inet_csk_listen_start()中分配的内存除了listen_sock管理结构外，用作半连接队列的哈希表槽位。哈希表中可以容纳的元素个数和listen()中的backlog参数有关（和系统设置有关，还会对齐到2的整数次幂），和哈希表的槽位个数是没有关系的，参见reqsk_queue_alloc()函数。

下面来看这行代码：

```
	sk->sk_max_ack_backlog = backlog;  
```

其中sk_max_ack_backlog存储的是套接字的连接队列的上限，即accept队列的上限，但是这个上限值并不意味着连接队列中只能有sk_max_ack_backlog指定的数量。还有一个地方需要说明的是，《Unix网络编程》中讲到listen()时，说第二个参数的值是半连接队列和连接队列的个数之和，但是在linux中不是这样的，简单地说，listen()的第二个参数既是半连接队列的长度，也是连接队列的长度，并不是两者的和。这样说不太准确，后面会专门写一篇关于listen()的第二个参数backlog的分析。

#### 三、inet_csk_listen_start()函数

inet_csk_listen_start()的源码实现及分析如下：

```
	/* 
	 * 使TCP传输控制块进入监听状态，实现监听状态:为管理连接 
	 * 请求块的散列表分配存储空间，接着使TCP传输控制块的状态 
	 * 迁移到LISTEN状态，然后将传输控制块添加到监听散列表中。 
	 * @nr_table_entries:允许连接的队列长度上限，通过此值 
	 *                   合理计算出存储连接请求块的散列表大小 
	 */  
	int inet_csk_listen_start(struct sock *sk, const int nr_table_entries)  
	{  
		struct inet_sock *inet = inet_sk(sk);  
		struct inet_connection_sock *icsk = inet_csk(sk);  
		/* 
		 * 为管理连接请求块的散列表分配存储空间，如果分配失败则返回 
		 * 相应错误码 
		 */  
		int rc = reqsk_queue_alloc(&icsk->icsk_accept_queue, nr_table_entries);  
	  
		if (rc != 0)  
			return rc;  
	  
		/* 
		 * 初始化连接队列长度上限，清除当前已建立连接数 
		 */  
		sk->sk_max_ack_backlog = 0;  
		sk->sk_ack_backlog = 0;  
		/* 
		 * 初始化传输控制块中与延时发送ACK段有关的控制数据结构icsk_ack 
		 */  
		inet_csk_delack_init(sk);  
	  
		/* There is race window here: we announce ourselves listening, 
		 * but this transition is still not validated by get_port(). 
		 * It is OK, because this socket enters to hash table only 
		 * after validation is complete. 
		 */  
		/* 
		 * 设置传输控制块状态为监听状态 
		 */  
		sk->sk_state = TCP_LISTEN;  
		/* 
		 * 调用的是inet_csk_get_port()，如果没有绑定端口，则进行绑定 
		 * 端口操作；如果已经绑定了端口，则对绑定的端口进行校验。绑定 
		 * 或校验端口成功后，根据端口号在传输控制块中设置网络字节序的 
		 * 端口号成员，然后再清除缓存在传输控制块中的目的路由缓存，最后 
		 * 调用hash接口inet_hash()将该传输控制块添加到监听散列表listening_hash 
		 * 中，完成监听 
		 */  
		if (!sk->sk_prot->get_port(sk, inet->num)) {  
			inet->sport = htons(inet->num);  
	  
			sk_dst_reset(sk);  
			sk->sk_prot->hash(sk);  
	  
			return 0;  
		}  
	  
		/* 
		 * 如果绑定或校验端口失败，则说明监听失败，设置传输控制块状态 
		 * 为TCP_CLOSE状态 
		 */  
		sk->sk_state = TCP_CLOSE;  
		/* 
		 * 释放之前分配的inet_bind_bucket实例 
		 */  
		__reqsk_queue_destroy(&icsk->icsk_accept_queue);  
		return -EADDRINUSE;  
	}  
```

inet_csk_listen_start()首先调用reqsk_queue_alloc()来分配管理连接队的内存，如果分配成功，则开始初始化sock结构中与连接队列相关的成员，并将套接字的状态设置为LISTEN状态。在上述工作完成后，该函数还要检查当前套接字是否已经绑定本地协议地址，如果没有绑定，则内核会自动为套接字分配一个可用端口，当前这种情况一般不会发生，如果发生那就是你的服务器程序忘记调用bind()了。

#### 四、reqsk_queue_alloc()函数

reqsk_queue_alloc()的源码实现及分析如下所示：

```
	/* 
	 * 用来分配连接请求块散列表，然后将其连接到所在传输控制块的请求 
	 * 块容器中。 
	 */  
	int reqsk_queue_alloc(struct request_sock_queue *queue,  
				  unsigned int nr_table_entries)  
	{  
		size_t lopt_size = sizeof(struct listen_sock);  
		struct listen_sock *lopt;  
	  
		/* 
		 * 取用户设定的连接队列长度最大值参数nr_table_entries和系统最多 
		 * 可同时存在未完成三次握手SYN请求数sysctl_max_syn_backlog两者的 
		 * 最小值，他们都用来控制连接队列的长度，只是前者针对某传输控制 
		 * 块，而后者控制的是全局的 
		 */  
		nr_table_entries = min_t(u32, nr_table_entries, sysctl_max_syn_backlog);  
		nr_table_entries = max_t(u32, nr_table_entries, 8);  
		/* 
		 * 调用roundup_pow_of_two以确保nr_table_entries的值为2的n次方 
		 */  
		nr_table_entries = roundup_pow_of_two(nr_table_entries + 1);  
		/* 
		 * 计算用来保存SYN请求连接的listen_sock结构的大小 
		 */  
		lopt_size += nr_table_entries * sizeof(struct request_sock *);  
		if (lopt_size > PAGE_SIZE)  
			/* 
			 * 如果用于保存SYN请求连接的listen_sock结构大于一个页面， 
			 * 则调用__vmalloc()从高位内存中分配虚拟内存，并且清零 
			 */  
			lopt = __vmalloc(lopt_size,  
				GFP_KERNEL | __GFP_HIGHMEM | __GFP_ZERO,  
				PAGE_KERNEL);  
		else  
			/* 
			 * 如果小于一个页面，则在常规内存中分配内存并清零。kzalloc() 
			 * 封装了kmalloc()及memset() 
			 */  
			lopt = kzalloc(lopt_size, GFP_KERNEL);  
		if (lopt == NULL)  
			return -ENOMEM;  
		/* 
		 * 从nr_table_entries = max_t(u32, nr_table_entries, 8);中可以看出 
		 * nr_table_entries最小值为8，所以这里从3开始 
		 */  
		for (lopt->max_qlen_log = 3;  
			 (1 << lopt->max_qlen_log) < nr_table_entries;  
			 lopt->max_qlen_log++);  
	  
		/* 
		 * 初始化listen_sock结构中的一些成员，如用于生成连接请求块 
		 * 散列表的hash_rnd等 
		 */  
		get_random_bytes(&lopt->hash_rnd, sizeof(lopt->hash_rnd));  
		rwlock_init(&queue->syn_wait_lock);  
		queue->rskq_accept_head = NULL;  
		lopt->nr_table_entries = nr_table_entries;  
	  
		/* 
		 * 将散列表连接到所在传输控制块的请求块容器中 
		 */  
		write_lock_bh(&queue->syn_wait_lock);  
		queue->listen_opt = lopt;  
		write_unlock_bh(&queue->syn_wait_lock);  
	  
		return 0;  
	}  
```

从上面的代码中可以看到半连接队列长度的计算过程，nr_table_entries的值存储的就是计算的结果，这个值是基于listen()的第二个参数的值计算得到的。半连接队列的上限值的以2为底的对数存储在lopt的max_qlen_log成员中，对数的计算是通过下面的代码完成的，如下所示：

```
	for (lopt->max_qlen_log = 3;  
			 (1 << lopt->max_qlen_log) < nr_table_entries;  
			 lopt->max_qlen_log++);  
```

#### 五、结束语

在listen()系统调用中，第二个参数backlog对服务器的程序影响是很大的，而且不同的系统对这个参数的使用可能有所不同。前面我们也提到了，《Unix网络编程》中对第二参数backlog的描述是连接队列和半连接队列的长度之和不超过backlog，但是在Linux中并不是这样，限于篇幅，后面会单独写一篇关于backlog参数的分析文章来详细介绍。


