---
layout: post
title: "解析pcap数据包格式"
date: 2013-08-26 11:17:00 +0800
comments: false
categories:
- 2013
- 2013~08
- kernel
- kernel~net
tags:
---
  协议是一个比较复杂的协议集，有很多专业书籍介绍。在此，我仅介绍其与编程密切相关的部分：以太网上TCP/IP协议的分层结构及其报文格式。  
我们知道TCP/IP协议采用分层结构，其分层模型及协议如下表：  
应　用　层	(Application) HTTP、Telnet、FTP、SMTP、SNMP  
传　输　层	(Transport) TCP、UDP  
网 间 网层	(Internet) IP【ARP、RARP、ICMP】  
网络接口层	(Network) Ethernet、X.25、SLIP、PPP

  协议采用分层结构，因此，数据报文也采用分层封装的方法。下面以应用最广泛的以太网为例说明其数据报文分层封装，如下图所示：

![](/images/kernel/2013-08-26-1.png)

  任何通讯协议都有独特的报文格式，TCP/IP协议也不例外。对于通讯协议编程，我们首先要清楚其报文格式。由于TCP/IP协议采用分层模型，各层都有专用的报头，以下就简单介绍以太网下TCP/IP各层报文格式。

![](/images/kernel/2013-08-26-2.png)

  8字节的前导用于帧同步，CRC域用于帧校验。这些用户不必关心其由网卡芯片自动添加。目的地址和源地址是指网卡的物理地址，即MAC地址，具有唯一性。帧类型或协议类型是指数据包的高级协议，如 0x0806表示ARP协议，0x0800表示IP协议等。

　　ARP/RARP（地址解析/反向地址解析）报文格式如下图：

![](/images/kernel/2013-08-26-3.png)

 “硬件类型”域指发送者本机网络接口类型（值“1”代表以太网）。“协议类型”域指发送者所提供/请求的高级协议地址类型（“0x0800”代表 IP协议）。“操作”域指出本报文的类型（“1”为ARP请求，“2”为ARP响应，“3”为RARP请求，“4”为RARP响应）。

　　IP数据报头格式如下图：

![](/images/kernel/2013-08-26-4.png)

　　我们用单片机实现TCP/IP协议要作一些简化，不考虑数据分片和优先权。因此，在此我们不讨论服务类型和标志偏移域，只需填“0” 即可。协议“版本”为4，“头长度”单位为32Bit，“总长度”以字节为单位，表示整个IP数据报长度。“标识”是数据包的ID号，用于识别不同的IP 数据包。“生存时间” TTL是个数量及的概念，防止无用数据包一直存在网络中。一般每经过路由器时减一，因此通过TTL 可以算出数据包到达目的地所经过的路由器个数。“协议”域表示创建该数据包的高级协议类型。如 1表示ICMP协议，6表示TCP协议，17表示 UDP协议等。IP数据包为简化数据转发时间，仅采用头校验的方法，数据正确性由高层协议保证。

　　ICMP（网间网控制报文协议）协议 应用广泛。在此仅给出最常见的回应请求与应答报文格式，用户命令ping便是利用此报文来测试信宿机的可到达性。报文格式如下图所示：

![](/images/kernel/2013-08-26-5.png)

　　类型0 为回应应答报文，8 为回应请求报文。整个数据包均参与检验。注意ICMP封装在IP数据包里传送。

　　UDP报文格式如下图：

![](/images/kernel/2013-08-26-6.png)

　　TCP报文格式如下图：

![](/images/kernel/2013-08-26-7.png)


--------------

WireShark捕获的数据

![](/images/kernel/2013-08-26-8.jpg)

```
                            以下为物理层的数据帧概况

Frame 1 (62 bytes on wire, 62 bytes captured)           1号帧，线路62字节，实际捕获62字节
Arrival Time: Jan 21, 2008 15:17:33.910261000           捕获日期和时间
[Time delta from previous packet:0.00000 seconds]       此包与前一包的时间间隔
[Time since reference or first frame: 0.00 seconds]     此包与第1帧的间隔时间
Frame Number: 1                                         帧序号
Packet Length: 62 bytes                                 帧长度
Capture Length: 62 bytes                                捕获长度
[Frame is marked: False]                                此帧是否做了标记：否
[Protocols in frame: eth:ip:tcp]                        帧内封装的协议层次结构
[Coloring Rule Name: HTTP]                              用不同颜色染色标记的协议名称：HTTP
[Coloring Rule String: http || tcp.port == 80]          染色显示规则的字符串：


                    以下为数据链路层以太网帧头部信息
Ethernet II, Src: AcerTech_5b:d4:61 (00:00:e2:5b:d4:61), Dst: Jetcell_e5:1d:0a (00:d0:2b:e5:1d:0a)
以太网协议版本II，源地址：厂名_序号（网卡地址），目的：厂名_序号（网卡地址）
 Destination: Jetcell_e5:1d:0a (00:d0:2b:e5:1d:0a)       目的：厂名_序号（网卡地址）
 Source: AcerTech_5b:d4:61 (00:00:e2:5b:d4:61)           源：厂名_序号（网卡地址）
 Type: IP (0x0800)                                       帧内封装的上层协议类型为IP（十六进制码0800）看教材70页图3.2

                          以下为互联网层IP包头部信息
Internet Protocol, Src: 202.203.44.225 (202.203.44.225), Dst: 202.203.208.32 (202.203.208.32)
互联网协议，源IP地址，目的IP地址
Version: 4                                                       互联网协议IPv4
Header length: 20 bytes                                          IP包头部长度
Differentiated Services Field:0x00(DSCP 0x00:Default;ECN:0x00)   差分服务字段
Total Length: 48                                                 IP包的总长度
Identification:0x8360 (33632)                                    标志字段
Flags:                                                           标记字段（在路由传输时，是否允许将此IP包分段）
Fragment offset: 0                                               分段偏移量（将一个IP包分段后传输时，本段的标识）
Time to live: 128                                                生存期TTL
Protocol: TCP (0x06)                                             此包内封装的上层协议为TCP
Header checksum: 0xe4ce [correct]                                头部数据的校验和
Source: 202.203.44.225 (202.203.44.225)                          源IP地址
Destination: 202.203.208.32 (202.203.208.32)                     目的IP地址

                        以下为传输层TCP数据段头部信息
Transmission Control Protocol, Src Port: 2764 (2764), Dst Port: http (80), Seq: 0, Len: 0   传输控制协议TCP的内容
Source port: 2764 (2764）                              源端口名称（端口号）
Destination port: http (80)                            目的端口名http（端口号80）
Sequence number: 0    (relative sequence number)       序列号（相对序列号）
Header length: 28 bytes                                头部长度
Flags: 0x02 (SYN)                                      TCP标记字段（本字段是SYN，是请求建立TCP连接）
Window size: 65535                                     流量控制的窗口大小
Checksum: 0xf73b [correct]                             TCP数据段的校验和
Options: (8 bytes)                                     可选项
```
