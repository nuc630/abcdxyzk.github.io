---
layout: post
title: "HAProxy 研究笔记 -- epoll 事件的处理"
date: 2015-07-29 16:12:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3825388.html

 本文介绍 HAProxy 中 epoll 事件的处理机制，版本为 1.5-dev17。

```
	1. 背景知识
		1.1. fd 更新列表
		1.2. fdtab 数据结构
		1.3. fd event 的设置
	2. _do_poll() 代码分析
		2.1. 检测 fd 更新列表
		2.2. 获取活动的 fd
		2.3. 处理活动的 fd
```

HAProxy 支持多种异步机制，有 select，poll，epoll，kqueue 等。本文介绍 epoll 的 相关实现，epoll 的代码在源文件 ev_epoll.c 中。epoll 的关键处理逻辑集中在函数 _do_poll() 中，下面会详细的分析该函数。

#### 1. 背景知识

在分析 _do_poll() 实现之前，有一些关联的设计需要简单介绍一下，以便于理解该函数中 的一些代码。

##### 1.1. fd 更新列表

见 fd.c 中的全局变量：
```
	/* FD status is defined by the poller's status and by the speculative I/O list */
	int fd_nbupdt = 0;             // number of updates in the list
	unsigned int *fd_updt = NULL;  // FD updates list
```

这两个全局变量用来记录状态需要更新的 fd 的数量及具体的 fd。_do_poll() 中会根据 这些信息修改对应 fd 的 epoll 设置。

##### 1.2. fdtab 数据结构

struct fdtab 数据结构在 include/types/fd.h 中定义，内容如下：

```
	/* info about one given fd */
	struct fdtab {
		int (*iocb)(int fd);                 /* I/O handler, returns FD_WAIT_* */
		void *owner;                         /* the connection or listener associated with this fd, NULL if closed */
		unsigned int  spec_p;                /* speculative polling: position in spec list+1. 0=not in list. */
		unsigned char spec_e;                /* speculative polling: read and write events status. 4 bits */
		unsigned char ev;                    /* event seen in return of poll() : FD_POLL_* */
		unsigned char new:1;                 /* 1 if this fd has just been created */
		unsigned char updated:1;             /* 1 if this fd is already in the update list */
	};
```

该结构的成员基本上都有注释，除了前两个成员，其余的都是和 fd IO 处理相关的。后面 分析代码的时候再具体的解释。

src/fd.c 中还有一个全局变量：

```
	struct fdtab *fdtab = NULL;     /* array of all the file descriptors */
```

fdtab[] 记录了 HAProxy 所有 fd 的信息，数组的每个成员都是一个 struct fdtab， 而且成员的 index 正是 fd 的值，这样相当于 hash，可以高效的定位到某个 fd 对应的 信息。

##### 1.3. fd event 的设置

include/proto/fd.h 中定义了一些设置 fd event 的函数：

```
	/* event manipulation primitives for use by I/O callbacks */
	static inline void fd_want_recv(int fd)
	static inline void fd_stop_recv(int fd)
	static inline void fd_want_send(int fd)
	static inline void fd_stop_send(int fd)
	static inline void fd_stop_both(int fd)
```

这些函数见名知义，就是用来设置 fd 启动或停止接收以及发送的。这些函数底层调用的 是一系列 fd_ev_XXX() 的函数真正的设置 fd。这里简单介绍一下 fd_ev_set() 的代码：

```
	static inline void fd_ev_set(int fd, int dir)
	{
		unsigned int i = ((unsigned int)fdtab[fd].spec_e) & (FD_EV_STATUS << dir);
		...
		if (i & (FD_EV_ACTIVE << dir))
			return; /* already in desired state */
		fdtab[fd].spec_e |= (FD_EV_ACTIVE << dir);
		updt_fd(fd); /* need an update entry to change the state */
	}
```

该函数会判断一下 fd 的对应 event 是否已经设置了。没有设置的话，才重新设置。设置 的结果记录在 struct fdtab 结构的 spec_e 成员上，而且只是低 4 位上。然后调用 updt_fd() 将该 fd 放到 update list 中：

```
	static inline void updt_fd(const int fd)
	{
		if (fdtab[fd].updated)
			/* already scheduled for update */
			return;
		fdtab[fd].updated = 1;
		fd_updt[fd_nbupdt++] = fd;
	}
```

从上面代码可以看出， struct fdtab 中的 updated 成员用来标记当前 fd 是否已经被放 到 update list 中了。没有的话，则更新设置 updated 成员，并且记录到 fd_updt[] 中， 并且增加需要跟新的 fd 的计数 fd_nbupdt。

至此，用于分析 _do_poll() 的一些背景知识介绍完毕。

#### 2. _do_poll() 代码分析

这里将会重点的分析 _do_poll() 的实现。该函数可以粗略分为三部分：

```
	检查 fd 更新列表，获取各个 fd event 的变化情况，并作 epoll 的设置
	计算 epoll_wait 的 delay 时间，并调用 epoll_wait，获取活动的 fd
	逐一处理所有有 IO 事件的 fd
```

以下将按顺序介绍这三部分的代码。

##### 2.1. 检测 fd 更新列表

代码如下，后面会按行分析：

```
	 43 /*
	 44  * speculative epoll() poller
	 45  */
	 46 REGPRM2 static void _do_poll(struct poller *p, int exp)
	 47 {
	 ..     ..
	 53 
	 54     /* first, scan the update list to find changes */
	 55     for (updt_idx = 0; updt_idx < fd_nbupdt; updt_idx++) {
	 56         fd = fd_updt[updt_idx];
	 57         en = fdtab[fd].spec_e & 15;  /* new events */
	 58         eo = fdtab[fd].spec_e >> 4;  /* previous events */
	 59 
	 60         if (fdtab[fd].owner && (eo ^ en)) {
	 61             if ((eo ^ en) & FD_EV_POLLED_RW) {
	 62                 /* poll status changed */
	 63                 if ((en & FD_EV_POLLED_RW) == 0) {
	 64                     /* fd removed from poll list */
	 65                     opcode = EPOLL_CTL_DEL;
	 66                 }
	 67                 else if ((eo & FD_EV_POLLED_RW) == 0) {
	 68                     /* new fd in the poll list */
	 69                     opcode = EPOLL_CTL_ADD;
	 70                 }
	 71                 else {
	 72                     /* fd status changed */
	 73                     opcode = EPOLL_CTL_MOD;     
	 74                 }
	 75 
	 76                 /* construct the epoll events based on new state */
	 77                 ev.events = 0;
	 78                 if (en & FD_EV_POLLED_R)
	 79                     ev.events |= EPOLLIN;
	 80 
	 81                 if (en & FD_EV_POLLED_W)
	 82                     ev.events |= EPOLLOUT;
	 83 
	 84                 ev.data.fd = fd;
	 85                 epoll_ctl(epoll_fd, opcode, fd, &ev);
	 86             }
	 87 
	 88             fdtab[fd].spec_e = (en << 4) + en;  /* save new events */
	 89 
	 90             if (!(en & FD_EV_ACTIVE_RW)) {
	 91                 /* This fd doesn't use any active entry anymore, we can
	 92                  * kill its entry.
	 93                  */
	 94                 release_spec_entry(fd);
	 95             }
	 96             else if ((en & ~eo) & FD_EV_ACTIVE_RW) {
	 97                 /* we need a new spec entry now */
	 98                 alloc_spec_entry(fd);
	 99             }
	100                                                             
	101         }
	102         fdtab[fd].updated = 0;
	103         fdtab[fd].new = 0;
	104     }
	105     fd_nbupdt = 0;
```

haproxy 就是一个大的循环。每一轮循环，都顺序执行几个不同的功能。其中调用当前 poller 的 poll 方法便是其中一个环节。

55 - 56 行： 获取 fd 更新列表中的每一个 fd。 fd_updt[] 就是前面背景知识中介绍 的。haproxy 运行的不同阶段，都有可能通过调用背景知识中介绍的一些 fd event 设置函数 来更改 fd 的状态，最终会更新 fd_updt[] 和 fd_nbupdt。这里集中处理一下所有需要更新 的 fd。

57 - 58 行： 获取当前 fd 的最新事件，以及保存的上一次的事件。前面提到了，fd 的事 设置仅用 4 个 bit 就可以了。sturct fdtab 的 spec_e 成员是 unsigned char, 8 bit， 低 4 bit 保存 fd 当前最新的事件，高 4 bit 保存上一次的事件。这个做法就是为了判断 fd 的哪些事件上前面的处理中发生了变化，以便于更新。至于 fd 前一次的事件是什么时 后保存的，看后面的分析就知道了。

60 行： 主要判断 fd 记录的事件是否发生了变化。如果没有变化，就直接到 102-103 行 的处理了。这里有个小疑问，还没来及深入分析，就是哪些情况会使 fd 处于更新列表中， 但是 fd 上的事件有没有任何变化。

63 - 74 行：检测 fd 的 epoll operation 是否需要更改，比如ADD/DEL/MOD 等操作。

77 - 85 行：检测 fd 的 epoll events 的设置，并调用 epoll_ctl 设置 op 和 event

88 行：这里就是记录下 fd events 设置的最新状态。高低 4 位记录的结果相同。而在 程序运行过程中，仅修改低 4 位，这样和高 4 位一比较，就知道发生了哪些变化。

90 - 99 行：这里主要根据 fd 的新旧状态，更新 speculative I/O list。这个地方在 haproxy 的大循环中有独立的处理流程，这里不作分析。

102 - 103 行：清除 fd 的 new 和 updated 状态。new 状态通常是在新建一个 fd 时调 用 fd_insert 设置的，这里已经完成了 fd 状态的更新，因此两个成员均清零。

105 行： 整个 update list 都处理完了，fd_nbupdt 清零。haproxy 的其他处理流程会 继续更新 update list。下一次调用 _do_poll() 的时候继续处理。当然，这么说也说是 不全面的，因为接下来的处理流程也会有可能处理 fd 的 update list。但主要的处理还 是这里分析的代码块。

至此，fd 更新列表中的所有 fd 都处理完毕，该设置的也都设置了。下面就需要调用 epoll_wait 获得所有活动的 fd 了。
2.2. 获取活动的 fd

代码如下：

```
	107     /* compute the epoll_wait() timeout */
	108 
	109     if (fd_nbspec || run_queue || signal_queue_len) {
	...         ...
	115         wait_time = 0;
	116     }
	117     else {
	118         if (!exp)
	119             wait_time = MAX_DELAY_MS;
	120         else if (tick_is_expired(exp, now_ms))
	121             wait_time = 0;
	122         else {
	123             wait_time = TICKS_TO_MS(tick_remain(now_ms, exp)) + 1;
	124             if (wait_time > MAX_DELAY_MS)
	125                 wait_time = MAX_DELAY_MS;
	126         }
	127     }
	128 
	129     /* now let's wait for polled events */
	130 
	131     fd = MIN(maxfd, global.tune.maxpollevents);
	132     gettimeofday(&before_poll, NULL);
	133     status = epoll_wait(epoll_fd, epoll_events, fd, wait_time);
	134     tv_update_date(wait_time, status);
	135     measure_idle();
```

107 - 127 行：主要是用来计算调用 epoll_wait 时的 timeout 参数。如果 fd_nbspec 不为 0，或 run_queue 中有任务需要运行，或者信号处理 queue 中有需要处理的，都设置 timeout 为 0，目的是希望 epoll_wait 尽快返回，程序好及时处理其他的任务。

131 - 135 行： 计算当前最多可以处理的 event 数目。这个数目也是可配置的。然后调用 epoll_wait, 所有活动 fd 的信息都保存在 epoll_events[] 数组中。

这部分代码逻辑比较简单，接下来就是处理所有活动的 fd 了。
2.3. 处理活动的 fd

逐一处理活动的 fd。这段代码也可以划分为若干个小代码，分别介绍如下：

```
	139     for (count = 0; count < status; count++) {
	140         unsigned char n;
	141         unsigned char e = epoll_events[count].events;
	142         fd = epoll_events[count].data.fd;
	143 
	144         if (!fdtab[fd].owner)
	145             continue;
	146 
	147         /* it looks complicated but gcc can optimize it away when constants
	148          * have same values... In fact it depends on gcc :-(
	149          */
	150         fdtab[fd].ev &= FD_POLL_STICKY;
	151         if (EPOLLIN == FD_POLL_IN && EPOLLOUT == FD_POLL_OUT &&
	152             EPOLLPRI == FD_POLL_PRI && EPOLLERR == FD_POLL_ERR &&
	153             EPOLLHUP == FD_POLL_HUP) {
	154             n = e & (EPOLLIN|EPOLLOUT|EPOLLPRI|EPOLLERR|EPOLLHUP);
	155         }
	156         else {
	157             n = ((e & EPOLLIN ) ? FD_POLL_IN  : 0) |
	158                 ((e & EPOLLPRI) ? FD_POLL_PRI : 0) |
	159                 ((e & EPOLLOUT) ? FD_POLL_OUT : 0) |
	160                 ((e & EPOLLERR) ? FD_POLL_ERR : 0) |
	161                 ((e & EPOLLHUP) ? FD_POLL_HUP : 0);
	162         }
	163 
	164         if (!n)
	165             continue;
	166 
	167         fdtab[fd].ev |= n;    
	168
```

139 - 142 行： 从 epoll_events[] 中取出一个活动 fd 及其对应的 event。

150 行： fdtab[fd].ev 仅保留 FD_POLL_STICKY 设置，即 FD_POLL_ERR | FD_POLL_HUP， 代表仅保留 fd 原先 events 设置中的错误以及 hang up 的标记位，不管 epoll_wait 中 是否设置了该 fd 的这两个 events。

151 - 162 行： 这段代码的功能主要就是根据 epoll_wait 返回的 fd 的 events 设置情 况，正确的设置 fdtab[fd].ev。之所以代码还要加上条件判断，是因为 haproxy 自己也 用了一套标记 fd 的 events 的宏定义 FD_POLL_XXX，而 epoll_wait 返回的则是系统中 的 EPOLLXXX。因此，这里就涉及到系统标准的 events 转换到 haproxy 自定义 events 的过程。其中，151-154 行代表 haproxy 自定义的关于 fd 的 events 和系统标准的 完全一致，157-161 行代表 haproxy 自定义的和系统标准的不一致，因此需要一个一个 标记位判断，然后转换成 haproxy 自定义的。

167 行： 将转换后的 events 记录到 fdtab[fd].ev。因此，haproxy 中对于 fd events 的记录，始终是采用 haproxy 自定义的。

```
	169         if (fdtab[fd].iocb) {
	170             int new_updt, old_updt;
	171 
	172             /* Mark the events as speculative before processing
	173              * them so that if nothing can be done we don't need
	174              * to poll again.
	175              */
	176             if (fdtab[fd].ev & FD_POLL_IN)
	177                 fd_ev_set(fd, DIR_RD);
	178 
	179             if (fdtab[fd].ev & FD_POLL_OUT)
	180                 fd_ev_set(fd, DIR_WR);
	181 
	182             if (fdtab[fd].spec_p) {
	183                 /* This fd was already scheduled for being called as a speculative I/O */
	184                 continue;
	185             }
	186 
	187             /* Save number of updates to detect creation of new FDs. */
	188             old_updt = fd_nbupdt;
	189             fdtab[fd].iocb(fd);
```

169 行： 正常情况下， fdtab[fd] 的 iocb 方法指向 conn_fd_handler，该函数负责处 理 fd 上的 IO 事件。

176 - 180 行： 根据前面设置的 fd 的 events，通过调用 fd_ev_set() 更新 fdtab 结构 的 spec_e 成员。也就是说，在调用 fd_ev_clr() 清理对应 event 之前，就不需要再次设 置 fd 的 event。因为 haproxy 认为仍然需要处理 fd 的 IO。fdtab 的 ev 成员是从 epoll_wait 返回的 events 转换后的结果，而 spec_e 成员则是 haproxy 加入了一些对 fd IO 事件可能性判断的结果。

188 - 189 行： 保存一下当前的 fd update list 的数目，接着调用 fd 的 iocb 方法， 也就是 conn_fd_handler()。之所以要保存当前的 fd update list 数目，是因为 conn_fd_handler() 执行时，如果接受了新的连接，则会有新的 fd 生成，这时也会更新 fd_nbupdt。记录下旧值，就是为了方便知道在 conn_fd_handler 执行之后，有哪些 fd 是新生成的。

```
	...             ...
	200             for (new_updt = fd_nbupdt; new_updt > old_updt; new_updt--) {
	201                 fd = fd_updt[new_updt - 1];
	202                 if (!fdtab[fd].new)
	203                     continue;
	204 
	205                 fdtab[fd].new = 0;
	206                 fdtab[fd].ev &= FD_POLL_STICKY;
	207 
	208                 if ((fdtab[fd].spec_e & FD_EV_STATUS_R) == FD_EV_ACTIVE_R)
	209                     fdtab[fd].ev |= FD_POLL_IN;
	210 
	211                 if ((fdtab[fd].spec_e & FD_EV_STATUS_W) == FD_EV_ACTIVE_W)
	212                     fdtab[fd].ev |= FD_POLL_OUT;
	213 
	214                 if (fdtab[fd].ev && fdtab[fd].iocb && fdtab[fd].owner)
	215                     fdtab[fd].iocb(fd);
	216 
	217                 /* we can remove this update entry if it's the last one and is
	218                  * unused, otherwise we don't touch anything.
	219                  */
	220                 if (new_updt == fd_nbupdt && fdtab[fd].spec_e == 0) {
	221                     fdtab[fd].updated = 0;
	222                     fd_nbupdt--;
	223                 }
	224             }
	225         }
	226     }
	227 
	228     /* the caller will take care of speculative events */
	229 }  
```

上面这段代码就是执行完毕当前活动 fd 的 iocb 之后，发现有若干个新的 fd 生成，通常 发生在接收新建连接的情况。这种情况，haproxy 认为有必要立即执行这些新的 fd 的 iocb 方法。因为通常一旦客户端新建连接的话，都会尽快发送数据的。这么做就不必等到 下次 epoll_wait 返回之后才处理新的 fd，提高了效率。

至此，haproxy epoll 的事件处理机制粗略分析完毕。这里还有一个 speculative events 的逻辑，本文分析中全都跳过了，随后再完善。 

