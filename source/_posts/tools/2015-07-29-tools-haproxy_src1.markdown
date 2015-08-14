---
layout: post
title: "HAProxy 研究笔记 -- TCP 连接处理流程"
date: 2015-07-29 15:49:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3771148.html

本文基于 HAProxy 1.5-dev7 版本。
```
	目录
	1. 关键数据结构 session
	2. 相关初始化
		2.1. 初始化处理 TCP 连接的方法
		2.2. 初始化 listener
		2.3. 绑定所有已注册协议上的 listeners
		2.4. 启用所有已注册协议上的 listeners
	3. TCP 连接的处理流程
		3.1. 接受新建连接
		3.2. TCP 连接上的接收事件
		3.3. TCP 连接上的发送事件
		3.4. http 请求的处理
```

#### 1. 关键数据结构 session

haproxy 负责处理请求的核心数据结构是 struct session，本文不对该数据结构进行分析。

从业务的处理的角度，简单介绍一下对 session 的理解：

```
	haproxy 每接收到 client 的一个连接，便会创建一个 session 结构，该结构一直伴随着连接的处理，直至连接被关闭，session 才会被释放
	haproxy 其他的数据结构，大多会通过引用的方式和 session 进行关联
	一个业务 session 上会存在两个 TCP 连接，一个是 client 到 haproxy，一个是 haproxy 到后端 server。
```

此外，一个 session，通常还要对应一个 task，haproxy 最终用来做调度的是通过 task。

#### 2. 相关初始化

在 haproxy 正式处理请求之前，会有一系列初始化动作。这里介绍和请求处理相关的一些初始化。

##### 2.1. 初始化处理 TCP 连接的方法

初始化处理 TCP 协议的相关数据结构，主要是和 socket 相关的方法的声明。详细见下面 proto_tcpv4 (proto_tcp.c)的初始化：
```
	static struct protocol proto_tcpv4 = {
		.name = "tcpv4",
		.sock_domain = AF_INET,
		.sock_type = SOCK_STREAM,
		.sock_prot = IPPROTO_TCP,
		.sock_family = AF_INET,
		.sock_addrlen = sizeof(struct sockaddr_in),
		.l3_addrlen = 32/8,
		.accept = &stream_sock_accept,
		.read = &stream_sock_read,
		.write = &stream_sock_write,
		.bind = tcp_bind_listener,
		.bind_all = tcp_bind_listeners,
		.unbind_all = unbind_all_listeners,
		.enable_all = enable_all_listeners,
		.listeners = LIST_HEAD_INIT(proto_tcpv4.listeners),
		.nb_listeners = 0,
	};
```

##### 2.2. 初始化 listener

listener，顾名思义，就是用于负责处理监听相关的逻辑。

在 haproxy 解析 bind 配置的时候赋值给 listener 的 proto 成员。函数调用流程如下：
```
	cfgparse.c
		-> cfg_parse_listen
			-> str2listener
				-> tcpv4_add_listener
					-> listener->proto = &proto_tcpv4;
```

由于这里初始化的是 listener 处理 socket 的一些方法。可以推断， haproxy 接收 client 新建连接的入口函数应该是 protocol 结构体中的 accpet 方法。对于tcpv4 来说，就是 stream_sock_accept() 函数。该函数到 1.5-dev19 中改名为 listener_accept()。这是后话，暂且不表。

listener 的其他初始化

```
	cfgparse.c
		-> check_config_validity
			-> listener->accept = session_accept;
	listener->frontend = curproxy; (解析 frontend 时，会执行赋值： curproxy->accept = frontend_accept）
	listener->handler = process_session;
```

整个 haproxy 配置文件解析完毕，listener 也已初始化完毕。可以简单梳理一下几个 accept 方法的设计逻辑：

```
	stream_sock_accept(): 负责接收新建 TCP 连接，并触发 listener 自己的 accept 方法 session_accept()
	session_accept(): 负责创建 session，并作 session 成员的初步初始化，并调用 frontend 的 accept 方法 front_accetp()
	frontend_accept(): 该函数主要负责 session 前端的 TCP 连接的初始化，包括 socket 设置，log 设置，以及 session 部分成员的初始化
```

下文分析 TCP 新建连接处理过程，基本上就是这三个函数的分析。

##### 2.3. 绑定所有已注册协议上的 listeners

```
	haproxy.c 
		-> protocol_bind_all 
			-> all registered protocol bind_all
				-> tcp_bind_listeners (TCP)
					-> tcp_bind_listener 
						-> [ fdtab[fd].cb[DIR_RD].f = listener->proto->accept ]
```

该函数指针指向 proto_tcpv4 结构体的 accept 成员，即函数 stream_sock_accept

##### 2.4. 启用所有已注册协议上的 listeners

把所有 listeners 的 fd 加到 polling lists 中 haproxy.c -> protocol_enable_all -> all registered protocol enable_all -> enable_all_listeners (TCP) -> enable_listener 函数会将处于 LI_LISTEN 的 listener 的状态修改为 LI_READY，并调用 cur poller 的 set 方法， 比如使用 sepoll，就会调用 __fd_set

#### 3. TCP 连接的处理流程

##### 3.1. 接受新建连接

前面几个方面的分析，主要是为了搞清楚当请求到来时，处理过程中实际的函数调用关系。以下分析 TCP 建连过程。

```
	haproxy.c 
		-> run_poll_loop 
			-> cur_poller.poll 
				-> __do_poll (如果配置使用的是 sepoll，则调用 ev_sepoll.c 中的 poll 方法) 
					-> fdtab[fd].cb[DIR_RD].f(fd) (TCP 协议的该函数指针指向 stream_sock_accept )
						-> stream_sock_accept
							-> 按照 global.tune.maxaccept 的设置尽量可能多执行系统调用 accept，然后再调用 l->accept()，即 listener 的 accept 方法 session_accept
								-> session_accept
```

session_accept 主要完成以下功能

```
	调用 pool_alloc2 分配一个 session 结构
	调用 task_new 分配一个新任务
	将新分配的 session 加入全局 sessions 链表中
	session 和 task 的初始化，若干重要成员的初始化如下
		t->process = l->handler： 即 t->process 指向 process_session
		t->context = s： 任务的上下文指向 session
		s->listener = l： session 的 listener 成员指向当前的 listener
		s->si[] 的初始化，记录 accept 系统调用返回的 cfd 等
		初始化 s->txn
		为 s->req 和 s->rep 分别分配内存，并作对应的初始化
			s->req = pool_alloc2(pool2_buffer)
			s->rep = pool_alloc2(pool2_buffer)
			从代码上来看，应该是各自独立分配 tune.bufsize + sizeof struct buffer 大小的内存
		新建连接 cfd 的一些初始化
			cfd 设置为非阻塞
			将 cfd 加入 fdtab[] 中，并注册新建连接 cfg 的 read 和 write 的方法
			fdtab[cfd].cb[DIR_RD].f = l->proto->read，设置 cfd 的 read 的函数 l->proto->read，对应 TCP 为 stream_sock_read，读缓存指向 s->req，
			fdtab[cfd].cb[DIR_WR].f = l->proto->write，设置 cfd 的 write 函数 l->proto->write，对应 TCP 为 stream_sock_write，写缓冲指向 s->rep
	p->accept 执行 proxy 的 accept 方法即 frontend_accept
		设置 session 结构体的 log 成员
		根据配置的情况，分别设置新建连接套接字的选项，包括 TCP_NODELAY/KEEPALIVE/LINGER/SNDBUF/RCVBUF 等等
		如果 mode 是 http 的话，将 session 的 txn 成员做相关的设置和初始化
```

##### 3.2. TCP 连接上的接收事件

```
	haproxy.c 
		-> run_poll_loop 
			-> cur_poller.poll 
				-> __do_poll (如果配置使用的是 sepoll，则调用 ev_sepoll.c 中的 poll 方法) 
					-> fdtab[fd].cb[DIR_RD].f(fd) (该函数在建连阶段被初始化为四层协议的 read 方法，对于 TCP 协议，为 stream_sock_read )
						-> stream_sock_read
```

stream_sock_read 主要完成以下功能

  找到当前连接的读缓冲，即当前 session 的 req buffer：
```
	struct buffer *b = si->ib
```

```
	根据配置，调用 splice 或者 recv 读取套接字上的数据，并填充到读缓冲中，即填充到从 b->r（初始位置应该就是 b->data）开始的内存中
	如果读取到 0 字节，则意味着接收到对端的关闭请求，调用 stream_sock_shutr 进行处理
		读缓冲标记 si->ib->flags 的 BF_SHUTR 置位，清除当前 fd 的 epoll 读事件，不再从该 fd 读取
		如果写缓冲 si->ob->flags 的 BF_SHUTW 已经置位，说明应该是由本地首先发起的关闭连接动作
			将 fd 从 fdset[] 中清除，从 epoll 中移除 fd，执行系统调用 close(fd)， fd.state 置位 FD_STCLOSE
			stream interface 的状态修改 si->state = SI_ST_DIS
	唤醒任务 task_wakeup，把当前任务加入到 run queue 中。随后检测 runnable tasks 时，就会处理该任务

##### 3.3. TCP 连接上的发送事件

```
	haproxy.c 
		-> run_poll_loop 
			-> cur_poller.poll 
				-> __do_poll (如果配置使用的是 sepoll，则调用 ev_sepoll.c 中的 poll 方法) 
					-> fdtab[fd].cb[DIR_WR].f(fd) (该函数在建连阶段被初始化为四层协议的 write 方法，对于 TCP 协议，为 stream_sock_write )
						-> stream_sock_write
```

stream_sock_write主要完成以下功能

  找到当前连接的写缓冲，即当前 session 的 rep buffer：
```
	struct buffer *b = si->ob
```

```
	将待发送的数据调用 send 系统调用发送出去  
	或者数据已经发送完毕，需要发送关闭连接的动作 stream_sock_shutw-> 系统调用 shutdown  
	唤醒任务 task_wakeup，把当前任务加入到 run queue 中。随后检测 runnable tasks 时，就会处理该任务  
```

##### 3.4. http 请求的处理

```
	haproxy.c 
		-> run_poll_loop 
			-> process_runnable_tasks，查找当前待处理的任务所有 tasks， 然后调用 task->process（大多时候就是 process_session） 进行处理
				-> process_session
```

process_session 主要完成以下功能
```
	处理连接需要关闭的情形，分支 resync_stream_interface
	处理请求，分支 resync_request (read event)
		根据 s->req->analysers 的标记位，调用不同的 analyser 进行处理请求
		ana_list & AN_REQ_WAIT_HTTP： http_wait_for_request
		ana_list & AN_REQ_HTTP_PROCESS_FE： http_process_req_common
		ana_list & AN_REQ_SWITCHING_RULES：process_switching_rules
	处理应答，分支 resync_response (write event)
		根据 s->rep->analysers 的标记位，调用不同的 analyser 进行处理请求
		ana_list & AN_RES_WAIT_HTTP： http_wait_for_response
		ana_list & AN_RES_HTTP_PROCESS_BE：http_process_res_common
	处理 forward buffer 的相关动作
	关闭 req 和 rep 的 buffer，调用 pool2_free 释放 session 及其申请的相关内存，包括读写缓冲 (read 0 bytes)
		pool_free2(pool2_buffer, s->req);
		pool_free2(pool2_buffer, s->rep);
		pool_free2(pool2_session, s);
	task 从运行任务队列中清除，调用 pool2_free 释放 task 申请的内存： task_delete(); task_free();
```

本文简单分析了 TCP 连接的处理过程，不侧重细节分析，而且缺少后端 server 的选择以及建连等，重在希望展示出一个 haproxy 处理 TCP 连接的框架。

