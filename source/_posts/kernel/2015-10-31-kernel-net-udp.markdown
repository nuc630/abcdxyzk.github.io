---
layout: post
title: "udp协议"
date: 2015-10-31 21:47:00 +0800
comments: false
categories:
- 2015
- 2015~10
- kernel
- kernel~net
tags:
---

UDP数据段格式：udp包头8字节
<table>
	<tr>
		<td width="200">源端口号（16）</td>
		<td width="200">目的端口号（16）</td>
	</tr>
	<tr>
		<td width="200">长度（16）</td>
		<td width="200">校验和（16）</td>
	</tr>
	<tr>
		<td width="400" colspan="2">数据（若有的话）</td>
	</tr>
</table>

长度：UDP报头 加上 UDP数据的长度。

校验和：UDP报头和UDP数据字段两者的校验和。（加伪首部）

raw socket 发送udp包

```
	//mdos.c
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
	#include <linux/udp.h>

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
		char buf[512] = {0};
		struct ip *ip;
		struct udphdr *udp;
		int ip_len;
		/*
	#define kk 16
		char ch[kk] = {0x47,0x45,0x54,0x20,0x2f,0x20,0x48,0x54,0x54,0x50,0x2f,0x31,0x2e,0x31,0x0d,0x0a};
	*/
	#define kk 168
		char ch[kk] = {
	0x47, 0x45, 0x54, 0x20, 0x2f, 0x20, 0x48, 0x54, 0x54, 0x50, 0x2f, 0x31, 0x2e, 0x31, 0x0d, 0x0a,
	0x55, 0x73, 0x65, 0x72, 0x2d, 0x41, 0x67, 0x65, 0x6e, 0x74, 0x3a, 0x20, 0x63, 0x75, 0x72, 0x6c,
	0x2f, 0x37, 0x2e, 0x31, 0x39, 0x2e, 0x37, 0x20, 0x28, 0x78, 0x38, 0x36, 0x5f, 0x36, 0x34, 0x2d,
	0x72, 0x65, 0x64, 0x68, 0x61, 0x74, 0x2d, 0x6c, 0x69, 0x6e, 0x75, 0x78, 0x2d, 0x67, 0x6e, 0x75,
	0x29, 0x20, 0x6c, 0x69, 0x62, 0x63, 0x75, 0x72, 0x6c, 0x2f, 0x37, 0x2e, 0x31, 0x39, 0x2e, 0x37,
	0x20, 0x4e, 0x53, 0x53, 0x2f, 0x33, 0x2e, 0x31, 0x35, 0x2e, 0x33, 0x20, 0x7a, 0x6c, 0x69, 0x62,
	0x2f, 0x31, 0x2e, 0x32, 0x2e, 0x33, 0x20, 0x6c, 0x69, 0x62, 0x69, 0x64, 0x6e, 0x2f, 0x31, 0x2e,
	0x31, 0x38, 0x20, 0x6c, 0x69, 0x62, 0x73, 0x73, 0x68, 0x32, 0x2f, 0x31, 0x2e, 0x34, 0x2e, 0x32,
	0x0d, 0x0a, 0x48, 0x6f, 0x73, 0x74, 0x3a, 0x20, 0x31, 0x39, 0x32, 0x2e, 0x31, 0x36, 0x38, 0x2e,
	0x31, 0x30, 0x39, 0x2e, 0x32, 0x32, 0x32, 0x0d, 0x0a, 0x41, 0x63, 0x63, 0x65, 0x70, 0x74, 0x3a,
	0x20, 0x2a, 0x2f, 0x2a, 0x0d, 0x0a, 0x0d, 0x0a
	};

		int data_len = kk;

		//在我们UDP的报文中Data没有字段，所以整个IP报文的长度
		ip_len = sizeof(struct ip) + sizeof(struct udphdr) + data_len;

		//开始填充IP首部
		ip=(struct ip*)buf;
		ip->ip_v = IPVERSION;
		ip->ip_hl = sizeof(struct ip)>>2;
		ip->ip_tos = 0;
		ip->ip_len = htons(ip_len);
		ip->ip_id = 0;
		ip->ip_off = 0;
		ip->ip_ttl = MAXTTL;
		ip->ip_p = IPPROTO_UDP;
		ip->ip_sum = 0;
		ip->ip_dst = target->sin_addr;

		//开始填充UDP首部
		udp = (struct udphdr*)(buf+sizeof(struct ip));
		udp->source = htons(srcport);
		udp->dest = target->sin_port;
		udp->check = 0;
		udp->len = htons(data_len + sizeof(struct udphdr));

		int i = ip_len - data_len;
		int j = i;
		for (;i<ip_len;i++)
			buf[i] = ch[i-j];
		/*
		int s = 'A';
		buf[i++] = 0x00 + s;
		buf[i++] = 0x01 + s;
		buf[i++] = 0x02 + s;
		buf[i++] = 0x03 + s;
		buf[i++] = 0x04 + s;
		buf[i++] = 0x05 + s;
		buf[i++] = 0x06 + s;
		buf[i++] = 0x07 + s;
		buf[i++] = 0x08 + s;
		buf[i++] = 0x09 + s;
	*/
		printf("%lx %d %d\n", ip->ip_dst, udp->dest, udp->source);
		int T = 1;
		while(1) {
			if (T == 0) break;
			T--;
			//printf("%d\n", T);
			//udp->seq = random();
		        //源地址伪造，我们随便任意生成个地址，让服务器一直等待下去
		        //ip->ip_src.s_addr = random();
			//自定义源地址192.168.204.136 = 0xc0a8cc88; 反转赋值
		        ip->ip_src.s_addr = 0xf86da8c0;
			unsigned sum = csum_tcpudp_nofold(ip->ip_src.s_addr, ip->ip_dst.s_addr, sizeof(struct udphdr)+data_len, IPPROTO_UDP, 0);
		        udp->check = check_sum((unsigned short*)udp, sizeof(struct udphdr)+data_len, sum);
			ip->ip_sum = check_sum((unsigned short*)ip, sizeof(struct ip), 0);
			printf("s1 s2 %lx %lx\n", udp->check, ip->ip_sum);
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
		        printf("Usage:%s target dstport srcport\n", argv[0]);
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

		//将协议字段置为IPPROTO_UDP，来创建一个UDP的原始套接字
		if (0 > (skfd = socket(AF_INET, SOCK_RAW, IPPROTO_UDP))) {
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

