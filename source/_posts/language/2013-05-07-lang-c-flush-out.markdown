---
layout: post
title: "C语言输出缓冲区函数说明"
date: 2013-05-07 18:15:00 +0800
comments: false
categories:
- 2013
- 2013~05
- language
- language~c
tags:
---
```
	#include <stdio.h>
	#include <unistd.h>

	int main(void)
	{
		int i = 0;
		while(1) {
			printf("sleeping %d", i++); //(1)
			fflush(stdout);
			sleep(1);
		}
		return 0;
	}
```
#### 1
printf将"sleeping %d"输出到标准输出文件的缓冲区中(缓冲区在内存上)，fflush(stdout)将缓冲区中的内容强制刷新到，并将其中的内容输出到显示器上("\n"回车换行 == fflush(stdout)+换行)
```
	fflush()
	buffer(In memroy) -----------> hard disk/monitor
```
#### 2
有三个流(stream)是自动打开的， 相应的FILE结构指针为stdin、stdout、stderr，与之对应的文件描述符是：STDIN_FILENO、STDOUT_FILENO、STDERR_FILENO。

#### 流缓冲的属性：
缓冲区类型有：全缓冲(大部分缓冲都是这类型)、行缓冲(例如stdio,stdout)、无缓冲(例如stderr)。  
关于全缓冲，例如普通的文件操作，进行fputs、fprintf操作后，数据并没有立即写入磁盘文件中，当fflush或fclose文件时，数据才真正写入。  
可以用以下函数设置流的缓冲类型：
```
	void setvbuf()  
	void setbuf()  
	void setbuffer()  
	void setlinebuf()
```

#### 3
fflush() 是把 FILE *里的缓冲区(位于用户态进程空间)刷新到内核中  
fsync() -是把内核中对应的缓冲(是在 vfs 层的缓冲)刷新到硬盘中

#### 4
在Linux的标准函数库中，有一套称作“高级I/O”的函数，我们熟知的printf()、fopen()、fread()、fwrite()都在此 列，它们也被称作“缓冲I/O（buffered I/O）”，每次写文件的时候，也仅仅是写入内存中的缓冲区，等满足了一定的条件（达到一定数量，或遇到特定字符，如换行符\n和文件结束符EOF），再 将缓冲区中的内容一次性写入文件，这样就大大增加了文件读写的速度。

-----------------------------------------------------------------
  The three types of buffering available are unbuffered, block buffered, and line buffered. When an output stream is unbuffered, information appears on the destination file or terminal as soon as written; when it is block buffered many characters are saved up and written as a block; when it is line buffered characters are saved up until a newline is output or input is read from any stream attached to a terminal device (typically stdin). The function fflush(3) may be used to force the block out early. (See fclose(3).) Normally all files are block buffered. When the first I/O operation occurs on a file, malloc(3) is called, and a buffer is obtained. If a stream refers to a terminal (as stdout normally does) it is line buffered. The standard error
stream stderr is always unbuffered by default.

  一般来说，block buffered的效率高些，将多次的操作合并成一次操作。先在标准库里缓存一部分，直到该缓冲区满了，或者程序显示的调用fflush时，将进行更新操作。而setbuf 则可以设置该缓冲区的大小。

##### setbuf()
```
	#include <stdio.h>
	void setbuf(FILE *stream, char *buf);
```
这个函数应该必须在如何输出被写到该文件之前调用。一般放在main里靠前面的语句！但是setbuf有个经典的错误，man手册上也提到了，c陷阱和缺陷上也提到了
You must make sure that both buf and the space it points to still exist by the time stream is closed, which also happens at program termination. For example, the following is illegal:
```
	#include <stdio.h>
	int main()
	{
		char buf[BUFSIZ];
		setbuf(stdin, buf);
		printf("Hello, world!\n");
		return 0;
	}
```
这个程序是错误的。buf缓冲区最后一次清空应该在main函数结束之后，程序交回控制给操作系统之前C运行库所必须进行的清理工作的一部分，但是此时 buf字符数组已经释放。修改的方法是将buf设置为static，或者全局变量； 或者调用malloc来动态申请内存。
```
	char * malloc();
	setbuf(stdout,malloc(BUFSIZE));
```
这里不需要判断malloc的返回值，如果malloc调用失败，将返回一个null指针，setbuf的第二个参数可以是null,此时不进行缓冲！

##### fflush()
fflush函数则刷新缓冲区，将缓冲区上的内容更新到文件里。
```
	#include <stdio.h>
	int fflush(FILE *stream);
```
  The function fflush forces a write of all user-space buffered data for the given output or update stream via the stream underlying write function. The open status of the stream is unaffected. If the stream argument is NULL, fflush flushes all open output streams.

但是fflush仅仅刷新C库里的缓冲。其他的一些数据的刷新需要调用fsync或者sync!

  Note that fflush() only flushes the user space buffers provided by the C library. To ensure that the data is physically stored on disk the kernel buffers must be flushed too, e.g. with sync(2) or fsync(2).

##### fsync()和sync()
  fsync和sync最终将缓冲的数据更新到文件里。
```
	#include <unistd.h>
	int fsync(int fd);
```
  fsync copies all in-core parts of a file to disk, and waits until the device reports that all parts are on stable storage. It also updates metadata stat information. It does not necessarily ensure that the entry in the directory containing the file has also reached disk. For that an explicit fsync on the file descriptor of the directory is also needed.

  同步命令sync就直接调用了sync函数来更新磁盘上的缓冲！

