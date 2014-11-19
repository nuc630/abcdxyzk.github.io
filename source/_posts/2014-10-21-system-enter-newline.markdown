---
layout: post
title: "\\r\\n,\\n,\\r简介"
date: 2014-10-21 10:06:00 +0800
comments: true
categories:
- 2014
- 2014~10
- system
- system~base
tags:
- system
---
'\r'是回车，前者使光标到行首，（carriage return）  
'\n'是换行，后者使光标下移一格，（line feed）

\r 是回车，return  
\n 是换行，newline

^M 是ascii中的'\r', 回车符，是16进制的0x0D，八进制的015，十进制的13  
^M在vi编辑器中可以使用Ctrl+ v + m三个键打出来

对于换行这个动作，unix下一般只有一个0x0A表示换行("\n")，windows下一般都是0x0D和0x0A两个字符("\r\n")，苹果机(MAC OS系统)则采用回车符CR表示下一行(\r)  
>	Unix系统里，每行结尾只有“<换行>”，即“\n”；  
>	Windows系统里面，每行结尾是“<回车><换行>”，即“\r\n”；  
>	Mac系统里，每行结尾是“<回车>”,即“\r”。

一个直接后果是，Unix/Mac系统下的文件在Windows里打开的话，所有文字会变成一行；而Windows里的文件在Unix下打开的话，在每行的结尾会多车一个^M字符。
Dos和windows采用回车+换行CR/LF表示下一行,即^M$（$不是换行符的表示，换行符没有表示出来，$是文本结束EOF的表示）
而UNIX/Linux采用换行符LF表示下一行，即\n  
苹果机(MAC OS系统)则采用回车符CR表示下一行，即\r  

CR用符号'\r'表示, 十进制ASCII代码是13, 十六进制代码为0x0D;  
LF使用'\n'符号表示, ASCII代码是10, 十六制为0x0A. 所以Windows平台上换行在文本文件中是使用 0d 0a 两个字节表示, 而UNIX和苹果平台上换行则是使用0a或0d一个字节表示.

由于dos风格的换行使用\r\n，把这样的文件上传到unix，有些版本的vi不能识别\r，所以vi显示时在行尾会出现^M出来，但是有些就能识别\r\n，正常显示回车换行。

dos to unix，去掉^M
```
tr -d "\015" <myfile.txt > myfile_new.txt
tr -d "\r" <myfile.txt > myfile_new.txt
```
