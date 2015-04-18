---
layout: post
title: "TCP状态转换"
date: 2015-04-18 16:13:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---

![](/images/kernel/2015-04-18-1.png)  

##### 1、建立连接协议（三次握手）
(1) 客户端发送一个带SYN标志的TCP报文到服务器。这是三次握手过程中的报文1。  
(2) 服务器端回应客户端的，这是三次握手中的第2个报文，这个报文同时带ACK标志和SYN标志。因此它表示对刚才客户端SYN报文的回应；同时又标志SYN给客户端，询问客户端是否准备好进行数据通讯。  
(3) 客户必须再次回应服务段一个ACK报文，这是报文段3。  

##### 2、连接终止协议（四次握手）
  由于TCP连接是全双工的，因此每个方向都必须单独进行关闭。这原则是当一方完成它的数据发送任务后就能发送一个FIN来终止这个方向的连接。收到一个 FIN只意味着这一方向上没有数据流动，一个TCP连接在收到一个FIN后仍能发送数据。首先进行关闭的一方将执行主动关闭，而另一方执行被动关闭。  
(1) TCP客户端发送一个FIN，用来关闭客户到服务器的数据传送（报文段4）。  
(2) 服务器收到这个FIN，它发回一个ACK，确认序号为收到的序号加1（报文段5）。和SYN一样，一个FIN将占用一个序号。  
(3) 服务器关闭客户端的连接，发送一个FIN给客户端（报文段6）。  
(4) 客户段发回ACK报文确认，并将确认序号设置为收到序号加1（报文段7）。  


#### tcp状态解释

0. CLOSED: 表示初始状态。  
1. LISTEN: 表示服务器端的某个SOCKET处于监听状态，可以接受连接了.  
2. SYN_SENT: 客户端通过应用程序调用connect进行active open.于是客户端tcp发送一个SYN以请求建立一个连接.之后状态置为SYN_SENT.  
3. SYN_RECV: 服务端应发出ACK确认客户端的SYN,同时自己向客户端发送一个SYN.之后状态置为SYN_RECV.  
4. ESTABLISHED：代表一个打开的连接，双方可以进行或已经在数据交互了.  
5. FIN_WAIT_1: 主动关闭(active close)端应用程序调用close，于是其TCP发出FIN请求主动关闭连接，之后进入FIN_WAIT1状态.  
6. FIN_WAIT2: 主动关闭端接到ACK后，就进入了FIN-WAIT-2 . 其实FIN_WAIT_1和FIN_WAIT_2状态的真正含义都是表示等待对方的FIN报文。而这两种状态的区别 是：FIN_WAIT_1状态实际上是当SOCKET在ESTABLISHED状态时，它想主动关闭连接，向对方发送了FIN报文，此时该SOCKET即 进入到FIN_WAIT_1状态。而当对方回应ACK报文后，则进入到FIN_WAIT_2状态.  
7. CLOSE_WAIT: CLOSE_WAIT:被动关闭(passive close)端TCP接到FIN后，就发出ACK以回应FIN请求(它的接收也作为文件结束符传递给上层应用程序),并进入CLOSE_WAIT。接下来还有数据发送给对方，如果没有的话，那么你也就可以 close这个SOCKET，发送FIN报文给对方，也即关闭连接。所以你在CLOSE_WAIT状态下，需要完成的事情是等待你去关闭连接.  
8. LAST_ACK: 被动关闭端一段时间后，接收到文件结束符的应用程序将调用CLOSE关闭连接。这导致它的TCP也发送一个 FIN,等待对方的ACK.就进入了LAST-ACK.  
9. TIME_WAIT: 在主动关闭端接收到FIN后，TCP就发送ACK包，并进入TIME-WAIT状态.  
10. CLOSING: 正常情况下，当你发送FIN报文后，按理来说是应该先收到（或同时收到）对方的 ACK报文，再收到对方的FIN报文。但是CLOSING状态表示你发送FIN报文后，没有收到对方的ACK报文，反而收到了对方的FIN报文。表示双方都正在关闭SOCKET连接.  
11. CLOSED: 被动关闭端在接受到ACK包后，就进入了closed的状态。连接结束.  


