---
layout: post
title: "socket和sock的一些分析"
date: 2015-06-12 16:55:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/wolongzhumeng/article/details/8900414

1、每一个打开的文件、socket等等都用一个file数据结构代表，这样文件和socket就通过inode->u(union)中的各个成员来区别：
```
	struct inode {
		.....................
		union {
			struct ext2_inode_info ext2_i;
			struct ext3_inode_info ext3_i;
			struct socket socket_i;
			.....................
		} u;
	};
```

2、每个socket数据结构都有一个sock数据结构成员，sock是对socket的扩充，两者一一对应，socket->sk指向对应的sock，sock->socket 指向对应的socket；

3、socket和sock是同一事物的两个侧面，为什么不把两个数据结构合并成一个呢？这是因为socket是inode结构中的一部分，即把inode结
构内部的一个union用作socket结构。由于插口操作的特殊性，这个数据结构中需要有大量的结构成分，如果把这些成分全部放到socket
结构中，则inode结构中的这个union就会变得很大，从而inode结构也会变得很大，而对于其他文件系统这个union是不需要这么大的，
所以会造成巨大浪费，系统中使用inode结构的数量要远远超过使用socket的数量，故解决的办法就是把插口分成两部分，把与文件系
统关系密切的放在socket结构中，把与通信关系密切的放在另一个单独结构sock中；

```
	struct socket
	{
		socket_state state;      // 该state用来表明该socket的当前状态
		typedef enum {
			SS_FREE = 0,         /* not allocated */
			SS_UNCONNECTED,      /* unconnected to any socket */
			SS_CONNECTING,       /* in process of connecting */
			SS_CONNECTED,        /* connected to socket */
			SS_DISCONNECTING     /* in process of disconnecting */
		} socket_state;
		unsigned long flags;     //该成员可能的值如下，该标志用来设置socket是否正在忙碌
		#define SOCK_ASYNC_NOSPACE 0
		#define SOCK_ASYNC_WAITDATA 1
		#define SOCK_NOSPACE 2
		struct proto_ops *ops;   //依据协议邦定到该socket上的特定的协议族的操作函数指针，例如IPv4 TCP就是inet_stream_ops
		struct inode *inode;     //表明该socket所属的inode
		struct fasync_struct *fasync_list; //异步唤醒队列
		struct file *file;       //file回指指针
		struct sock *sk;         //sock指针
		wait_queue_head_t wait;  //sock的等待队列，在TCP需要等待时就sleep在这个队列上
		short type;              //表示该socket在特定协议族下的类型例如SOCK_STREAM,
		unsigned char passcred;  //在TCP分析中无须考虑
	};

	struct sock {
		/* socket用来对进入的包进行匹配的5大因素 */
		__u32 daddr;        // dip，Foreign IPv4 addr
		__u32 rcv_saddr;    // 记录套接字所绑定的地址 Bound local IPv4 addr
		__u16 dport;        // dport
		unsigned short num; /* 套接字所在的端口号, 端口号小于1024的为特权端口, 只有特权用户才能绑定,当用户指定的端
							 * 口号为零时, 系统将提供一个未分配的用户端口，如果对于raw socket的话，该num又可以用来
							 * 保存socket(int family, int type, int protocol)中的protocol，而不是端口号了；在bind时候，会首先
							 * 将邦定的源端口号赋予该成员，最终sport成员从该成员出获取源端口号__tcp_v4_hash主要就
							 * 是利用了该成员来hash从而排出hash链
							 */
		int bound_dev_if;   // Bound device index if != 0

		/* 主hash链，系统已分配的端口用tcp_hashinfo.__tcp_bhash来索引, 索引槽结构为tcp_bind_hashbucket, 端口绑定结构用tcp_bind_bucket描述,
		它包含指向绑定到该端口套接字的指针(owners), 套接字的sk->prev指针指向该绑定结构 */
		struct sock *next;
		struct sock **pprev;
		/* sk->bind_next和sk->bind_pprev用来描述绑定到同一端口的套接字，例如http服务器 */
		struct sock *bind_next;
		struct sock **bind_pprev;
		struct sock *prev;

		volatile unsigned char state, zapped; // Connection state，zapped在TCP分析中无须考虑
		__u16 sport;                   // 源端口，见num

		unsigned short family;         // 协议族，例如PF_INET
		unsigned char reuse;           // 地址是否可重用，只有RAW才使用
		unsigned char shutdown;        // 判断该socket连接在某方向或者双向方向上都已经关闭
		#define SHUTDOWN_MASK 3
		#define RCV_SHUTDOWN 1
		#define SEND_SHUTDOWN 2
		atomic_t refcnt;               // 引用计数
		socket_lock_t lock;            // 锁标志， 每个socket都有一个自旋锁，该锁在用户上下文和软中断处理时提供了同步机制
		typedef struct {
			spinlock_t slock;
			unsigned int users;
			wait_queue_head_t wq;
		} socket_lock_t;
		wait_queue_head_t *sleep;      // Sock所属线程的自身休眠等待队列
		struct dst_entry *dst_cache;   // 目的地的路由缓存
		rwlock_t dst_lock;             // 为该socket赋dst_entry值时的锁

		/* sock的收发都是要占用内存的，即发送缓冲区和接收缓冲区。 系统对这些内存的使用是有限制的。 通常，每个sock都会从配额里
			预先分配一些，这就是forward_alloc， 具体分配时：
			1）比如收到一个skb，则要计算到rmem_alloc中，并从forward_alloc中扣除。 接收处理完成后（如用户态读取），则释放skb，并利
				用tcp_rfree()把该skb的内存反还给forward_alloc。
			2）发送一个skb，也要暂时放到发送缓冲区，这也要计算到wmem_queued中，并从forward_alloc中扣除。真正发送完成后，也释放
				skb，并反还forward_alloc。 当从forward_alloc中扣除的时候，有可能forward_alloc不够，此时就要调用tcp_mem_schedule()来增
				加forward_alloc，当然，不是随便想加就可以加的，系统对整个TCP的内存使用有总的限制，即sysctl_tcp_mem[3]。也对每个sock
				的内存使用分别有限制，即sysctl_tcp_rmem[3]和sysctl_tcp_wmem[3]。只有满足这些限制（有一定的灵活性），forward_alloc才
				能增加。 当发现内存紧张的时候，还会调用tcp_mem_reclaim()来回收forward_alloc预先分配的配额。
		*/
		int rcvbuf;                    // 接受缓冲区的大小（按字节）
		int sndbuf;                    // 发送缓冲区的大小（按字节）
		atomic_t rmem_alloc;           // 接受队列中存放的数据的字节数
		atomic_t wmem_alloc;           // 发送队列中存放的数据的字节数
		int wmem_queued;               // 所有已经发送的数据的总字节数
		int forward_alloc;             // 预分配剩余字节数

		struct sk_buff_head receive_queue; // 接受队列
		struct sk_buff_head write_queue;   // 发送队列
		atomic_t omem_alloc;               // 在TCP分析中无须考虑 * "o" is "option" or "other" */

		__u32 saddr; /* 指真正的发送地址，这里需要注意的是，rcv_saddr是记录套接字所绑定的地址，其可能是广播或者
						多播，对于我们要发送的包来说，只能使用接口的IP地址，而不能使用广播或者多播地址 */
		unsigned int allocation;       // 分配该sock之skb时选择的模式，GFP_ATOMIC还是GFP_KERNEL等等

		volatile char dead,            // tcp_close.tcp_listen_stop.inet_sock_release调用sock_orphan将该值置1，表示该socket已经和进程分开，变成孤儿
					done,              // 用于判断该socket是否已经收到 fin，如果收到则将该成员置1
					urginline,         // 如果该值被设置为1，表示将紧急数据放于普通数据流中一起处理，而不在另外处理
					keepopen,          // 是否启动保活定时器
					linger,            // lingertime一起，指明了close()后保留的时间
					destroy,           // 在TCP分析中无须考虑
					no_check,          // 是否对发出的skb做校验和，仅对UDP有效
					broadcast,         // 是否允许广播，仅对UPD有效
					bsdism;            // 在TCP分析中无须考虑
		unsigned char debug;           // 在TCP分析中无须考虑
		unsigned char rcvtstamp;       // 是否将收到skb的时间戳发送给app
		unsigned char use_write_queue; // 在init中该值被初始化为1，该值一直没有变化
		unsigned char userlocks;       // 包括如下几种值的组合，从而改变收包等操作的执行顺序
		#define SOCK_SNDBUF_LOCK 1
		#define SOCK_RCVBUF_LOCK 2
		#define SOCK_BINDADDR_LOCK 4
		#define SOCK_BINDPORT_LOCK 8
		int route_caps;                // 指示本sock用到的路由的信息
		int proc;                      // 保存用户线程的pid
		unsigned long lingertime;      // lingertime一起，指明了close()后保留的时间
		int hashent;                   // 存放4元的hash值
		struct sock *pair;             // 在TCP分析中无须考虑

		/* 一个进程也许会锁住socket导致该socket不能被改变。特别是这点意味着其甚至不能被驱动中断所改变，例如，
			到达的报会被堵塞，导致我们无法获取新的数据或者任何的状态改变。所以在这里，当socket被锁住的时候，中
			断处理可以将包往下面的backlog中添加*/
		struct {
			struct sk_buff *head;
			struct sk_buff *tail;
		} backlog;

		rwlock_t callback_lock;          // sock相关函数内部操作的保护锁
		struct sk_buff_head error_queue; // 错误报文的队列，很少使用
		struct proto *prot;              // 例如指向tcp_prot

		union {       // 私有TCP相关数据保存
			struct tcp_opt af_tcp;
			.............
		} tp_pinfo;

		int err,      // 保存各种错误，例如ECONNRESET Connection reset by peer，从而会影响到后续流程的处理
			err_soft; // 保存各种软错误，例如EPROTO Protocol error，从而会影响到后续流程的处理
		unsigned short ack_backlog;       // 当前已经accept的数目
		unsigned short max_ack_backlog;   // 当前listen sock能保留多少个待处理TCP连接.
		__u32 priority;                   /* Packet queueing priority，Used to set the TOS field. Packets with a higher priority may be processed first, depending on the device’s queueing discipline. See SO_PRIORITY */
		unsigned short type;              // 例如SOCK_STREAM，SOCK_DGRAM或者SOCK_RAW等
		unsigned char localroute;         // Route locally only if set – set by SO_DONTROUTE option.
		unsigned char protocol;           // socket(int family, int type, int protocol)中的protocol
		struct ucred peercred;            // 在TCP分析中无须考虑
		int rcvlowat;                     /* 声明在开始发送 数据 (SO_SNDLOWAT) 或正在接收数据的用户 (SO_RCVLOWAT) 传递数据之
		前缓冲区内的最小字节数. 在 Linux 中这两个值是不可改变的, 固定为 1 字节. */
		long rcvtimeo;                    // 接收时的超时设定, 并在超时时报错
		long sndtimeo;                    // 发送时的超时设定, 并在超时时报错

		union {       // 私有inet相关数据保存
			struct inet_opt af_inet;
			.................
		} protinfo;

		/* the timer is used for SO_KEEPALIVE (i.e. sending occasional keepalive probes to a remote site – by default, set to 2 hours in
		stamp is simply the time that the last packet was received. */
		struct timer_list timer;
		struct timeval stamp;
		struct socket *socket; // 对应的socket
		void *user_data;       // 私有数据，在TCP分析中无须考虑

		/* The state_change operation is called whenever the status of the socket is changed. Similarly, data_ready is called
			when data have been received, write_space when free memory available for writing has increased and error_report
			when an error occurs, backlog_rcv when socket locked, putting skb to backlog, destruct for release this sock*/
		void (*state_change)(struct sock *sk);
		void (*data_ready)(struct sock *sk,int bytes);
		void (*write_space)(struct sock *sk);
		void (*error_report)(struct sock *sk);
		int (*backlog_rcv) (struct sock *sk, struct sk_buff *skb);
		void (*destruct)(struct sock *sk);
	};


	struct inet_opt
	{
		int ttl;                    // IP的TTL设置
		int tos;                    // IP的TOS设置
		unsigned cmsg_flags;        // 该标志用来决定是否向应用层打印相关信息，包括如下可能的值
		#define IP_CMSG_PKTINFO 1
		#define IP_CMSG_TTL 2
		#define IP_CMSG_TOS 4
		#define IP_CMSG_RECVOPTS 8
		#define IP_CMSG_RETOPTS 16
		struct ip_options *opt;     // IP选项，包括安全和处理限制、记录路径、时间戳、宽松的源站选路、严格的源站选路
		unsigned char hdrincl;      // 用于RAW
		__u8 mc_ttl;                // 多播TTL
		__u8 mc_loop;               // 多播回环
		unsigned recverr : 1,       // 是否允许传递扩展的可靠的错误信息.
		freebind : 1;               // 是否允许socket被绑定
		__u16 id;                   // 用于禁止分片的IP包的ID计数
		__u8 pmtudisc;              // 路径MTU发现
		int mc_index;               // 多播设备索引
		__u32 mc_addr;              // 自己的多播地址
		struct ip_mc_socklist *mc_list; // 多播组
	};

	struct tcp_opt {
		int tcp_header_len;         // tcp首部长度（包括选项）
		__u32 pred_flags; /* 首部预测标志，在syn_rcv、syn_sent、更新窗口或其他恰当的时候，设置pred_flags（主要
							是创建出不符合快速路径的条件，一般值为0x??10 << 16 + snd_wnd）?所对应的值不确定，
							在连接完毕之后，根据pred_flags以及其他因素来确定是否走快速路径。*/
	
		__u32 rcv_nxt;              // 期望接受到的下一个tcp包的seq
		__u32 snd_nxt;              // 要发送的下一个tcp包的seq
		__u32 snd_una;              // 表示最近一个尚未确认的但是已经发送过的报文的seq
		__u32 snd_sml;              // 最近发送的小包的最后一个字节数，主要用于Nagle算法
		__u32 rcv_tstamp;           // 最近收到的ACK的时间，用于保活
		__u32 lsndtime;             // 最近发送的数据包的时间，用于窗口restart

		/* 经受时延的确认的控制 */
		struct {
			__u8 pending;           /* 正处于ACK延时状态，包括如下几种状态 ACK is pending */
			enum tcp_ack_state_t
			{
				TCP_ACK_SCHED = 1,
				TCP_ACK_TIMER = 2,
				TCP_ACK_PUSHED= 4
			};
			__u8 quick;            /* 快速恢复算法时，用于决定是否需要重传的收到的重复ACK的最大数目 Scheduled number of quick acks */
			__u8 pingpong;         /* 当前该TCP会话处于交互状态（非延时ACK状态）The session is interactive */
			__u8 blocked;          /* 当前socket被锁住了，这时候延时的ACK不再等待，而是立即发送 Delayed ACK was blocked by socket lock*/]
			/*Adaptive Time-Out (ATO) is the time that must elapse before an acknowledgment is considered lost. RFC 2637*/
			__u32 ato;             /* 软件时钟的预测嘀嗒数目 Predicted tick of soft clock */
			unsigned long timeout; /* 当前延时确认的定时器时间 Currently scheduled timeout */
			__u32 lrcvtime;        /* 最后收到的数据报的时间戳 timestamp of last received data packet*/
			__u16 last_seg_size;   /* 最后收到的数据报的大小 Size of last incoming segment */

			/*
			1. tp->advmss：The MSS advertised by the host. This is initialised in the function tcp_advertise_mss, from the routing table's destination cache(dst->advmss).
	Given that the cached entry is calculated from the MTU (maximum transfer unit) of the next hop, this will have a value of 1460 over Ethernet.

			2. tp->ack.rcv_mss：A lower-bound estimate of the peer's MSS. This is initiated in tcp_initialize_rcv mss, and updated whenever a segment is received by
	tcp measure rcv mss.

			3. tp->mss_cache：The current effective sending MSS, which is calculated in the function tcp_sync_mss. When the socket is created, it is initialised to 536 by
	tcp_v4_init_sock. Note that these are the only functions that alter the value of tp->mss cache.

			4. tp->mss clamp：An upper-bound value of the MSS of the connection. This is negotiated at connect(), such that it is the minimum of the MSS values advertised
	by the two hosts.We will never see a segment larger than this.
	*/
			__u16 rcv_mss;    /* 属于点到点的mss，用于延时确认 MSS used for delayed ACK decisions */
		} ack;

		__u16 mss_cache;      // 当前提供的有效mss， /* Cached effective mss, not including SACKS */
		__u16 mss_clamp;      // 最大mss，连接建立时协商的mss或者用户通过ioctl指定的mss的两者之中最大值
		/* Maximal mss, negotiated at connection setup */
		__u16 advmss;         /* MTU包括路径MTU，这里的advmss是本机告知周围网关的我自身的mss */

		/* 用于直接拷贝给应用层的数据，当用户正在读取该套接字时, TCP包将被排入套接字的预备队列(tcp_prequeue ())，将其
		传递到该用户线程上下文中进行处理. */
		struct {
			struct sk_buff_head prequeue; // 当前预备队列
			struct task_struct *task;     // 当前线程
			struct iovec *iov;            // 用户空间接受数据的地址
			int memory;                   // 当前预备队列中的包总字节数目
			int len;                      // 用户进程从预备队列中读取的数据字节数
		} ucopy;

		__u32 snd_wl1;        // 收到对方返回的skb，记下该包的seq号，用于判断窗口是否需要更新 /* Sequence for window update */
		__u32 snd_wnd;        // 记录对方提供的窗口大小 /* The window we expect to receive */
		__u32 max_window;     // 对方曾经提供的最大窗口 /* Maximal window ever seen from peer */
		__u32 pmtu_cookie;    // 将发送mss和当前的pmtu/exthdr设置同步 /* Last pmtu seen by socket */
		__u16 ext_header_len; // 网络层协议选项长度 /* Network protocol overhead (IP/IPv6 options) */
		__u8 ca_state;        // 快速重传状态机 /* State of fast-retransmit machine */
		enum tcp_ca_state
		{
			TCP_CA_Open = 0,
			TCP_CA_Disorder = 1,
			TCP_CA_CWR = 2,
			TCP_CA_Recovery = 3,
			TCP_CA_Loss = 4
		};
		/* RFC 1122指出，TCP实现必须包括Karn和Jacobson实现计算重传超时（retransmission timeout：RTO）的算法 */
		__u8 retransmits; // 某个还没有被确认的发送TCP包重传的次数 /* Number of unrecovered RTO timeouts. */

		/* 当收到下面数量的重复ack时，快速重传开始，而无需等待重传定时器超时 */
		__u8 reordering; /* Packet reordering metric. */

		/* 当我们发出一个tcp包之后，并不立刻释放掉该包，而是等待其对应的ack到来，如果这时候ack来了，那么我们将从
		write_queue队列中释放掉该包，同时将该事件的标志记录在tp->queue_shrunk中，如果原来进程由于write_queue中没
		有足够的空间继续发送数据而休眠的话，那么此时将会唤醒其对应的sock，从而进程可以继续发送数据 */
		__u8 queue_shrunk; /* Write queue has been shrunk recently.*/
		__u8 defer_accept; // 请参考附录1 /* User waits for some data after accept() */

		/* 往返时间测量 RTT，有关RTT的侧量这里不再详细讨论measurement ：Round-Trip Time (RTT) is the estimated round-trip time for an Acknowledgment to be received for a
	given transmitted packet. When the network link is a local network, this delay will be minimal (if not zero). When the network link is
	the Internet, this delay could be substantial and vary widely. RTT is adaptive. */
		__u8 backoff;         /* backoff */
		__u32 srtt;           /* smothed round trip time << 3 */
		__u32 mdev;           /* medium deviation */
		__u32 mdev_max;       /* maximal mdev for the last rtt period */
		__u32 rttvar;         /* smoothed mdev_max */
		__u32 rtt_seq;        /* sequence number to update rttvar */
		__u32 rto;            /* 重传超时时间 retransmit timeout */

		__u32 packets_out;    /* 已经发出去的数目 Packets which are "in flight" */
		__u32 left_out;       /* 发出去已经被确认的数目 Packets which leaved network */
		__u32 retrans_out;    /* 重传的发出去的包数目 Retransmitted packets out */

		// 慢启动和拥塞控制 Slow start and congestion control (see also Nagle, and Karn & Partridge)
		__u32 snd_ssthresh;   // 拥塞控制时的慢启动门限 /* Slow start size threshold */
		__u32 snd_cwnd;       // 当前采用的拥塞窗口 /* Sending congestion window */
		__u16 snd_cwnd_cnt;   // 线形增加的拥塞窗口计数器 /* Linear increase counter */
		__u16 snd_cwnd_clamp; // 拥塞窗口的最大值（一般为对方通告的窗口大小） /* Do not allow snd_cwnd to grow above this */
		__u32 snd_cwnd_used;  // 慢启动，每发出去一个包，snd_cwnd_used++
		__u32 snd_cwnd_stamp; // 该参数可以保证在重传模式下不会改变拥塞窗口的大小 */

		/* 重传定时器和延时确认定时器 Two commonly used timers in both sender and receiver paths. */
		unsigned long timeout;// 用于重传
		struct timer_list retransmit_timer;     /* Resend (no ack) */
		struct timer_list delack_timer;         /* Ack delay */
		struct sk_buff_head out_of_order_queue; // 乱序的TCP报都存放在该队列中 /* Out of order segments go here */

		struct tcp_func *af_specific;           // ipv4/ipv6 相关特定处理函数 /* Operations which are AF_INET{4,6} specific */
		struct tcp_func ipv4_specific = {
			ip_queue_xmit,
			tcp_v4_send_check,
			tcp_v4_rebuild_header,
			tcp_v4_conn_request,
			tcp_v4_syn_recv_sock,
			tcp_v4_remember_stamp,
			sizeof(struct iphdr),

			ip_setsockopt,
			ip_getsockopt,
			v4_addr2sockaddr,
			sizeof(struct sockaddr_in)
		};
		struct sk_buff *send_head;  // 最先要发送的TCP报文 /* Front of stuff to transmit */
		struct page *sndmsg_page;   // sendmsg所使用的缓冲内存页面 /* Cached page for sendmsg */
		u32 sndmsg_off;             // sendmsg所使用的缓冲偏移 /* Cached offset for sendmsg */

		__u32 rcv_wnd;              // 当前接受窗口 /* Current receiver window */
		__u32 rcv_wup;              // 对方窗口最后一次更新时的rcv_nxt /* rcv_nxt on last window update sent */
		__u32 write_seq;            // tcp发送总数据字节量+1 /* Tail(+1) of data held in tcp send buffer */
		__u32 pushed_seq;           // 上次发送带PSH标志的TCP包的seq /* Last pushed seq, required to talk to windows */
		__u32 copied_seq;           // 尚未读取的数据第一个字节位置 /* Head of yet unread data */

		// Options received (usually on last packet, some only on SYN packets).
		char tstamp_ok,        /* syn包上的时间戳 TIMESTAMP seen on SYN packet */
		wscale_ok,             /* SACK选项处理Kind=5不再详细叙说 Wscale seen on SYN packet */
		sack_ok;               /* SACK选项处理Kind=5不再详细叙说 SACK seen on SYN packet */
		char saw_tstamp;       /* 最后一个TCP包的时间戳 Saw TIMESTAMP on last packet */
		__u8 snd_wscale;       /* 接受窗口扩大因子 Window scaling received from sender */
		__u8 rcv_wscale;       /* 发送窗口扩大因子 Window scaling to send to receiver */
		__u8 nonagle;          /* 是否允许Nagle算法 Disable Nagle algorithm? */
		__u8 keepalive_probes; /* 保活探测的数量 num of allowed keep alive probes */

		/* PAWS：防止回绕的序号，不再详细叙说 PAWS/RTTM data */
		__u32 rcv_tsval;       /* Time stamp value */
		__u32 rcv_tsecr;       /* Time stamp echo reply */
		__u32 ts_recent;       /* Time stamp to echo next */
		long ts_recent_stamp;  /* Time we stored ts_recent (for aging) */

		/* SACK选项处理Kind=5不再详细叙说 SACKs data1 */
		__u16 user_mss;        /* 用户通过ioctl指定的mssmss requested by user in ioctl */
		__u8 dsack;            /* D-SACK is scheduled */
		__u8 eff_sacks;        /* Size of SACK array to send with next packet */
		struct tcp_sack_block duplicate_sack[1]; /* D-SACK block */
		struct tcp_sack_block selective_acks[4]; /* The SACKS themselves*/

		/* 通告窗口(advertised window，tp->tcv_wnd)，window_clamp是最大的通告窗口，说白了就是
		应用程序的缓冲区真实大小。rcv_ssthresh是更为严格的window_clamp，主要用于慢启动期间
		预测连接的行为 */
		__u32 window_clamp;   /* Maximal window to advertise */
		__u32 rcv_ssthresh;   /* Current window clamp */

		__u8 probes_out;      /* 用于零窗口探测 unanswered 0 window probes */
		__u8 num_sacks;       /* Number of SACK blocks */

		__u8 syn_retries;     /* syn重试次数 num of allowed syn retries */
		__u8 ecn_flags;       /* 显式拥塞通知状态位，不再详叙 ECN status bits. */
		__u16 prior_ssthresh; /* 在经过重传后恢复时的ssthresh保存值 ssthresh saved at recovery start */

		/* SACK选项处理Kind=5不再详细叙说 SACKs data2 */
		__u32 lost_out;       /* Lost packets */
		__u32 sacked_out;     /* SACK'd packets */
		__u32 fackets_out;    /* FACK'd packets */
		__u32 high_seq;       /* snd_nxt at onset of congestion */

		__u32 retrans_stamp;  // 上次重传的时间，其也会记住第一个syn的时间戳
		__u32 undo_marker;    /* 开始跟踪重传的标示符 tracking retrans started here. */
		int undo_retrans;     /* 用于Undo冗余的重传 number of undoable retransmissions. */
		__u32 urg_seq;        /* 紧急指针的seq Seq of received urgent pointer */
		__u16 urg_data;       /* 紧急指针的相关控制标志保存 Saved octet of OOB data and control flags */
		__u8 pending;         /* 确定定时器的事件 Scheduled timer event，包括如下四种情况 */
		#define TCP_TIME_RETRANS 1  /* Retransmit timer */
		#define TCP_TIME_DACK 2     /* Delayed ack timer */
		#define TCP_TIME_PROBE0 3   /* Zero window probe timer */
		#define TCP_TIME_KEEPOPEN 4 /* Keepalive timer */

		__u8 urg_mode;        /* 是否处于紧急模式 In urgent mode */
		__u32 snd_up;         /* 紧急指针位置 Urgent pointer */

		/* The syn_wait_lock is necessary only to avoid tcp_get_info having to grab the main lock sock while browsing the listening hash
		 * (otherwise it's deadlock prone). This lock is acquired in read mode only from tcp_get_info() and it's acquired in write mode _only_ from
		 * code that is actively changing the syn_wait_queue. All readers that are holding the master sock lock don't need to grab this lock in read
		 * mode too as the syn_wait_queue writes are always protected from the main sock lock.
		 */
		rwlock_t syn_wait_lock;
		struct tcp_listen_opt *listen_opt;

		/* 服务器段listening socket的已经建立的子socket FIFO队列 FIFO of established children */
		struct open_request *accept_queue;
		struct open_request *accept_queue_tail;

		int write_pending;             /* 是否有对socket的写请求 A write to socket waits to start. */
		unsigned int keepalive_time;   /* 保活定时器启动的时间阀值 time before keep alive takes place */
		unsigned int keepalive_intvl;  /* 保活探测时间间隔 time interval between keep alive probes */
		int linger2;                   // lingertime一起，指明了close()后保留的时间
		int frto_counter;              /* 开始重传后的新的ack数目 Number of new acks after RTO */
		__u32 frto_highmark;           /* 重传发生时的要发送的下一个tcp包的seq snd_nxt when RTO occurred */

		unsigned long last_synq_overflow; // 用于syn_cookie处理
	};
```
/*
附录1：
The first option we'll consider is TCP_DEFER_ACCEPT. (This is what it's called in Linux; other OSs offer the same option but use different names.)
To understand the idea of the TCP_DEFER_ACCEPT option, it is necessary to picture a typical process of the HTTP client-server interaction. Consider
how the TCP establishes a connection with the goal of transferring data. On a network, information travels in discrete units called IP packets (or IP
datagrams). A packet always has a header that carries service information, used for internal protocol handling, and it may also carry payload data. A
typical example of service information is a set of so-called flags, which mark the packets as having special meaning to a TCP/IP stack, such as
acknowledgement of successful packet receiving. Often, it's possible to carry payload in the “marked” packet, but sometimes, internal logic forces a
TCP/IP stack to send out packets with just a header. These packets often introduce unwanted delays and increased overhead and result in overall
performance degradation.

The server has now created a socket and is waiting for a connection. The connection procedure in TCP/IP is a so-called “three-way handshake.” First,
a client sends a TCP packet with a SYN flag set and no payload (a SYN packet). The server replies by sending a packet with SYN/ACK flags set (a
SYN/ACK packet) to acknowledge receipt of the initial packet. The client then sends an ACK packet to acknowledge receipt of the second packet and to
finalize the connection procedure. After receiving the SYN/ACK, the packet server wakes up a receiver process while waiting for data. When the three-way
handshake is completed, the client starts to send “useful” data to be transferred to the server. Usually, an HTTP request is quite small and fits into a single
packet. But in this case, at least four packets will be sent in both directions, adding considerable delay times. Note also that the receiver has already been
waiting for the information—since before the data was ever sent.

To alleviate these problems, Linux (along with some other OSs) includes a TCP_DEFER_ACCEPT option in its TCP implementation. Set on a server-side
listening socket, it instructs the kernel not to wait for the final ACK packet and not to initiate the process until the first packet of real data has arrived. After
sending the SYN/ACK, the server will then wait for a data packet from a client. Now, only three packets will be sent over the network, and the connection
establishment delay will be significantly reduced, which is typical for HTTP.

This feature, called an “accept filter” , is used in different ways, although in all cases, the effect is the same as TCP_DEFER_ACCEPT—the server
will not wait for the final ACK packet, waiting only for a packet carrying a payload. More information about this option and its significance for a high-performance
Web server is available in the Apache documentation.
*/
