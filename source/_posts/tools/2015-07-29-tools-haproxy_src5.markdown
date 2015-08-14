---
layout: post
title: "HAProxy 研究笔记 -- HTTP请求处理-2-解析"
date: 2015-07-29 16:07:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3819702.html

 本文继续分析 1.5-dev17 中接收到 client 数据之后的处理。

haproxy-1.5-dev17 中接收 client 发送的请求数据流程见文档： HTTP请求处理-1-接收

#### 1. haproxy 主循环的处理流程

主循环处理流程见文档 主循环简介

请求数据的解析工作在主循环 process_runnable_tasks() 中执行。

#### 2. 执行 run queue 中的任务

 HTTP请求处理-1-接收 中分析到 session 建立之后，一来会将 session 的 task 放入 runqueue，该 task 会 在下一轮遍历可以运行的 task 中出现，并得到执行。二是立即调用 conn_fd_handler 去 接收 client 发送的数据。

数据接收流程结束后（注意，这并不代表接收到了完整的 client 请求，因为也可能暂时 读取不到 client 的数据退出接收），haproxy 调度执行下一轮循环，调用 process_runnable_tasks() 处理所有在 runqueue 中的 task：

```
	void process_runnable_tasks(int *next)
	{
		...
		eb = eb32_lookup_ge(&rqueue, rqueue_ticks - TIMER_LOOK_BACK);
		while (max_processed--) {
			...
			t = eb32_entry(eb, struct task, rq);
			eb = eb32_next(eb);
			__task_unlink_rq(t);

			t->state |= TASK_RUNNING;
			/* This is an optimisation to help the processor's branch
			 * predictor take this most common call.
			 */
			t->calls++;
			if (likely(t->process == process_session))
				t = process_session(t);
			else
				t = t->process(t);
			...
		}
	}
```

大多数情况下，task 的 proecss 都指向 process_session() 函数。该函数就是负责解析 已接收到的数据，选择 backend server，以及 session 状态的变化等等。

#### 3. session 的处理：process_session()

下面介绍 process_session() 函数的实现。该函数代码比较庞大，超过一千行，这里仅 介绍与 HTTP 请求处理的逻辑，采用代码块的逻辑介绍。

处理 HTTP 请求的逻辑代码集中在 label resync_request 处。

```
	struct task *process_session(struct task *t)
	{
		...
	 resync_request:
		/* Analyse request */
		if (((s->req->flags & ~rqf_last) & CF_MASK_ANALYSER) ||
			((s->req->flags ^ rqf_last) & CF_MASK_STATIC) ||
			s->si[0].state != rq_prod_last ||
			s->si[1].state != rq_cons_last) {
			unsigned int flags = s->req->flags;

			if (s->req->prod->state >= SI_ST_EST) {
				ana_list = ana_back = s->req->analysers;
				while (ana_list && max_loops--) {
					/* 这段代码中逐一的列举出了所有的 analysers 对应的处理函数
					 * 这里不一一列出，等待下文具体分析
					 */
					...
				}
			}
			rq_prod_last = s->si[0].state;
			rq_cons_last = s->si[1].state;
			s->req->flags &= ~CF_WAKE_ONCE;
			rqf_last = s->req->flags;

			if ((s->req->flags ^ flags) & CF_MASK_STATIC)
				goto resync_request;
		}
```

首先要判断 s->req->prod->state 的状态是否已经完成建连，根据之前的初始化动作， se->req->prod 指向 s->si[0]，即标识与 client 端连接的相关信息。正确建连成功之 后，会更改 si 的状态的，具体代码在 session_complete() 中：

```
	s->si[0].state     = s->si[0].prev_state = SI_ST_EST;
	...
	s->req->prod = &s->si[0];
	s->req->cons = &s->si[1];
```

只有 frontend 连接建立成功，才具备处理 client 发送请求数据的基础。上一篇文章中 已经接收到了 client 发送的数据。这里就是需要根据 s->req->analysers 的值，确定 while 循环中哪些函数处理当前的数据。

补充介绍一下 s->req->analysers 的赋值。 同样是在 session_complete 中初始化的

```
	/* activate default analysers enabled for this listener */
	s->req->analysers = l->analysers;
```

可见，其直接使用 session 所在的 listener 的 analyser。 listener 中该数值的初始化 是在 check_config_validity() 中完成的：
```
			listener->analysers |= curproxy->fe_req_ana;
```
而归根结蒂还是来源于 listener 所在的 proxy 上的 fe_req_ana， proxy 上的 fe_req_ana 的初始化同样是在 check_config_validity()，且是在给 listener->analysers 赋值之前

```
		if (curproxy->cap & PR_CAP_FE) {
			if (!curproxy->accept)
				curproxy->accept = frontend_accept;

			if (curproxy->tcp_req.inspect_delay ||
				!LIST_ISEMPTY(&curproxy->tcp_req.inspect_rules))
				curproxy->fe_req_ana |= AN_REQ_INSPECT_FE;

			if (curproxy->mode == PR_MODE_HTTP) {
				curproxy->fe_req_ana |= AN_REQ_WAIT_HTTP | AN_REQ_HTTP_PROCESS_FE;
				curproxy->fe_rsp_ana |= AN_RES_WAIT_HTTP | AN_RES_HTTP_PROCESS_FE;
			}

			/* both TCP and HTTP must check switching rules */
			curproxy->fe_req_ana |= AN_REQ_SWITCHING_RULES;
		}
```

从上面代码可以看出，一个 HTTP 模式的 proxy，至少有三个标记位会被置位： AN_REQ_WAIT_HTTP, AN_REQ_HTTP_PROCESS_FE, AN_REQ_SWITCHING_RULES。也就是说， s->req->analysers 由以上三个标记置位。那么随后处理 HTTP REQ 的循环中，就要经过 这三个标记位对应的 analyser 的处理。

接着回到 resync_request 标签下的那个 while 循环，就是逐个判断 analysers 的设置， 并调用对应的函数处理。需要启用那些 analysers，是和 haproxy 的配置相对应的。本文 使用最简单的配置，下面仅列出配置所用到的几个处理函数：

```
			while (ana_list && max_loops--) {
				/* Warning! ensure that analysers are always placed in ascending order! */

				if (ana_list & AN_REQ_INSPECT_FE) {
					if (!tcp_inspect_request(s, s->req, AN_REQ_INSPECT_FE))
						break;
					UPDATE_ANALYSERS(s->req->analysers, ana_list, ana_back, AN_REQ_INSPECT_FE);
				}
			
				if (ana_list & AN_REQ_WAIT_HTTP) {
					if (!http_wait_for_request(s, s->req, AN_REQ_WAIT_HTTP))
						break;
					UPDATE_ANALYSERS(s->req->analysers, ana_list, ana_back, AN_REQ_WAIT_HTTP);
				}

				if (ana_list & AN_REQ_HTTP_PROCESS_FE) {
					if (!http_process_req_common(s, s->req, AN_REQ_HTTP_PROCESS_FE, s->fe))
						break;
					UPDATE_ANALYSERS(s->req->analysers, ana_list, ana_back, AN_REQ_HTTP_PROCESS_FE);
				}

				if (ana_list & AN_REQ_SWITCHING_RULES) {
					if (!process_switching_rules(s, s->req, AN_REQ_SWITCHING_RULES))
						break;
					UPDATE_ANALYSERS(s->req->analysers, ana_list, ana_back, AN_REQ_SWITCHING_RULES);
				}
				...
			}
```

analysers 的处理也是有顺序的。其中处理请求的第一个函数是 tcp_inspect_request()。 该函数主要是在于如果配置了这里先介绍 http_wait_for_request() 函数的实现。 顾名思义，该函数主要是配置中启用 inspect_rules 时，会调用到该函数。否则的话， 处理 HTTP Req 的第一个函数就是 http_wait_for_request().

顾名思义，http_wait_for_request() 该函数分析所解析的 HTTP Requset 不一定是一个 完整的请求。上篇文章分析读取 client 请求数据的实现中，已经提到，只要不能从 socket 读到更多的数据，就会结束数据的接收。一个请求完全完全有可能因为一些异常原因，或者 请求长度本身就比较大而被拆分到不同的 IP 报文中，一次 read 系统调用可能只读取到其 中的一部分内容。因此，该函数会同时分析已经接收到的数据，并确认是否已经接收到了 完整的 HTTP 请求。只有接收到了完整的 HTTP 请求，该函数处理完，才会交给下一个 analyser 处理，否则只能结束请求的处理，等待接收跟多的数据，解析出一个完成的 HTTP 请求才行。

#### 4. 解析接收到的 http 请求数据： http_wait_for_request()

以下是 http_wait_for_request() 的简要分析：

1.调用 http_msg_analyzer，解析 s->req->buf 中新读取到的数据。该函数会按照 HTTP 协议， 解析 HTTP request 和 response 的头部数据，并记录到数据结构 struct http_msg 中。

2.如果开启了 debug，并且已经完整的解析了 header，则 header 内容打印出来

3.尚未读取到完整的 request 的处理，分作以下几种情形处理：

```
	if (unlikely(msg->msg_state < HTTP_MSG_BODY)) {
		/*
		 * First, let's catch bad requests.
		 */

	解析到 header 内容中有不符合 HTTP 协议的情形 HTTP_MSG_ERROR，应答 400 bad request 处理
	req->buf 满了，甚至加入 maxrewrite 的空间仍然不够用，应答 400 bad request
	读取错误 CF_READ_ERROR 发生，比如 client 发送 RST 断开连接， 应答 400 bad request
	读取超时，client 超时未发送完整的请求，应答 408 Request Timeout
	client 主动关闭，发送 FIN 包，实际上是所谓的 half-close，同样应答 400 bad request
	如果以上情况都不满足，则意味着还可以继续尝试读取新数据，设置一下超时

		/* just set the request timeout once at the beginning of the request */
		if (!tick_isset(req->analyse_exp)) {
			if ((msg->msg_state == HTTP_MSG_RQBEFORE) &&
				(txn->flags & TX_WAIT_NEXT_RQ) &&
				tick_isset(s->be->timeout.httpka))
				req->analyse_exp = tick_add(now_ms, s->be->timeout.httpka);
			else
				req->analyse_exp = tick_add_ifset(now_ms, s->be->timeout.httpreq);
		}
```

根据以上代码，在等待 http request 期间，有两种 timeout 可以设置： 当是http 连接 Keep-Alive 时，并且处理完了头一个请求之后，等待第二个请求期间，设置 httpka 的超 时，超过设定时间不发送新的请求，将会超时；否则，将设置 http 的 request timeout。

因此，在不启用 http ka timeout 时，http request 同时承担起 http ka timeout 的 功能。在有 http ka timeout 时，这两者各自作用的时间段没有重叠。

满足该环节的请求都终止处理，不再继续了。

##### 4.2. 处理完整的 http request

这里处理的都是已经解析到完整 http request header 的情况，并且所有 header 都被 索引化了，便于快速查找。根据已经得到的 header 的信息，设置 session 和 txn 的 相关成员，相当于汇总一下 header 的摘要信息，便于随后处理之用。流程如下：

```
	更新 session 和 proxy 的统计计数
	删除 http ka timeout 的超时处理。可能在上一个请求处理完之后，设置了 http ka 的 timeout，因为这里已经得到完整的请求，因此需要停止该 timeout 的处理逻辑
	确认 METHOD，并设置 session 的标记位 s->flags |= SN_REDIRECTABLE，只有 GET 和 HEAD 请求可以被重定向
	检测 URI 是否是配置的要做 monitor 的 URI，是的话，则执行对应 ACL，并设置应答
	检测如果开启 log 功能的话，要给 txn->uri 分配内存，用于记录 URI
	检测 HTTP version
		将 0.9 版本的升级为 1.0
		1.1 及其以上的版本都当做 1.1 处理
	初始化用于标识 Connection header 的标记位
	如果启用了 capture header 配置，调用 capture_headers() 记录下对应的 header
	处理 Transfer-Encoding/Content-Length 等 header
	最后一步，清理 req->analysers 的标记位 AN_REQ_WAIT_HTTP，因为本函数已经成功处理完毕，可以进行下一个 analyser 的处理了。
```

至此，http_wait_for_request() 的处理已经结束。

#### 5. 其他对 HTTP 请求的处理逻辑

按照我们前面分析的，随后应该还有两个 analyser 要处理，简单介绍一下：

```
	AN_REQ_HTTP_PROCESS_FE 对应的 http_process_req_common()
		对 frontend 中 req 配置的常见处理，比如 block ACLs, filter, reqadd 等
		设置 Connection mode， 主要是 haproxy 到 server 采用什么连接方式，tunnel 或者 按照 transcation 处理的短连接
	AN_REQ_SWITCHING_RULES 对应的 process_switching_rules()
		如果配置了选择 backend 的 rules，比如用 use_backend，则查询规则为 session 分配一个 backend
		处理 persist_rules，一旦设置了 force-persist, 则不管 server 是否 down，都要保证 session 分配给 persistence 中记录的 server。
```

以上两个函数，不再具体分析。待以后需要时再完善。

至此，client 端 http 请求已经完成解析和相关设置，并且给 session 指定了将来选择 server 所属的 backend。

下一篇文章就分析选择 server 的流程。 

