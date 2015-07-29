---
layout: post
title: "HAProxy 研究笔记 -- HTTP请求处理-1-接收"
date: 2015-07-29 16:03:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3795082.html

这里继续分析 http req 的处理。当前分析的代码为 1.5-dev17。

#### 1. 初始化 session 数据处理相关的设置

建连的处理基本上就是 _do_poll ->listener_accept ->session_accept ->fronend_accept()

其中 session_accept() 会设置新建 fd 的 io handler

```
	/* Add the various callbacks. Right now the transport layer is present
	 * but not initialized. Also note we need to be careful as the stream
	 * int is not initialized yet.
	 */
	conn_prepare(s->si[0].conn, &sess_conn_cb, l->proto, l->xprt, s);

    fdtab[cfd].owner = s->si[0].conn; /*fd 对应的 owner 为 connection 结构*/
	fdtab[cfd].iocb = conn_fd_handler;
	conn_data_want_recv(s->si[0].conn);
	if (conn_xprt_init(s->si[0].conn) < 0)
		goto out_free_task;
```

IPv4 http 对应的 listener 的 xprt 和proto 分别被初始化为

```
	l->xprt = &raw_sock;
	l->proto = &proto_tcpv4;
```

conn_prepare() 就是将相关数据收发以及连接处理的函数都赋值到 connection 结构体上：

```
	/* Assigns a connection with the appropriate data, ctrl, transport layers, and owner. */
	static inline void conn_assign(struct connection *conn, const struct data_cb *data,
		                           const struct protocol *ctrl, const struct xprt_ops *xprt,
		                           void *owner)
	{
		conn->data = data;
		conn->ctrl = ctrl;
		conn->xprt = xprt;
		conn->owner = owner;
	}

	/* prepares a connection with the appropriate data, ctrl, transport layers, and
	 * owner. The transport state and context are set to 0.
	 */
	static inline void conn_prepare(struct connection *conn, const struct data_cb *data,
		                            const struct protocol *ctrl, const struct xprt_ops *xprt,
		                            void *owner)
	{
		conn_assign(conn, data, ctrl, xprt, owner);
		conn->xprt_st = 0;
		conn->xprt_ctx = NULL;
	}
```

经过初始化， session client 端的 connection 结构体初始化完成：

```
    conn->data 指向 sess_conn_cb。 后面调用 session_complete() 会被再次赋值
    conn->ctrl 指向 l->proto, IPv4 下为 proto_tcpv4
    conn->xprt 执向 l->xprt, 不启用 SSL 时为 raw_sock，启用 SSL 时为 ssl_sock
    conn->owner 指向 session
```

接着调用 session_complete 完成建立一个 session 所需要的最后的初始化工作，其中 包含调用 frontend_accept，并将当前 session 对应的 task 放入runqueue 中以待下 次执行：

```
    ...
   	si_takeover_conn(&s->si[0], l->proto, l->xprt);
   	...
   	t->process = l->handler;
   	...
	if (p->accept && (ret = p->accept(s)) <= 0) {
		/* Either we had an unrecoverable error (<0) or work is
		 * finished (=0, eg: monitoring), in both situations,
		 * we can release everything and close.
		 */
		goto out_free_rep_buf;
	}
	...
	task_wakeup(t, TASK_WOKEN_INIT);
```

其中 si_takeover_conn 完成为 si 分配连接的处理函数，实现如下：

```
	static inline void si_takeover_conn(struct stream_interface *si, const struct protocol *ctrl, const struct xprt_ops *xprt)
	{
		si->ops = &si_conn_ops;
		conn_assign(si->conn, &si_conn_cb, ctrl, xprt, si);
	}

	si_conn_cb 的定义如下：

	struct data_cb si_conn_cb = {
		.recv    = si_conn_recv_cb,
		.send    = si_conn_send_cb,
		.wake    = si_conn_wake_cb,
	};
```

因此，si->conn->data 指向了 si_conn_cb。这个结构用在随后的 recv/send 中。

此外，session 所对应的任务 task 在 session_complete 的最后通过调用 task_wakeup() 是在随后的循环中被执行。task 的处理函数初始化为 l->handler 即 process_session().

至此，一个新建 session 的 client fd 的 io 处理函数 conn_fd_handler() 及 session 的处理函数 process_session() 都已经正确初始化好了。

以后基本上就是这两个函数分别负责数据的读取，以及业务的处理。

#### 2. 接收 client 发送的请求数据

epoll 中考虑的新建连接通常会尽可能快的传输数据，因此对于新建的 fd，通常会尽快的 执行 io handler，即调用 conn_fd_handler

是在 ev_epoll.c 中的 _do_poll() 中进行：

```
	gettimeofday(&before_poll, NULL);
	status = epoll_wait(epoll_fd, epoll_events, global.tune.maxpollevents, wait_time);
	tv_update_date(wait_time, status);
	measure_idle();

	/* process polled events */

	for (count = 0; count < status; count++) {
		unsigned int n;
		unsigned int e = epoll_events[count].events;
		fd = epoll_events[count].data.fd;
		...
		/* Save number of updates to detect creation of new FDs. */
		old_updt = fd_nbupdt;
		fdtab[fd].iocb(fd);
		...
		for (new_updt = fd_nbupdt; new_updt > old_updt; new_updt--) {
			fd = fd_updt[new_updt - 1];
		    ...
			if (fdtab[fd].ev && fdtab[fd].iocb && fdtab[fd].owner)
				fdtab[fd].iocb(fd);
			...
        }
```

上面代码中第一处执行 iocb() 的是由 epoll_wait() 返回的 fd 触发的。而第二次的 iocb() 则就是在前面 iocb 的执行过程中新建的 fd，为了提高效率，则直接调用该 fd 的 iocb()，也 就是 conn_fd_handler() 函数。

```
	int conn_fd_handler(int fd) 
	{
		struct connection *conn = fdtab[fd].owner;
		...
		if ((fdtab[fd].ev & (FD_POLL_IN | FD_POLL_HUP | FD_POLL_ERR)) &&
			conn->xprt &&
			!(conn->flags & (CO_FL_WAIT_RD|CO_FL_WAIT_ROOM|CO_FL_ERROR|CO_FL_HANDSHAKE))) {
			/* force detection of a flag change : it's impossible to have both
			 * CONNECTED and WAIT_CONN so we're certain to trigger a change.
			 */
			flags = CO_FL_WAIT_L4_CONN | CO_FL_CONNECTED;
			conn->data->recv(conn);
		}
		...
	}
```

根据的 session_complete 的初始化，上面代码 conn->data->recv 指向 si_conn_recv_cb()。 该函数就是 haproxy 中负责接收数据的入口函数。相同的，si_conn_send_cb() 就是 haproxy 中负责发送数据的入口函数。

si_conn_recv_cb() 函数简单介绍如下：

```
	if (conn->xprt->rcv_pipe &&
	    chn->to_forward >= MIN_SPLICE_FORWARD && chn->flags & CF_KERN_SPLICING) {
	    ...
        ret = conn->xprt->rcv_pipe(conn, chn->pipe, chn->to_forward);
        ...
    }
    ...
	while (!chn->pipe && !(conn->flags & (CO_FL_ERROR | CO_FL_SOCK_RD_SH | CO_FL_DATA_RD_SH | CO_FL_WAIT_RD | CO_FL_WAIT_ROOM | CO_FL_HANDSHAKE))) {
    
        ...
        ret = conn->xprt->rcv_buf(conn, chn->buf, max);
        ...
    }
```

该函数主要根据数据的接收情况，选择调用 xprt 的 rcv_pipe 还是 rcv_buf. 前面已经 分析过， conn->xprt 指向了 listner 的 xprt，不启用 SSL 就是 raw_sock 数据结构

因此，数据的接收最终是通过调用 raw_sock 的 raw_sock_to_pipe 或/和 raw_sock_to_buf 完成的。 

