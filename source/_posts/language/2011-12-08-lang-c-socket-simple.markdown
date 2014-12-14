---
layout: post
title: "最简单点对点通信样例"
date: 2011-12-08 16:22:00 +0800
comments: false
categories:
- 2011
- 2011~12
- language
- language~c
tags:
- koj
---
```
	#include <stdio.h>
	#include <stdlib.h>
	#include <string.h>
	#include <errno.h>
	#include <sys/types.h>
	#include <sys/socket.h>
	#include <netinet/in.h>
	#include <unistd.h>
	#include <arpa/inet.h>
	#define MAXLINE 4096

	#include <sys/ioctl.h>
	#include <net/if.h>
	#include <net/if_arp.h>

	#include <pthread.h>

	int send_to_port = 6667;
	int self_port = 6666;

	void *get(void *data)
	{
		int listenfd, connfd;
		struct sockaddr_in servaddr;

		if( (listenfd = socket(AF_INET, SOCK_STREAM, 0)) == -1 ) {
			printf("create socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		memset(&servaddr, 0, sizeof(servaddr));
		servaddr.sin_family = AF_INET;
		servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
		servaddr.sin_port = htons(self_port);

		if( bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) == -1) {
			printf("bind socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		if( listen(listenfd, 10) == -1) {
			printf("listen socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		char buff[4096];
		int n;
		while(1)
		{
			if( (connfd = accept(listenfd, (struct sockaddr*)NULL, NULL)) == -1) {
				printf("accept socket error: %s(errno: %d)",strerror(errno),errno);
				return 0;
			}
			n = recv(connfd, buff, MAXLINE, 0);
			buff[n] = '\0';
			printf("recv msg from server: %s", buff);

			close(connfd);
		}
		return 0;
	}

	char server_addr[333];

	void *sent(void *data)
	{
		int sockfd, n;
		struct sockaddr_in servaddr;
		char sendline[4096];
	
		while(1)
		{
			fgets(sendline, 4096, stdin);
			
			if( (sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
				printf("create socket error: %s(errno: %d)\n", strerror(errno),errno);
				return 0;
			}

			memset(&servaddr, 0, sizeof(servaddr));
			servaddr.sin_family = AF_INET;
			servaddr.sin_port = htons(send_to_port);
			if( inet_pton(AF_INET, server_addr, &servaddr.sin_addr) <= 0) {
				printf("inet_pton error for %s\n", server_addr);
				return 0;
			}

			if( connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) < 0) {
				printf("connect error: %s(errno: %d)\n",strerror(errno),errno);
				return 0;
			}

			if( send(sockfd, sendline, strlen(sendline), 0) < 0) {
				printf("send msg error: %s(errno: %d)\n", strerror(errno), errno);
			}
			close(sockfd);
		}
		return 0;
	}

	int main(int argc, char** argv)
	{
		if( argc != 2) {
			printf("usage: ./client <ip_address>\n");
			return 0;
		}
		strcpy(server_addr, argv[1]);
	
		pthread_t th1, th2;
		void *retval;
		pthread_create(&th1, NULL, get, 0);
		pthread_create(&th2, NULL, sent, 0);
		pthread_join(th1, &retval);
		pthread_join(th2, &retval);
		return 0;
	}
```
编译：g++ client.cpp -o client -lpthread  
运行：./client xx.xx.xx.xx


```
	#include <stdio.h>
	#include <stdlib.h>
	#include <string.h>
	#include <errno.h>
	#include <sys/types.h>
	#include <sys/socket.h>
	#include <netinet/in.h>
	#include <unistd.h>
	#include <arpa/inet.h>
	#define MAXLINE 4096

	#include <sys/ioctl.h>
	#include <net/if.h>
	#include <net/if_arp.h>

	#include <pthread.h>

	int send_to_port = 6666;
	int self_port = 6667;

	void *get(void *data)
	{
		int listenfd, connfd;
		struct sockaddr_in servaddr;

		if( (listenfd = socket(AF_INET, SOCK_STREAM, 0)) == -1 ) {
			printf("create socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		memset(&servaddr, 0, sizeof(servaddr));
		servaddr.sin_family = AF_INET;
		servaddr.sin_addr.s_addr = htonl(INADDR_ANY);
		servaddr.sin_port = htons(self_port);

		if( bind(listenfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) == -1) {
			printf("bind socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		if( listen(listenfd, 10) == -1) {
			printf("listen socket error: %s(errno: %d)\n",strerror(errno),errno);
			return 0;
		}

		char buff[4096];
		int n;
		while(1)
		{
			if( (connfd = accept(listenfd, (struct sockaddr*)NULL, NULL)) == -1) {
				printf("accept socket error: %s(errno: %d)",strerror(errno),errno);
				return 0;
			}
			n = recv(connfd, buff, MAXLINE, 0);
			buff[n] = '\0';
			printf("recv msg from client: %s", buff);
	
			close(connfd);
		}
		return 0;
	}

	char server_addr[333];

	void *sent(void *data)
	{
		int sockfd, n;
		struct sockaddr_in servaddr;
		char sendline[4096];
	
		while(1)
		{
			fgets(sendline, 4096, stdin);

			if( (sockfd = socket(AF_INET, SOCK_STREAM, 0)) < 0) {
				printf("create socket error: %s(errno: %d)\n", strerror(errno),errno);
				return 0;
			}

			memset(&servaddr, 0, sizeof(servaddr));
			servaddr.sin_family = AF_INET;
			servaddr.sin_port = htons(send_to_port);
			if( inet_pton(AF_INET, server_addr, &servaddr.sin_addr) <= 0) {
				printf("inet_pton error for %s\n", server_addr);
				return 0;
			}

			if( connect(sockfd, (struct sockaddr*)&servaddr, sizeof(servaddr)) < 0) {
				printf("connect error: %s(errno: %d)\n",strerror(errno),errno);
				return 0;
			}

			if( send(sockfd, sendline, strlen(sendline), 0) < 0) {
				printf("send msg error: %s(errno: %d)\n", strerror(errno), errno);
			}
			close(sockfd);
		}
		return 0;
	}

	int main(int argc, char** argv)
	{
		if( argc != 2) {
			printf("usage: ./server <ip_address>\n");
			return 0;
		}
		strcpy(server_addr, argv[1]);
	
		pthread_t th1, th2;
		void *retval;
		pthread_create(&th1, NULL, get, 0);
		pthread_create(&th2, NULL, sent, 0);
		pthread_join(th1, &retval);
		pthread_join(th2, &retval);
		return 0;
	}
```
编译：g++ server.cpp -o server -lpthread  
运行：./server xx.xx.xx.xx

