---
layout: post
title: "字节序和比特序"
date: 2013-06-20 18:23:00 +0800
comments: false
categories:
- 2013
- 2013~06
- language
- language~c
tags:
---

字节序和比特序，因为比特序对所有代码（包括汇编）是透明的，所以对于小端系统，有说是用大端比特序，也有说是用小端比特序。  
下面是copy一部分觉得靠谱的内容：  
大小端
我们对"endianness"这个名词估计都很熟悉了。它首先被Danny Cohen于1980引入，用来表述计算机系统表示多字节整数的方式。
endianness分为两种：大端和小端。(从字节序的角度来看)大端方式是将整数中最高位byte存放在最低地址中。而小端方式则相反，将整数中的最高位byte存放在最高地址中。
对于某个确定的计算机系统，比特序通常与字节序保持一致。换言之，在大端系统中，每个byte中最高位bit存放在内存最低位；在小端系统中，最低位bit存放在内存最低位。
正如大部分人是按照从左至右的顺序书写数字，一个多字节整数的内存布局也应该遵循同样的方式，即从左至右为数值的最高位至最低位。正如我们在下面的例子中所看到的，这是书写整数最清晰的方式。

根据上述规则，我们按以下方式分别在大端和小端系统中值为0x0a0b0c0d的整数。
在大端系统中书写整数：
```
	byte  addr	0	1	2	3
	bit offset  01234567 01234567 01234567 01234567

	    binary  00001010 00001011 00001100 00001101
	      hex      0a       0b       0c       0d
```

在小端系统中书写整数(认真看)
```
	byte  addr	0	1	2	3
	bit offset  01234567 01234567 01234567 01234567

	    binary  10110000 00110000 11010000 01010000
	      hex      d0       c0       b0       a0
```

说明字节序：
```
	#include <stdio.h>  
	int main (void)  
	{  
		union b  
		{  
			short k;  //测试环境short占2字节  
			char i[2];  //测试环境char占1字节  
		}*s,a;  
		s=&a;  
		s->i[0]=0x41;  
		s->i[1]=0x52;  
		printf("%x\n",s->k);  
		return 0;  
	}
``` 
输出：5241

-------

self code:
```
	#include <stdio.h>
	union W
	{
		struct Y
		{
			unsigned int s1:4;
			unsigned int s2:8;
			unsigned int s3:20;
		} y;
		unsigned int c;
	} w;

	union V 
	{
		struct X
		{
			unsigned char s1:3;
			unsigned char s2:3;
			unsigned char s3:2;
		} x;
		unsigned char c;
	} v;

	int main()
	{
		w.c = 0x12345678;
		printf("%x %x %x %x\n", w.c, w.y.s1, w.y.s2, w.y.s3); 

		v.c = 100;
		printf("%d %x %x %x\n", v.c, v.x.s1, v.x.s2, v.x.s3); 
		return 0;
	}
```

输出：  
12345678 8 67 12345  
100 4 4 1  

100 = （01100100）2  
因为字节序是小端的所以第一行输出说明：位域变量从左到右分配位，所以第二行的输出的位域变量也应该从左到右分配位。所以  
100 = 001 001 10  （小端比特序二进制）  
对应:  s1  s2  s3  （位域变量从左到右分配位）  

符合。

