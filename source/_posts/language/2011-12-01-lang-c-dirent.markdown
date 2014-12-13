---
layout: post
title: "遍历文件函数 dirent"
date: 2011-12-01 01:34:00 +0800
comments: false
categories:
- 2011
- 2011~12
- language
- language~c
tags:
- koj
- judge
---
引用头文件#include<dirent.h>  
结构体说明  
```
	struct dirent {　　
		long d_ino; /* inode number 索引节点号 */　　
		off_t d_off; /* offset to this dirent 在目录文件中的偏移 */　　
		unsigned short d_reclen; /* length of this d_name 文件名长 */　　
		unsigned char d_type; /* the type of d_name 文件类型 */　　
		char d_name [NAME_MAX+1]; /* file name (null-terminated) 文件名，最长255字符 */　　
	}
```
相关函数  
opendir()，readdir()，closedir();

使用实例
```
	#include <stdio.h>
	#include <string.h>
	#include <dirent.h>
	#include <sys/stat.h>

	int main()
	{
		struct dirent* ent = NULL;
		DIR *pDir;
		pDir=opendir(".");

		while ((ent=readdir(pDir)) != NULL)
		{
			//printf("%d %d\n", ent->d_reclen, ent->d_type);
			if (ent->d_type==8)
			printf("filename: %s\n", ent->d_name);
		}
		return 0;
	}
```

