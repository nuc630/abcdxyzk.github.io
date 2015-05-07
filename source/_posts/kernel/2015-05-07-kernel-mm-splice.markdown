---
layout: post
title: "Linux 中的零拷贝技术 splice"
date: 2015-05-07 15:26:00 +0800
comments: false
categories:
- 2015
- 2015~05
- kernel
- kernel~mm
tags:
---
http://hi.baidu.com/renguihuashi/item/ef71f8e28d74f5f22b09a415

linux下如何实现文件对拷呢？

最容易想到的方法就是，申请一份内存buf，read 源文件一段数据到buf，然后将此buf write到目标文件，示例代码如下：
```
	char buf[max_read];
	off_t size = stat_buf.st_size;
	while ( off_in < size ) {
		int len = size - off_in > max_read ? max_read : size - off_in;
		len = read(f_in, buf, len);
		off_in += len;
		write(f_out, buf, len);
	}
```

还有一种大家都知道的方式，就是通过mmap实现，示例代码如下：
```
	size_t filesize = stat_buf.st_size;
	source = mmap(0, filesize, PROT_READ, MAP_SHARED, f_in, 0);
	target = mmap(0, filesize, PROT_WRITE, MAP_SHARED, f_out, 0);
	memcpy(target, source, filesize);
```
因为mmap不需要内核态和用户态的内存拷贝，效率大大提高。

本文还想介绍另外一种，是今天无意google到的，就是如标题所述，基于splice实现，splice是Linux 2.6.17新加入的系统调用，官方文档的描述是，用于在两个文件间移动数据，而无需内核态和用户态的内存拷贝，但需要借助管道（pipe）实现。大概原理就是通过pipe buffer实现一组内核内存页（pages of kernel memory）的引用计数指针（reference-counted pointers），数据拷贝过程中并不真正拷贝数据，而是创建一个新的指向内存页的指针。也就是说拷贝过程实质是指针的拷贝。示例代码如下：
```
	int pipefd[2];
	pipe( pipefd );
	int max_read = 4096;
	off_t size = stat_buf.st_size;
	while ( off_in < size ) {
		int len = size - off_in > max_read ? max_read : size - off_in;
		len = splice(f_in, &off_in, pipefd[1], NULL, len, SPLICE_F_MORE |SPLICE_F_MOVE);
		splice(pipefd[0], NULL, f_out, &off_out, len, SPLICE_F_MORE |SPLICE_F_MOVE);
	}
```
使用splice一定要注意，因为其借助管道实现，而管道有众所周知的空间限制问题，超过了限制就会hang住，所以每次写入管道的数据量好严格控制，保守的建议值是一个内存页大小，即4k。另外，off_in和off_out传递的是指针，其值splice会做一定变动，使用时应注意。

splice kernel bug: https://git.kernel.org/cgit/linux/kernel/git/torvalds/linux.git/commit/?id=baff42ab1494528907bf4d5870359e31711746ae

---------------
http://ogris.de/howtos/splice.html

http://blog.csdn.net/eroswang/article/details/1999034

http://stackoverflow.com/questions/1580923/how-can-i-use-linuxs-splice-function-to-copy-a-file-to-another-file

```
   EINVAL Target  file  system  doesn't  support  splicing; target file is
          opened in append mode; neither of the descriptors  refers  to  a
          pipe; or offset given for non-seekable device.
```

---------------

#### file to file sample
```
	#define _GNU_SOURCE
	#include <fcntl.h>
	#include <stdio.h>
	#include <unistd.h>
	#include <errno.h>
	#include <string.h>
	#include <time.h>

	int main(int argc, char **argv)
	{
		int pipefd[2];
		int result;
		FILE *in_file;
		FILE *out_file;
		char buff[65537];

		if (argc != 3) {
			printf("usage: ./client infile outfile\n");
			exit(0);
		}
		result = pipe(pipefd);

		in_file = fopen(argv[1], "rb");
		out_file = fopen(argv[2], "wb");

		off_t off_in = 0, off_out = 0;
		int len = 1024*1024*30;
		while (len > 0) {
			int size = 65536;
			if (len < size) size = len;
			len -= size;

			result = splice(fileno(in_file), &off_in, pipefd[1], NULL, size, SPLICE_F_MORE | SPLICE_F_MOVE);
			result = splice(pipefd[0], NULL, fileno(out_file), &off_out, size, SPLICE_F_MORE | SPLICE_F_MOVE);
			//printf("%d\n", result);

	//	      read(fileno(in_file), buff, size);
	//	      write(fileno(out_file), buff, size);
		}
		close(pipefd[0]);
		close(pipefd[1]);
		fclose(in_file);
		fclose(out_file);

		return 0;
	}
```

#### more sample

[splice sample](/download/kernel/splice_sample.tar.gz)  

like:  
file to socket  
socket to file  
socket to socket  

