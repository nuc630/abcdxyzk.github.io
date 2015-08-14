---
layout: post
title: "SYN cookies机制下连接的建立"
date: 2015-04-10 14:34:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/justlinux2010/article/details/12619761

  在正常情况下，服务器端接收到客户端发送的SYN包，会分配一个连接请求块（即request_sock结构），用于保存连接请求信息，并且发送SYN+ACK包给客户端，然后将连接请求块添加到半连接队列中。客户端接收到SYN+ACK包后，会发送ACK包对服务器端的包进行确认。服务器端收到客户端的确认后，根据保存的连接信息，构建一个新的连接，放到监听套接字的连接队列中，等待用户层accept连接。这是正常的情况，但是在并发过高或者遭受SYN flood攻击的情况下，半连接队列的槽位数量很快就会耗尽，会导致丢弃新的连接请求，SYN cookies技术可以使服务器在半连接队列已满的情况下仍能处理新的SYN请求。

  如果开启了SYN cookies选项，在半连接队列满时，SYN cookies并不丢弃SYN请求，而是将源目的IP、源目的端口号、接收到的客户端初始序列号以及其他一些安全数值等信息进行hash运算，并加密后得到服务器端的初始序列号，称之为cookie。服务器端在发送初始序列号为cookie的SYN+ACK包后，会将分配的连接请求块释放。如果接收到客户端的ACK包，服务器端将客户端的ACK序列号减1得到的值，与上述要素hash运算得到的值比较，如果相等，直接完成三次握手，构建新的连接。SYN cookies机制的核心就是避免攻击造成的大量构造无用的连接请求块，导致内存耗尽，而无法处理正常的连接请求。

  启用SYN cookies是通过在启动环境中设置以下命令完成：
```
	echo 1 > /proc/sys/net/ipv4/tcp_syncookies
```
  注意，即使开启该机制并不意味着所有的连接都是用SYN cookies机制来完成连接的建立，只有在半连接队列已满的情况下才会触发SYN cookies机制。由于SYN cookies机制严重违背TCP协议，不允许使用TCP扩展，可能对某些服务造成严重的性能影响（如SMTP转发），对于防御SYN flood攻击的确有效。对于没有收到攻击的高负载服务器，不要开启此选项，可以通过修改tcp_max_syn_backlog、tcp_synack_retries和tcp_abort_on_overflow系统参数来调节。

下面来看看内核中是怎么通过SYN cookie机制来完成连接的建立。

  客户端的连接请求由
```
	tcp_v4_do_rcv()
		tcp_rcv_state_process()
			icsk->icsk_af_ops->conn_request()
				tcp_v4_conn_request()
```
函数处理。tcp_v4_conn_request()中有一个局部变量want_cookie，用来标识是否使用SYN cookies机制。want_cookie的初始值为0，如果半连接队列已满，并且开启了tcp_syncookies系统参数，则将其值设置为1，如下所示：

```
	int tcp_v4_conn_request(struct sock *sk, struct sk_buff *skb)
	{
	#ifdef CONFIG_SYN_COOKIES
		int want_cookie = 0;
	#else
	#define want_cookie 0 /* Argh, why doesn't gcc optimize this :( */
	#endif

	...... 

		/* TW buckets are converted to open requests without
		 * limitations, they conserve resources and peer is
		 * evidently real one.
		 */
		if (inet_csk_reqsk_queue_is_full(sk) && !isn) {
	#ifdef CONFIG_SYN_COOKIES
			if (sysctl_tcp_syncookies) {
				want_cookie = 1;
			} else
	#endif
		   
			goto drop;
		}
	......

	drop:
		return 0;
	}
```

  如果没有开启SYN cookies机制，在半连接队列满时，会跳转到drop处，返回0。在调用tcp_v4_conn_request()的tcp_rcv_state_process()中会直接释放SKB包。

  我们前面提高过，造成半连接队列满有两种情况（不考虑半连接队列很小的情况），一种是负载过高，正常的连接数过多；另一种是SYN flood攻击。如果是第一种情况，此时是否继续构建连接，则要取决于连接队列的情况及半连接队列的重传情况，如下所示：
```
	if (sk_acceptq_is_full(sk) && inet_csk_reqsk_queue_young(sk) > 1)
		goto drop;
```
  sk_acceptq_is_full()函数很好理解，根据字面意思就可以看出，该函数是检查连接队列是否已满。inet_csk_reqsk_queue_young()函数返回半连接队列中未重传过SYN+ACK段的连接请求块数量。如果连接队列已满并且半连接队列中的连接请求块中未重传的数量大于1，则会跳转到drop处，丢弃SYN包。如果半连接队列中未重传的请求块数量大于1，则表示未来可能有2个完成的连接，这些新完成的连接要放到连接队列中，但此时连接队列已满。如果在接收到三次握手中最后的ACK后连接队列中没有空闲的位置，会忽略接收到的ACK包，连接建立会推迟，所以此时最好丢掉部分新的连接请求，空出资源以完成正在进行的连接建立过程。还要注意，这个判断并没有考虑半连接队列是否已满的问题。从这里可以看出，即使开启了SYN cookies机制并不意味着一定可以完成连接的建立。

  如果可以继续连接的建立，调用inet_reqsk_alloc()分配连接请求块，如下所示：
```
	req = inet_reqsk_alloc(&tcp_request_sock_ops);
	if (!req)
		goto drop;
```
  看到这里可能就有人疑惑，既然开启了SYN cookies机制，仍然分配连接请求块，那和正常的连接构建也没有什么区别了。这里之所以要分配连接请求块是用于发送SYN+ACK包给客户端，发送后会释放掉，并不会加入到半连接队列中。

  接下来就是计算cookie的值，由cookie_v4_init_sequence()函数完成，如下所示：
```
	if (want_cookie) {
	#ifdef CONFIG_SYN_COOKIES
		syn_flood_warning(skb);
		req->cookie_ts = tmp_opt.tstamp_ok;
	#endif
		isn = cookie_v4_init_sequence(sk, skb, &req->mss);
	}
```
  计算得到的cookie值会保存在连接请求块tcp_request_sock结构的snt_isn成员中，接着会调用__tcp_v4_send_synack()函数发送SYN+ACK包，然后释放前面分配的连接请求块，如下所示：
```
	if (__tcp_v4_send_synack(sk, req, dst) || want_cookie)
		goto drop_and_free;
```
  在服务器端发送完SYN+ACK包后，我们看到在服务器端没有保存任何关于这个未完成连接的信息，所以在接收到客户端的ACK包后，只能根据前面发送的SYN+ACK包中的cookie值来决定是否继续构建连接。

  我们接下来看接收到ACK包后的处理情况。ACK包在tcp_v4_do_rcv()函数中调用的tcp_v4_hnd_req()中处理，如下所示：
```
	static struct sock *tcp_v4_hnd_req(struct sock *sk, struct sk_buff *skb)
	{
		......
	 
	#ifdef CONFIG_SYN_COOKIES
		if (!th->rst && !th->syn && th->ack)
			sk = cookie_v4_check(sk, skb, &(IPCB(skb)->opt));
	#endif
		return sk;
	}
```
  由于在服务器端没有保存未完成连接的信息，所以在半连接队列或ehash散列表中都不会找到对应的sock结构。如果开启了SYN cookies机制，则会检查接收到的数据包是否是ACK包，如果是，在cookie_v4_check()中会调用cookie_check()函数检查ACK包中的cookie值是否有效。如果有效，则会分配request_sock结构，并根据ACK包初始化相应的成员，开始构建描述连接的sock结构。创建过程和正常的连接创建过程一样。

