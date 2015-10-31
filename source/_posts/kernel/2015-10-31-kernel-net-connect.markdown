---
layout: post
title: "tcp连接建立过程"
date: 2015-10-31 22:13:00 +0800
comments: false
categories:
- 2015
- 2015~10
- kernel
- kernel~net
tags:
---

#### 一、server

##### 1. 接收syn

```
	tcp_v4_do_rcv {
		nsk = tcp_v4_hnd_req(sk, skb);

		nsk == sk


		tcp_rcv_state_process {
			icsk->icsk_af_ops->conn_request(sk, skb)
			tcp_v4_conn_request {
				__tcp_v4_send_synack {

					2. 发送syn/ack
				}
			}
		}
	}
```

##### 2. 接收ack

```
	tcp_v4_do_rcv {
		nsk = tcp_v4_hnd_req(sk, skb) {
			req = inet_csk_search_req
			nsk = tcp_check_req {
				tcp_v4_syn_recv_sock {
					tcp_create_openreq_child {
						inet_csk_clone {

							newsk->sk_state = TCP_SYN_RECV;

						}
					}
				}
			}
		}

		nsk != sk {
			tcp_child_process {
				tcp_rcv_state_process {

					if (!tcp_validate_incoming(sk, skb, th, 0))
						return 0;

					/* step 5: check the ACK field */
					if (th->ack) {
						int acceptable = tcp_ack(sk, skb, FLAG_SLOWPATH) > 0;

						switch (sk->sk_state) {
							case TCP_SYN_RECV:

							tcp_set_state(sk, TCP_ESTABLISHED);

						}

						case TCP_ESTABLISHED:
							tcp_data_queue(sk, skb);
							queued = 1;
							break;
						}
					}

				}
			}
		}
	}
```

#### 二、client

##### 1. 发送syn

```
	tcp_v4_connect {

		tcp_set_state(sk, TCP_SYN_SENT);

		tcp_connect {
			__tcp_add_write_queue_tail
			tcp_transmit_skb
			inet_csk_reset_xmit_timer
		}
	}
```

##### 2. 接收syn/ack

```
	tcp_v4_do_rcv {
		sk->sk_state == TCP_SYN_SENT

		tcp_rcv_state_process {
			queued = tcp_rcv_synsent_state_process(sk, skb, th, len) {

				tcp_set_state(sk, TCP_ESTABLISHED);

				tcp_send_ack(sk); // 发送ack
			}
		}
	}
```

