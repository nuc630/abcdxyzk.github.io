---
layout: post
title: "linux c libcurl的简单使用"
date: 2015-09-30 15:25:00 +0800
comments: false
categories:
- 2015
- 2015~09
- language
- language~c
tags:
---
http://blog.chinaunix.net/uid-23095063-id-163160.html

```
	yum install libcurl libcurl-devel
```

```
	#include <curl/curl.h>
	#include <stdio.h>
	#include <string.h>

	CURL *curl;
	CURLcode res;

	size_t write_data(void *ptr, size_t size, size_t nmemb, void *stream)
	{
		if (strlen((char *)stream) + strlen((char *)ptr) > 999999) return 0;
		strcat(stream, (char *)ptr);
	//	printf("%s\n", ptr);
		return nmemb;
	}

	char *down_file(char *url)
	{
		static char str[1000000];
		int ret;

		struct curl_slist *slist = NULL;
		slist = curl_slist_append(slist, "Connection: Keep-Alive"); //http长连接
		curl_easy_setopt(curl, CURLOPT_HTTPHEADER, slist);

		strcpy(str, "");

		curl_easy_setopt(curl, CURLOPT_VERBOSE, 1); // 显示详细信息

		curl_easy_setopt(curl, CURLOPT_URL, url); //设置下载地址
		curl_easy_setopt(curl, CURLOPT_TIMEOUT, 3); //设置超时时间

		curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, write_data); //设置写数据的函数
		curl_easy_setopt(curl, CURLOPT_WRITEDATA, str); //设置写数据的变量

		res = curl_easy_perform(curl); //执行下载

		str[999999] = '\0';
		if (CURLE_OK != res) //判断是否下载成功
			return NULL;

		return str;
	}

	int main()
	{
		char url[200];
		curl = curl_easy_init(); //对curl进行初始化

		char *result;
		printf("Please Input a url: ");
		while (scanf("%s", url) != EOF) {
			result = down_file(url);
			if (result)
				puts(result);
			else
				puts("Get Error!");
			printf("\nPlease Input a url: ");
		}
		curl_easy_cleanup(curl); //释放curl资源

		return 0;
	}
```

