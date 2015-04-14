---
layout: post
title: " Linux网络编程：原始套接字 SOCK_RAW"
date: 2015-04-14 21:27:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.chinaunix.net/uid-23069658-id-3280895.html

#### 一、修改iphdr+tcphdr
对于TCP或UDP的程序开发，焦点在Data字段，我们没法直接对TCP或UDP头部字段进行赤裸裸的修改，当然还有IP头。换句话说，我们对它们头部操作的空间非常受限，只能使用它们已经开放给我们的诸如源、目的IP，源、目的端口等等。

原始套接字的创建方法：
```
	socket(AF_INET, SOCK_RAW, protocol);
```
  重点在protocol字段，这里就不能简单的将其值为0了。在头文件netinet/in.h中定义了系统中该字段目前能取的值，注意：有些系统中不一定实现了netinet/in.h中的所有协议。源代码的linux/in.h中和netinet/in.h中的内容一样。我们常见的有IPPROTO_TCP，IPPROTO_UDP和IPPROTO_ICMP。

用这种方式我就可以得到原始的IP包了，然后就可以自定义IP所承载的具体协议类型，如TCP，UDP或ICMP，并手动对每种承载在IP协议之上的报文进行填充。

先简单复习一下TCP报文的格式

![](/images/kernel/2015-04-14-1.jpg)  

![](/images/kernel/2015-04-14-2.jpg)  

原始套接字还提供了一个非常有用的参数IP_HDRINCL：

1、当开启该参数时：我们可以从IP报文首部第一个字节开始依次构造整个IP报文的所有选项，但是IP报文头部中的标识字段(设置为0时)和IP首部校验和字段总是由内核自己维护的，不需要我们关心。

2、如果不开启该参数：我们所构造的报文是从IP首部之后的第一个字节开始，IP首部由内核自己维护，首部中的协议字段被设置成调用socket()函数时我们所传递给它的第三个参数。

 开启IP_HDRINCL特性的模板代码一般为：
```
	const int on =1;
	if (setsockopt (sockfd, IPPROTO_IP, IP_HDRINCL, &on, sizeof(on)) < 0) {
		printf("setsockopt error!\n");
	}
```

所以，我们还得复习一下IP报文的首部格式：

![](/images/kernel/2015-04-14-3.jpg)  

同样，我们重点关注IP首部中的着色部分区段的填充情况。

```
	#include <stdlib.h>
	#include <stdio.h>
	#include <errno.h>
	#include <string.h>
	#include <unistd.h>
	#include <netdb.h>
	#include <sys/socket.h>
	#include <sys/types.h>
	#include <netinet/in.h>
	#include <netinet/ip.h>
	#include <arpa/inet.h>
	#include <linux/tcp.h>

	#include <linux/if_ether.h>
	#include <linux/if_arp.h>
	#include <linux/sockios.h>

	unsigned csum_tcpudp_nofold(unsigned saddr, unsigned daddr,
				unsigned len, unsigned proto, unsigned sum)
	{
		unsigned long long s = (unsigned)sum;
		s += (unsigned)saddr;
		s += (unsigned)daddr;
		s += (proto + len) << 8;
		s += (s >> 32);
		return (unsigned)s;
	}

	unsigned short check_sum(unsigned short *addr, int len, unsigned sum)
	{
		int nleft = len;
		unsigned short *w = addr;
		unsigned short ret = 0;
		while (nleft > 1) {
			sum += *w++;
			nleft -= 2;
		}
		if (nleft == 1) {
			*(unsigned char *)(&ret) = *(unsigned char *)w;
			sum += ret;
		}

		sum = (sum>>16) + (sum&0xffff);
		sum += (sum>>16);
		ret = ~sum;
		return ret;
	}

	//在该函数中构造整个IP报文，最后调用sendto函数将报文发送出去
	void attack(int skfd, struct sockaddr_in *target, unsigned short srcport)
	{
		char buf[256] = {0};
		struct ip *ip;
		struct tcphdr *tcp;
		int ip_len;
		int op_len = 12;

		//在我们TCP的报文中Data没有字段，所以整个IP报文的长度
		ip_len = sizeof(struct ip) + sizeof(struct tcphdr) + op_len;

		//开始填充IP首部
		ip=(struct ip*)buf;
		ip->ip_v = IPVERSION;
		ip->ip_hl = sizeof(struct ip)>>2;
		ip->ip_tos = 0;
		ip->ip_len = htons(ip_len);
		ip->ip_id = 0;
		ip->ip_off = 0;
		ip->ip_ttl = MAXTTL;
		ip->ip_p = IPPROTO_TCP;
		ip->ip_sum = 0;
		ip->ip_dst = target->sin_addr;

		//开始填充TCP首部
		tcp = (struct tcphdr*)(buf+sizeof(struct ip));
		tcp->source = htons(srcport);
		tcp->dest = target->sin_port;
		srand(time(NULL));
		tcp->doff = (sizeof(struct tcphdr) + op_len) >> 2; // tcphdr + option
		tcp->syn = 1;
		tcp->check = 0;
		tcp->window = ntohs(14600);

		int i = ip_len - op_len;
		// mss = 1460
		buf[i++] = 0x02;
		buf[i++] = 0x04;
		buf[i++] = 0x05;
		buf[i++] = 0xb4;
		// sack
		buf[i++] = 0x01;
		buf[i++] = 0x01;
		buf[i++] = 0x04;
		buf[i++] = 0x02;
		// wsscale = 7
		buf[i++] = 0x01;
		buf[i++] = 0x03;
		buf[i++] = 0x03;
		buf[i++] = 0x07;

		int T = 1;
		while(1) {
			if (T == 0) break;
			T--;
			tcp->seq = random();
			//源地址伪造，我们随便任意生成个地址，让服务器一直等待下去
			//ip->ip_src.s_addr = random();
			//自定义源地址192.168.204.136 = 0xc0a8cc88; 反转赋值
			ip->ip_src.s_addr = 0x88cca8c0;
			unsigned sum = csum_tcpudp_nofold(ip->ip_src.s_addr, ip->ip_dst.s_addr, sizeof(struct tcphdr)+op_len, IPPROTO_TCP, 0);
			tcp->check = check_sum((unsigned short*)tcp, sizeof(struct tcphdr)+op_len, sum);
	//		ip->ip_sum = check_sum((unsigned short*)ip, sizeof(struct ip), 0);
			sendto(skfd, buf, ip_len, 0, (struct sockaddr*)target, sizeof(struct sockaddr_in));
		}
	}

	int main(int argc, char** argv)
	{
		int skfd;
		struct sockaddr_in target;
		struct hostent *host;
		const int on = 1;
		unsigned short srcport;

		if (argc != 4) {
			printf("Usage:%s dstip dstport srcport\n", argv[0]);
			exit(1);
		}

		bzero(&target, sizeof(struct sockaddr_in));
		target.sin_family = AF_INET;
		target.sin_port = htons(atoi(argv[2]));

		if (inet_aton(argv[1], &target.sin_addr) == 0) {
			host = gethostbyname(argv[1]);
			if(host == NULL) {
				printf("TargetName Error:%s\n", hstrerror(h_errno));
				exit(1);
			}
			target.sin_addr = *(struct in_addr *)(host->h_addr_list[0]);
		}

		//将协议字段置为IPPROTO_TCP，来创建一个TCP的原始套接字
		if (0 > (skfd = socket(AF_INET, SOCK_RAW, IPPROTO_TCP))) {
			perror("Create Error");
			exit(1);
		}

		//用模板代码来开启IP_HDRINCL特性，我们完全自己手动构造IP报文
		if (0 > setsockopt(skfd, IPPROTO_IP, IP_HDRINCL, &on, sizeof(on))) {
			perror("IP_HDRINCL failed");
			exit(1);
		}

		//因为只有root用户才可以play with raw socket :)
		setuid(getpid());
		srcport = atoi(argv[3]);
		attack(skfd, &target, srcport);
	}
```

* 原始套接字上也可以调用connet、bind之类的函数


-------------

#### 修改mac+iphdr+tcphdr

blog.chinaunix.net/uid-23069658-id-3283534.html

在Linux系统中要从链路层(MAC)直接收发数帧，比较普遍的做法就是用libpcap和libnet两个动态库来实现。但今天我们就要用原始套接字来实现这个功能。

![](/images/kernel/2015-04-14-4.jpg)  

这里的2字节帧类型用来指示该数据帧所承载的上层协议是IP、ARP或其他。

为了实现直接从链路层收发数据帧，我们要用到原始套接字的如下形式：
```
	socket(PF_PACKET, type, protocol)
```
1、其中type字段可取SOCK_RAW或SOCK_DGRAM。它们两个都使用一种与设备无关的标准物理层地址结构struct sockaddr_ll{}，但具体操作的报文格式不同：

SOCK_RAW：直接向网络硬件驱动程序发送(或从网络硬件驱动程序接收)没有任何处理的完整数据报文(包括物理帧的帧头)，这就要求我们必须了解对应设备的物理帧帧头结构，才能正确地装载和分析报文。也就是说我们用这种套接字从网卡驱动上收上来的报文包含了MAC头部，如果我们要用这种形式的套接字直接向网卡发送数据帧，那么我们必须自己组装我们MAC头部。这正符合我们的需求。

SOCK_DGRAM：这种类型的套接字对于收到的数据报文的物理帧帧头会被系统自动去掉，然后再将其往协议栈上层传递；同样地，在发送时数据时，系统将会根据sockaddr_ll结构中的目的地址信息为数据报文添加一个合适的MAC帧头。

2、protocol字段，常见的，一般情况下该字段取ETH_P_IP，ETH_P_ARP，ETH_P_RARP或ETH_P_ALL，当然链路层协议很多，肯定不止我们说的这几个，但我们一般只关心这几个就够我们用了。这里简单提一下网络数据收发的一点基础。协议栈在组织数据收发流程时需要处理好两个方面的问题：“从上倒下”，即数据发送的任务；“从下到上”，即数据接收的任务。数据发送相对接收来说要容易些，因为对于数据接收而言，网卡驱动还要明确什么样的数据该接收、什么样的不该接收等问题。protocol字段可选的四个值及其意义如下：

protocol        值        作用  
ETH_P_IP      0X0800   只接收发往目的MAC是本机的IP类型的数据帧  
ETH_P_ARP     0X0806   只接收发往目的MAC是本机的ARP类型的数据帧  
ETH_P_RARP    0X8035   只接受发往目的MAC是本机的RARP类型的数据帧  
ETH_P_ALL     0X0003   接收发往目的MAC是本机的所有类型(ip,arp,rarp)的数据帧，同时还可以接收从本机发出去的所有数据帧。在混杂模式打开的情况下，还会接收到发往目的MAC为非本地硬件地址的数据帧。

protocol字段可取的所有协议参见/usr/include/linux/if_ether.h头文件里的定义。

最后，格外需要留心一点的就是，发送数据的时候需要自己组织整个以太网数据帧。和地址相关的结构体就不能再用前面的struct sockaddr_in{}了，而是struct sockaddr_ll{}，如下：

```
    struct sockaddr_ll{
        unsigned short sll_family; /* 总是 AF_PACKET */
        unsigned short sll_protocol; /* 物理层的协议 */
        int sll_ifindex; /* 接口号 */
        unsigned short sll_hatype; /* 报头类型 */
        unsigned char sll_pkttype; /* 分组类型 */
        unsigned char sll_halen; /* 地址长度 */
        unsigned char sll_addr[8]; /* 物理层地址 */
    };
```
  sll_protocoll：取值在linux/if_ether.h中，可以指定我们所感兴趣的二层协议；

  sll_ifindex：置为0表示处理所有接口，对于单网卡的机器就不存在“所有”的概念了。如果你有多网卡，该字段的值一般通过ioctl来搞定，模板代码如下，如果我们要获取eth0接口的序号，可以使用如下代码来获取：

```
    struct  sockaddr_ll  sll;
    struct ifreq ifr;

    strcpy(ifr.ifr_name, "eth0");
    ioctl(sockfd, SIOCGIFINDEX, &ifr);
    sll.sll_ifindex = ifr.ifr_ifindex;
```
  sll_hatype：ARP硬件地址类型，定义在 linux/if_arp.h 中。 取ARPHRD_ETHER时表示为以太网。

  sll_pkttype：包含分组类型。目前，有效的分组类型有：目标地址是本地主机的分组用的 PACKET_HOST，物理层广播分组用的 PACKET_BROADCAST ，发送到一个物理层多路广播地址的分组用的 PACKET_MULTICAST，在混杂(promiscuous)模式下的设备驱动器发向其他主机的分组用的 PACKET_OTHERHOST，源于本地主机的分组被环回到分组套接口用的 PACKET_OUTGOING。这些类型只对接收到的分组有意义。

  sll_addr和sll_halen指示物理层(如以太网，802.3，802.4或802.5等)地址及其长度，严格依赖于具体的硬件设备。类似于获取接口索引sll_ifindex，要获取接口的物理地址，可以采用如下代码：

```
    struct ifreq ifr;

    strcpy(ifr.ifr_name, "eth0");
    ioctl(sockfd, SIOCGIFHWADDR, &ifr);
```
 缺省情况下，从任何接口收到的符合指定协议的所有数据报文都会被传送到原始PACKET套接字口，而使用bind系统调用并以一个sochddr_ll结构体对象将PACKET套接字与某个网络接口相绑定，就可使我们的PACKET原始套接字只接收指定接口的数据报文。 

 接下来我们简单介绍一下网卡是怎么收报的，如果你对这部分已经很了解可以跳过这部分内容。网卡从线路上收到信号流，网卡的驱动程序会去检查数据帧开始的前6个字节，即目的主机的MAC地址，如果和自己的网卡地址一致它才会接收这个帧，不符合的一般都是直接无视。然后该数据帧会被网络驱动程序分解，IP报文将通过网络协议栈，最后传送到应用程序那里。往上层传递的过程就是一个校验和“剥头”的过程，由协议栈各层去实现。

接下来我们来写个简单的抓包程序，将那些发给本机的IPv4报文全打印出来：

```
	#include <stdio.h>
	#include <stdlib.h>
	#include <errno.h>
	#include <unistd.h>
	#include <sys/socket.h>
	#include <sys/types.h>
	#include <netinet/in.h>
	#include <netinet/ip.h>
	#include <netinet/if_ether.h>

	int main(int argc, char **argv)
	{
		int sock, n;
		char buffer[2048];
		struct ethhdr *eth;
		struct iphdr *iph;

		if (0 > (sock = socket(PF_PACKET, SOCK_RAW, htons(ETH_P_IP)))) {
			perror("socket");
			exit(1);
		}

		while (1) {
			printf("=====================================\n");
			//注意：在这之前我没有调用bind函数，原因是什么呢？
			n = recvfrom(sock, buffer, 2048, 0, NULL, NULL);
			printf("%d bytes read\n", n);

			//接收到的数据帧头6字节是目的MAC地址，紧接着6字节是源MAC地址。
			eth = (struct ethhdr*)buffer;
			printf("Dest MAC addr:%02x:%02x:%02x:%02x:%02x:%02x\n",eth->h_dest[0],eth->h_dest[1],eth->h_dest[2],eth->h_dest[3],eth->h_dest[4],eth->h_dest[5]);
			printf("Source MAC addr:%02x:%02x:%02x:%02x:%02x:%02x\n",eth->h_source[0],eth->h_source[1],eth->h_source[2],eth->h_source[3],eth->h_source[4],eth->h_source[5]);

			iph = (struct iphdr*)(buffer + sizeof(struct ethhdr));
			//我们只对IPV4且没有选项字段的IPv4报文感兴趣
			if(iph->version == 4 && iph->ihl == 5){
				unsigned char *sd, *dd;
				sd = (unsigned char*)&iph->saddr;
				dd = (unsigned char*)&iph->daddr;
				printf("Source Host: %d.%d.%d.%d Dest host: %d.%d.%d.%d\n", sd[0], sd[1], sd[2], sd[3], dd[0], dd[1], dd[2], dd[3]);
			//	printf("Source host:%s\n", inet_ntoa(iph->saddr));
			//	printf("Dest host:%s\n", inet_ntoa(iph->daddr));
			}
		}
		return 0;
	}
```

构造mac源地址包，注意目标mac地址要正确，可以本机先抓包看看是什么

```
	#include <stdlib.h>
	#include <stdio.h>
	#include <errno.h>
	#include <string.h>
	#include <unistd.h>
	#include <netdb.h>
	#include <sys/socket.h>
	#include <sys/types.h>
	#include <netinet/in.h>
	#include <netinet/ip.h>
	#include <arpa/inet.h>
	#include <linux/tcp.h>

	#include <linux/if_ether.h>
	#include <linux/if_arp.h>
	#include <linux/sockios.h>

	unsigned csum_tcpudp_nofold(unsigned saddr, unsigned daddr,
				unsigned len, unsigned proto, unsigned sum)
	{
		unsigned long long s = (unsigned)sum;
		s += (unsigned)saddr;
		s += (unsigned)daddr;
		s += (proto + len) << 8;
		s += (s >> 32);
		return (unsigned)s;
	}

	unsigned short check_sum(unsigned short *addr, int len, unsigned sum)
	{
		int nleft = len;
		unsigned short *w = addr;
		unsigned short ret = 0;
		while (nleft > 1) {
			sum += *w++;
			nleft -= 2;
		}
		if (nleft == 1) {
			*(unsigned char *)(&ret) = *(unsigned char *)w;
			sum += ret;
		}

		sum = (sum>>16) + (sum&0xffff);
		sum += (sum>>16);
		ret = ~sum;
		return ret;
	}

	int change(char c)
	{
		if (c >= 'a') return c-'a'+10;
		if (c >= 'A') return c-'A'+10;
		return c-'0';
	}

	//在该函数中构造整个IP报文，最后调用sendto函数将报文发送出去
	void attack(int skfd, struct sockaddr_ll *target, char **argv)
	{
		char buf[512]={0};
		struct ethhdr *eth;
		struct ip *ip;
		struct tcphdr *tcp;
		int pks_len;
		int i;
		int op_len = 12;
		unsigned short dstport;
		dstport = atoi(argv[3]);

		//在我们TCP的报文中Data没有字段，所以整个IP报文的长度
		pks_len = sizeof(struct ethhdr) + sizeof(struct ip) + sizeof(struct tcphdr) + op_len;
		eth = (struct ethhdr *) buf;
		/*
		eth->h_dest[0] = 0x00;
		eth->h_dest[1] = 0x50;
		eth->h_dest[2] = 0x56;
		eth->h_dest[3] = 0xee;
		eth->h_dest[4] = 0x14;
		eth->h_dest[5] = 0xa6;
		*/
	
		for (i=0;i<6;i++)
			eth->h_dest[i] = change(argv[1][i*3])*16 + change(argv[1][i*3+1]);

		/*
		eth->h_source[0] = 0x00;
		eth->h_source[1] = 0x0b;
		eth->h_source[2] = 0x28;
		eth->h_source[3] = 0xd7;
		eth->h_source[4] = 0x26;
		eth->h_source[5] = 0xa6;
		*/
		eth->h_proto = ntohs(ETH_P_IP);

		//开始填充IP首部
		ip=(struct ip*)(buf + sizeof(struct ethhdr));
		ip->ip_v = IPVERSION;
		ip->ip_hl = sizeof(struct ip) >> 2;
		ip->ip_tos = 0;
		ip->ip_len = htons(pks_len - sizeof(struct ethhdr));
		ip->ip_id = 0;
		ip->ip_off = 0;
		ip->ip_ttl = MAXTTL;
		ip->ip_p = IPPROTO_TCP;
		ip->ip_sum = 0;
		ip->ip_dst.s_addr = inet_addr(argv[2]);

		//开始填充TCP首部
		srand(time(NULL));
		tcp = (struct tcphdr*)(buf + sizeof(struct ethhdr) + sizeof(struct ip));
		tcp->source = random()%50000+10000;
		tcp->dest = ntohs(dstport);
		tcp->seq = random();
		tcp->doff = (sizeof(struct tcphdr) + op_len) >> 2;
		tcp->syn = 1;
		tcp->check = 0;
		tcp->window = ntohs(14600);

		i = pks_len - op_len;
		// mss = 1460
		buf[i++] = 0x02;
		buf[i++] = 0x04;
		buf[i++] = 0x05;
		buf[i++] = 0xb4;
		// sack
		buf[i++] = 0x01;
		buf[i++] = 0x01;
		buf[i++] = 0x04;
		buf[i++] = 0x02;
		// wsscale = 7
		buf[i++] = 0x01;
		buf[i++] = 0x03;
		buf[i++] = 0x03;
		buf[i++] = 0x07;

		int T = 1;
		while(1) {
			if (T == 0) break;
			T--;
			//源地址伪造，我们随便任意生成个地址，让服务器一直等待下去
			ip->ip_src.s_addr = random();
			//自定义源地址192.168.204.136 => 0xc0a8cc88
			//ip->ip_src.s_addr = 0x8fcca8c0;
			unsigned sum = csum_tcpudp_nofold(ip->ip_src.s_addr, ip->ip_dst.s_addr, sizeof(struct tcphdr)+op_len, IPPROTO_TCP, 0);
			tcp->check = check_sum((unsigned short*)tcp, sizeof(struct tcphdr)+op_len, sum);
			ip->ip_sum = check_sum((unsigned short*)ip, sizeof(struct ip), 0);
			sendto(skfd, buf, pks_len, 0, (struct sockaddr*)target, sizeof(struct sockaddr_ll));
		}
	}

	int main(int argc, char** argv)
	{
		int skfd;
		struct sockaddr_ll target;
		struct hostent *host;
		const int on=1;

		if (argc != 4) {
			printf("Usage:%s dstmac dstip dstport\n", argv[0]);
			exit(1);
		}
		if (strlen(argv[1]) != 17) {
			printf("Usage: dstmac must be xx:xx:xx:xx:xx:xx\n");
			exit(1);
		}

		//将协议字段置为IPPROTO_TCP，来创建一个TCP的原始套接字
		if (0 > (skfd = socket(PF_PACKET, SOCK_RAW, htons(ETH_P_IP)))) {
			perror("Create Error");
			exit(1);
		}

		// mac
		bzero(&target, sizeof(struct sockaddr_ll));

		struct ifreq ifr;
		strncpy(ifr.ifr_name, "eth0", IFNAMSIZ);
		ioctl(skfd, SIOCGIFINDEX, &ifr);
		target.sll_ifindex = ifr.ifr_ifindex;
		/*
		target.sll_family = AF_PACKET;
		target.sll_protocol = ntohs(80);
		target.sll_hatype = ARPHRD_ETHER;
		target.sll_pkttype = PACKET_OTHERHOST;
		target.sll_halen = ETH_ALEN;
		memset(target.sll_addr,0,8);
		target.sll_addr[0] = 0x00;
		target.sll_addr[1] = 0x0C;
		target.sll_addr[2] = 0x29;
		target.sll_addr[3] = 0x61;
		target.sll_addr[4] = 0xB6;
		target.sll_addr[5] = 0x43;
		*/


		/*
		//http://blog.chinaunix.net/uid-305141-id-2133781.html
		struct sockaddr_ll sll;
		struct ifreq ifstruct;
		memset (&sll, 0, sizeof (sll));
		sll.sll_family = PF_PACKET;
		sll.sll_protocol = htons (ETH_P_IP);

		strcpy (ifstruct.ifr_name, "eth0");
		ioctl (skfd, SIOCGIFINDEX, &ifstruct);
		sll.sll_ifindex = ifstruct.ifr_ifindex;

		strcpy (ifstruct.ifr_name, "eth0");
		ioctl (skfd, SIOCGIFHWADDR, &ifstruct);
		memcpy (sll.sll_addr, ifstruct.ifr_ifru.ifru_hwaddr.sa_data, ETH_ALEN);
		sll.sll_halen = ETH_ALEN;

		if (bind (skfd, (struct sockaddr *) &sll, sizeof (sll)) == -1) {
			printf ("bind:   ERROR\n");
			return -1;
		}

		memset(&ifstruct, 0, sizeof(ifstruct));
		strcpy (ifstruct.ifr_name, "eth0");
		if (ioctl (skfd, SIOCGIFFLAGS, &ifstruct) == -1) {
			perror ("iotcl()\n");
			printf ("Fun:%s Line:%d\n", __func__, __LINE__);
			return -1;
		}

		ifstruct.ifr_flags |= IFF_PROMISC;

		if(ioctl(skfd, SIOCSIFFLAGS, &ifstruct) == -1) {
			perror("iotcl()\n");
			printf ("Fun:%s Line:%d\n", __func__, __LINE__);
			return -1;
		} 
	*/
		//因为只有root用户才可以play with raw socket :)
		setuid(getpid());
	//	attack(skfd, &sll, srcport);
		attack(skfd, &target, argv);
	}
```

