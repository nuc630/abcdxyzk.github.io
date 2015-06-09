---
layout: post
title: "socket创建过程 sys_socket"
date: 2015-06-09 17:45:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://m.blog.chinaunix.net/uid-26905027-id-4031796.html

对于网络编程程序员来说sockfd = socket(AF_INET, SOCKET_DGRM, 0);这行代码是最熟悉不过，但这行代码的背后是......

1. socket这个api是库函数，我们直接调用就可以了，调用之后，产生0x80号软中断，linux系统由用户态切换到内核态，接着执行系统调用函数，在内核态执行相应的服务例程，针对socket这个函数，服务例程是sys_socket函数。至于这个过程是怎么实现的，在这里不阐述。下面我们分析sys_socket函数，看socket是怎么创建的。

2. 在分析sys_socket函数之前，我们先看一下sock_init初始化过程
   
```
	static int __init sock_init(void)
	{
		/*
		 * Initialize sock SLAB cache.
		 */

		sk_init(); 

		/*
		 * Initialize skbuff SLAB cache
		 */
		skb_init();

		/*
		 * Initialize the protocols module.
		 */

		init_inodecache();   //在这里创建了名为sock_inode_cache的cache
		register_filesystem(&sock_fs_type);
		sock_mnt = kern_mount(&sock_fs_type);

		/* The real protocol initialization is performed in later initcalls.
		 */

	#ifdef CONFIG_NETFILTER
		netfilter_init();
	#endif

		return 0;
	}

	struct socket_alloc {
		struct socket socket;
		struct inode vfs_inode;
	};

	static int init_inodecache(void)
	{
		sock_inode_cachep = kmem_cache_create("sock_inode_cache",
						sizeof(struct socket_alloc),         //在这里创建了名为sock_inode_cache，大小为sizeof(struct socket_alloc)的slab高速缓存  
                                                              //猜测创建slab高速缓存，而不是普通内存，那么操作socket结构就快了
						0,
						(SLAB_HWCACHE_ALIGN |
						SLAB_RECLAIM_ACCOUNT |
						SLAB_MEM_SPREAD),
						init_once,
						NULL);
		if (sock_inode_cachep == NULL)
			return -ENOMEM;
		return 0;
	}

	static struct vfsmount *sock_mnt __read_mostly;

	static struct file_system_type sock_fs_type = {    
		.name =        "sockfs",
		.get_sb =    sockfs_get_sb,
		.kill_sb =    kill_anon_super,
	};
    
	register_filesystem(&sock_fs_type);   //在这里注册了名为sockfs的VFS
	sock_mnt = kern_mount(&sock_fs_type);  //并在这里得到struct vfsmount 结构的sock_mnt变量，这个变量是全局变量，在创建socket的时候会用到

	static struct super_operations sockfs_ops = {
		.alloc_inode =    sock_alloc_inode,      //这里就是最终创建struct socket_alloc结构的函数
		.destroy_inode =sock_destroy_inode,
		.statfs =    simple_statfs,
	};

	static int sockfs_get_sb(struct file_system_type *fs_type,
			int flags, const char *dev_name, void *data,
			struct vfsmount *mnt)
	{
		return get_sb_pseudo(fs_type, "socket:", &sockfs_ops, SOCKFS_MAGIC,
								mnt);
	}

	static struct inode *sock_alloc_inode(struct super_block *sb)
	{
		struct socket_alloc *ei;

		ei = kmem_cache_alloc(sock_inode_cachep, GFP_KERNEL);  //在这里我们看到了memory allocate 操作
		if (!ei)
			return NULL;
		init_waitqueue_head(&ei->socket.wait);

		ei->socket.fasync_list = NULL;          //在这里对socket结构一些字段进行了初始化
		ei->socket.state = SS_UNCONNECTED;
		ei->socket.flags = 0;
		ei->socket.ops = NULL;
		ei->socket.sk = NULL;
		ei->socket.file = NULL;

		return &ei->vfs_inode;
	}
```

3. 前面进行的这些初始化，为后面做好了准备，接着往下看吧：

```
	asmlinkage long sys_socket(int family, int type, int protocol)
	{
		int retval;
		struct socket *sock;

		retval = sock_create(family, type, protocol, &sock);  //在这个函数完成了socket的创建过程
		if (retval < 0)
			goto out;

		retval = sock_map_fd(sock);  //把创建的socket和文件相关联，
		if (retval < 0)
			goto out_release;

	out:
		/* It may be already another descriptor 8) Not kernel problem. */
		return retval;

	out_release:
		sock_release(sock);
		return retval;
	}
```

sock_create函数是封装函数，实际调用的是__sock_create函数

```
	static int __sock_create(int family, int type, int protocol,
				struct socket **res, int kern)
	{
		int err;
		struct socket *sock;
		const struct net_proto_family *pf;

		/*
		 * Check protocol is in range
		 */
		if (family < 0 || family >= NPROTO)
			return -EAFNOSUPPORT;
		if (type < 0 || type >= SOCK_MAX)
			return -EINVAL;

		/* Compatibility.
		 * This uglymoron is moved from INET layer to here to avoid
		 * deadlock in module load.
         */
		if (family == PF_INET && type == SOCK_PACKET) {
			static int warned;
			if (!warned) {
				warned = 1;
				printk(KERN_INFO "%s uses obsolete (PF_INET,SOCK_PACKET)\n",
						current->comm);
			}
			family = PF_PACKET;
		}

		err = security_socket_create(family, type, protocol, kern);
		if (err)
			return err;

		/*
		 *    Allocate the socket and allow the family to set things up. if
		 *    the protocol is 0, the family is instructed to select an appropriate
		 *    default.
		 */
		sock = sock_alloc(); //这个函数调用了初始化时注册的创建socket和inode节点的回调函数，完成了socket和inode节点的创建。在unix和类unix系统中把socket当做文件节点来处理，所以有inode节点
                             //后面我们分析这个函数
		if (!sock) {
			if (net_ratelimit())
				printk(KERN_WARNING "socket: no more sockets\n");
			return -ENFILE;    /* Not exactly a match, but its the
								closest posix thing */
		}

		sock->type = type;

	#if defined(CONFIG_KMOD)
		/* Attempt to load a protocol module if the find failed.
		 *
		 * 12/09/1996 Marcin: this makes REALLY only sense, if the user
		 * requested real, full-featured networking support upon configuration.
		 * Otherwise module support will
		 */
		if (net_families[family] == NULL)
			request_module("net-pf-%d", family);
	#endif

		rcu_read_lock();
		pf = rcu_dereference(net_families[family]);  //根据协议族family得到struct net_proto_family结构，这个net_families数组在inet_init函数中初始化，稍后我们看看这个初始化过程
		err = -EAFNOSUPPORT;
		if (!pf)
			goto out_release;

		/*
		 * We will call the ->create function, that possibly is in a loadable
		 * module, so we have to bump that loadable module refcnt first.
		 */
		if (!try_module_get(pf->owner))
			goto out_release;

		/* Now protected by module ref count */
		rcu_read_unlock();

		err = pf->create(sock, protocol); //在这里创建了庞大的struct sock 结构，并进行了初始化。这个挂入的inet_create函数
		if (err < 0)
			goto out_module_put;

		/*
		 * Now to bump the refcnt of the [loadable] module that owns this
		 * socket at sock_release time we decrement its refcnt.
		 */
		if (!try_module_get(sock->ops->owner))
			goto out_module_busy;

		/*
		 * Now that we're done with the ->create function, the [loadable]
		 * module can have its refcnt decremented
		 */
		module_put(pf->owner);
		err = security_socket_post_create(sock, family, type, protocol, kern);
		if (err)
			goto out_release;
		*res = sock;

		return 0;

	out_module_busy:
		err = -EAFNOSUPPORT;
	out_module_put:
		sock->ops = NULL;
		module_put(pf->owner);
	out_sock_release:
		sock_release(sock);
		return err;

	out_release:
		rcu_read_unlock();
		goto out_sock_release;
	}
```

从上面的代码中看到_sock_create函数调用了回调函数完成了socket创建和初始化过程，下面我们看创建socket结构的过程：sock = sock_alloc();

```
	static struct socket *sock_alloc(void)
	{
		struct inode *inode;
		struct socket *sock;

		inode = new_inode(sock_mnt->mnt_sb); //在这里我们看到了sock_init函数中得到的全局变量sock_mnt，稍后看下new_inode函数
		if (!inode)
			return NULL;

		sock = SOCKET_I(inode); //得到了socket结构

		inode->i_mode = S_IFSOCK | S_IRWXUGO;
		inode->i_uid = current->fsuid;
		inode->i_gid = current->fsgid;

		get_cpu_var(sockets_in_use)++;
		put_cpu_var(sockets_in_use);
		return sock;
	}
	struct inode *new_inode(struct super_block *sb)
	{
		static unsigned long last_ino;
		struct inode * inode;

		spin_lock_prefetch(&inode_lock);
        
		inode = alloc_inode(sb);  //接着看这个函数
		if (inode) {
			spin_lock(&inode_lock);
			inodes_stat.nr_inodes++;
			list_add(&inode->i_list, &inode_in_use);
			list_add(&inode->i_sb_list, &sb->s_inodes);
			inode->i_ino = ++last_ino;
			inode->i_state = 0;
			spin_unlock(&inode_lock);
		}
		return inode;
	}
	static struct inode *alloc_inode(struct super_block *sb)
	{
		static const struct address_space_operations empty_aops;
		static struct inode_operations empty_iops;
		static const struct file_operations empty_fops;
		struct inode *inode;

		if (sb->s_op->alloc_inode) //在这里我们看到 if调节满足，因为在sock_init函数中我们挂入了sock_alloc_inode函数，之前我们也看到了sock_alloc_inode函数创建了sizeof(struct socket_alloc
                                   //大小的slab高速缓存
			inode = sb->s_op->alloc_inode(sb); 
		else
			inode = (struct inode *) kmem_cache_alloc(inode_cachep, GFP_KERNEL);

		if (inode) {
			struct address_space * const mapping = &inode->i_data;

			inode->i_sb = sb;
			inode->i_blkbits = sb->s_blocksize_bits;
			inode->i_flags = 0;
			atomic_set(&inode->i_count, 1);
			inode->i_op = &empty_iops;
			inode->i_fop = &empty_fops;
			inode->i_nlink = 1;
			atomic_set(&inode->i_writecount, 0);
			inode->i_size = 0;
			inode->i_blocks = 0;
			inode->i_bytes = 0;
			inode->i_generation = 0;
	#ifdef CONFIG_QUOTA
			memset(&inode->i_dquot, 0, sizeof(inode->i_dquot));
	#endif
			inode->i_pipe = NULL;
			inode->i_bdev = NULL;
			inode->i_cdev = NULL;
			inode->i_rdev = 0;
			inode->dirtied_when = 0;
			if (security_inode_alloc(inode)) {
				if (inode->i_sb->s_op->destroy_inode)
					inode->i_sb->s_op->destroy_inode(inode);
				else
					kmem_cache_free(inode_cachep, (inode));
				return NULL;
			}

			mapping->a_ops = &empty_aops;
			mapping->host = inode;
			mapping->flags = 0;
			mapping_set_gfp_mask(mapping, GFP_HIGHUSER);
			mapping->assoc_mapping = NULL;
			mapping->backing_dev_info = &default_backing_dev_info;

			/*
			 * If the block_device provides a backing_dev_info for client
			 * inodes then use that.  Otherwise the inode share the bdev's
			 * backing_dev_info.
			 */
			if (sb->s_bdev) {
				struct backing_dev_info *bdi;

				bdi = sb->s_bdev->bd_inode_backing_dev_info;
				if (!bdi)
					bdi = sb->s_bdev->bd_inode->i_mapping->backing_dev_info;
				mapping->backing_dev_info = bdi;
			}
			inode->i_private = NULL;
			inode->i_mapping = mapping;
		}
		return inode;
	}
```
    
从上面的分析中我们就可以很好的理解得到socket结构的过程：根据inode 得到socket

```
	sock = SOCKET_I(inode);  
	static inline struct socket *SOCKET_I(struct inode *inode)
	{
		return &container_of(inode, struct socket_alloc, vfs_inode)->socket;
	}
```

4. 现在创建socket结构的过程也就完成了，下面我们看看创建struct sock结构的过程

 在inet_init函数中，
```
	(void)sock_register(&inet_family_ops);

	static struct net_proto_family inet_family_ops = {
		.family = PF_INET,
		.create = inet_create,
		.owner    = THIS_MODULE,
	};
```
在这里我们看到了挂入的过程，net_families数组以family为下标，组成了各个协议创建函数，还记得执行create函数的地方吧？但在看这个函数以前先看看这里：

```
	/* Upon startup we insert all the elements in inetsw_array[] into
	 * the linked list inetsw.
	 */
	static struct inet_protosw inetsw_array[] =
	{
		{
			.type = SOCK_STREAM,
			.protocol = IPPROTO_TCP,
			.prot = &tcp_prot,
			.ops = &inet_stream_ops,
			.capability = -1,
			.no_check = 0,
			.flags = INET_PROTOSW_PERMANENT |
				INET_PROTOSW_ICSK,
		},

		{
			.type = SOCK_DGRAM,
			.protocol = IPPROTO_UDP,
			.prot = &udp_prot,
			.ops = &inet_dgram_ops,
			.capability = -1,
			.no_check = UDP_CSUM_DEFAULT,
			.flags = INET_PROTOSW_PERMANENT,
		},


		{
			.type = SOCK_RAW,
			.protocol = IPPROTO_IP,    /* wild card */
			.prot = &raw_prot,
			.ops = &inet_sockraw_ops,
			.capability = CAP_NET_RAW,
			.no_check = UDP_CSUM_DEFAULT,
			.flags = INET_PROTOSW_REUSE,
		}
	};

	//下面的代码是在inet_init函数中执行的
	/* Register the socket-side information for inet_create. */
		for (r = &inetsw[0]; r < &inetsw[SOCK_MAX]; ++r)
			INIT_LIST_HEAD(r);

		for (q = inetsw_array; q < &inetsw_array[INETSW_ARRAY_LEN]; ++q)
			inet_register_protosw(q);
```

我们来看看struct inet_protosw 这个结构

```
	/* This is used to register socket interfaces for IP protocols. */
	struct inet_protosw {
		struct list_head list;

		/* These two fields form the lookup key. */
		unsigned short     type;     /* This is the 2nd argument to socket(2). */
		unsigned short     protocol; /* This is the L4 protocol number. */

		struct proto     *prot;
		const struct proto_ops *ops;

		int capability; /* Which (if any) capability do
						 * we need to use this socket
						 * interface?
                                          */
		char no_check; /* checksum on rcv/xmit/none? */
		unsigned char     flags; /* See INET_PROTOSW_* below. */
	};
```


```
	/*
	 *    Create an inet socket. //从这个注释中我们可以看到，还可以创建其他类型的socket
	 */

	static int inet_create(struct socket *sock, int protocol)
	{
		struct sock *sk;
		struct list_head *p;
		struct inet_protosw *answer;
		struct inet_sock *inet;
		struct proto *answer_prot;
		unsigned char answer_flags;
		char answer_no_check;
		int try_loading_module = 0;
		int err;

		sock->state = SS_UNCONNECTED;

		/* Look for the requested type/protocol pair. */
		answer = NULL;
	lookup_protocol:
		err = -ESOCKTNOSUPPORT;
		rcu_read_lock();
		list_for_each_rcu(p, &inetsw[sock->type]) {   //在这里我们遍历inetsw数组，根据是UDP，TCP，RAW类型得到了struct inet_protosw结构
			answer = list_entry(p, struct inet_protosw, list);

			/* Check the non-wild match. */
			if (protocol == answer->protocol) {
				if (protocol != IPPROTO_IP)
					break;
			} else {
				/* Check for the two wild cases. */
				if (IPPROTO_IP == protocol) {
					protocol = answer->protocol;
					break;
				}
				if (IPPROTO_IP == answer->protocol)
					break;
			}
			err = -EPROTONOSUPPORT;
			answer = NULL;
		}

		if (unlikely(answer == NULL)) {
			if (try_loading_module < 2) {
				rcu_read_unlock();
				/*
				 * Be more specific, e.g. net-pf-2-proto-132-type-1
				 * (net-pf-PF_INET-proto-IPPROTO_SCTP-type-SOCK_STREAM)
				 */
				if (++try_loading_module == 1)
					request_module("net-pf-%d-proto-%d-type-%d",
							PF_INET, protocol, sock->type);
				/*
				 * Fall back to generic, e.g. net-pf-2-proto-132
				 * (net-pf-PF_INET-proto-IPPROTO_SCTP)
				 */
				else
					request_module("net-pf-%d-proto-%d",
							PF_INET, protocol);
				goto lookup_protocol;
			} else
				goto out_rcu_unlock;
		}

		err = -EPERM;
		if (answer->capability > 0 && !capable(answer->capability))
			goto out_rcu_unlock;

		sock->ops = answer->ops;    //对socket结构进行了初始化
		answer_prot = answer->prot;
		answer_no_check = answer->no_check;
		answer_flags = answer->flags;
		rcu_read_unlock();

		BUG_TRAP(answer_prot->slab != NULL);

		err = -ENOBUFS;
		sk = sk_alloc(PF_INET, GFP_KERNEL, answer_prot, 1);   //这个函数创建了struct sock 这个庞然大物
		if (sk == NULL)
			goto out;

		err = 0;
		sk->sk_no_check = answer_no_check;
		if (INET_PROTOSW_REUSE & answer_flags)
			sk->sk_reuse = 1;

		inet = inet_sk(sk);
		inet->is_icsk = (INET_PROTOSW_ICSK & answer_flags) != 0;

		if (SOCK_RAW == sock->type) {
			inet->num = protocol;
			if (IPPROTO_RAW == protocol)
				inet->hdrincl = 1;
		}

		if (ipv4_config.no_pmtu_disc)
			inet->pmtudisc = IP_PMTUDISC_DONT;
		else
			inet->pmtudisc = IP_PMTUDISC_WANT;

		inet->id = 0;

		sock_init_data(sock, sk);  //在这里对struct sock里面重要的字段进行了初始化，包括接受队列，发送队列，以及长度等

		sk->sk_destruct     = inet_sock_destruct;   
		sk->sk_family     = PF_INET;
		sk->sk_protocol     = protocol;
		sk->sk_backlog_rcv = sk->sk_prot->backlog_rcv;

		inet->uc_ttl    = -1;
		inet->mc_loop    = 1;
		inet->mc_ttl    = 1;
		inet->mc_index    = 0;
		inet->mc_list    = NULL;

		sk_refcnt_debug_inc(sk);

		if (inet->num) {    //我们看到当我们调用RAW类型的socket的时候，这个if条件就成立了
			/* It assumes that any protocol which allows
			 * the user to assign a number at socket
			 * creation time automatically
			 * shares.
			 */
			inet->sport = htons(inet->num);
			/* Add to protocol hash chains. */
			sk->sk_prot->hash(sk);
		}

		if (sk->sk_prot->init) {           //看L4层是否注册了初始化函数，我们看到UDP类型的socket为空，而TCP类型的socket注册了初始化函数
			err = sk->sk_prot->init(sk);
			if (err)
				sk_common_release(sk);
		}
	out:
		return err;
	out_rcu_unlock:
		rcu_read_unlock();
		goto out;
	}
```

```
	void sock_init_data(struct socket *sock, struct sock *sk)
	{
		skb_queue_head_init(&sk->sk_receive_queue); //接受队列
		skb_queue_head_init(&sk->sk_write_queue);   //发送队列
		skb_queue_head_init(&sk->sk_error_queue);
	#ifdef CONFIG_NET_DMA
		skb_queue_head_init(&sk->sk_async_wait_queue);
	#endif

		sk->sk_send_head    =    NULL;

		init_timer(&sk->sk_timer);

		sk->sk_allocation    =    GFP_KERNEL;
		sk->sk_rcvbuf        =    sysctl_rmem_default;  //接受缓冲区大小
		sk->sk_sndbuf        =    sysctl_wmem_default;  //发送缓冲区大小
		sk->sk_state        =    TCP_CLOSE;   //被初始化为TCP_CLOSE，再下一篇绑定分析中我们会看到会检查这个状态
		sk->sk_socket        =    sock;

		sock_set_flag(sk, SOCK_ZAPPED);

		if(sock)
		{
			sk->sk_type    =    sock->type;
			sk->sk_sleep    =    &sock->wait;
			sock->sk    =    sk;
		} else
			sk->sk_sleep    =    NULL;

		rwlock_init(&sk->sk_dst_lock);
		rwlock_init(&sk->sk_callback_lock);
		lockdep_set_class(&sk->sk_callback_lock,
				af_callback_keys + sk->sk_family);

		sk->sk_state_change    =    sock_def_wakeup;
		sk->sk_data_ready    =    sock_def_readable;
		sk->sk_write_space    =    sock_def_write_space;
		sk->sk_error_report    =    sock_def_error_report;
		sk->sk_destruct        =    sock_def_destruct;

		sk->sk_sndmsg_page    =    NULL;
		sk->sk_sndmsg_off    =    0;

		sk->sk_peercred.pid     =    0;
		sk->sk_peercred.uid    =    -1;
		sk->sk_peercred.gid    =    -1;
		sk->sk_write_pending    =    0;
		sk->sk_rcvlowat        =    1;
		sk->sk_rcvtimeo        =    MAX_SCHEDULE_TIMEOUT;
		sk->sk_sndtimeo        =    MAX_SCHEDULE_TIMEOUT;

		sk->sk_stamp.tv_sec = -1L;
		sk->sk_stamp.tv_usec = -1L;

		atomic_set(&sk->sk_refcnt, 1);
	}
```

