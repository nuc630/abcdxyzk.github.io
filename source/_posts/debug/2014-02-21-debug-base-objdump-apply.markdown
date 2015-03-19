---
layout: post
title: "独立的调试符号文件"
date: 2014-02-21 14:13:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~base
tags:
---
  这种将可执行程序与调试符号分离的方案好处多多。一方面，缩减了可执行程序的文件大小，在一定程度上提高了程序的执行性能，另一方面，对应的调试符号文件也方便了一些不时之需。本文就来看一下与此相关的两个问题。  
 
#### 一 如何给应用程序创建对应的调试符号文件？    
这很简单，看个演示实例。有代码如下：  
```
[root@lenky gdb]# cat t.c
#include <stdio.h> 
int main(int argc, char *argv[])
{
	printf("Hello world!\n");
	return 0;
}
```
依次执行命令如下：
```
[root@lenky gdb]# ls -l
total 4
-rw-r--r--. 1 root root 103 Mar 20 07:52 t.c
[root@lenky gdb]# gcc -g t.c -o t
[root@lenky gdb]# ls -l
total 12
-rwxr-xr-x. 1 root root 7717 Mar 20 07:58 t
-rw-r--r--. 1 root root  103 Mar 20 07:52 t.c
[root@lenky gdb]# objcopy --only-keep-debug t t.debuginfo
[root@lenky gdb]# objcopy --strip-debug t
[root@lenky gdb]# objcopy --add-gnu-debuglink=t.debuginfo t
[root@lenky gdb]# ls -l
total 20
-rwxr-xr-x. 1 root root 6470 Mar 20 07:58 t
-rw-r--r--. 1 root root  103 Mar 20 07:52 t.c
-rwxr-xr-x. 1 root root 6109 Mar 20 07:58 t.debuginfo
```
OK，可执行程序t和对应的调试符号文件t.debuginfo就生成了。    

几条命令，给以分别解释一下：    
1. gcc -g t.c -o t    
  这个无需多说，值得注意的是，-g和-O2可以同时使用。    
2. objcopy –only-keep-debug t t.debuginfo    
  将可执行程序文件t内的与调试相关的信息拷贝到文件t.debuginfo内。也可以这样：  
cp t t.debuginfo  
strip --only-keep-debug t.debuginfo  
3. objcopy –strip-debug t    
  删除可执行程序文件t内的调试相关信息。也可以直接使用strip命令，不过strip命令会把symtab也删除掉，导致在没有debuginfo文件的情况下，打印堆栈信息会受到影响，比如变得不那么清晰。    
4. objcopy –add-gnu-debuglink=t.debuginfo t    
  在可执行程序文件t内添加一个名为.gnu_debuglink的section段，该段内包含有debuginfo文件的name名称和checksum校验和，以确保后续在进行实际调试时，可执行程序和对应的调试符号文件是一致的。  

#### 二 如何使用gdb调试带有调试符号文件的应用程序？    
  其实想想也知道，这只需解决一个问题，即如何把应用程序与调试符号文件关联起来。    
  gdb会按照一定的规则去搜索对应路径，找寻应用程序的调试符号文件，比如gdb会自动查找可执行程序所在目录下的.debug文件夹：  
```
[root@lenky ~]# pwd
/root
[root@lenky ~]# gdb /home/work/gdb/t -q
Reading symbols from /home/work/gdb/t...Reading symbols from /home/work/gdb/.debug/t.debug...done.
done.
(gdb)
```
把调试符号文件放到同一个目录也可以：
```
[root@lenky ~]# rm -fr /tmp/.debug/
[root@lenky ~]# cp /home/work/gdb/.debug/t.debug /tmp/
[root@lenky ~]# gdb /tmp/t -q
Reading symbols from /tmp/t...Reading symbols from /tmp/t.debug...done.
done.
(gdb)
```

#### 下面再介绍另外几种主动设置方法：    
##### 1，通过gdb启动参数-s指定：  
```
[root@lenky ~]# gdb -s /home/work/gdb/.debug/t.debug -e /tmp/t -q
Reading symbols from /home/work/gdb/.debug/t.debug...done.
(gdb)
```
注意：可执行程序必须通过-e指定，否则貌似gdb会拿它覆盖-s参数，比如如下：
```
[root@lenky ~]# gdb -s /home/work/gdb/.debug/t.debug /tmp/t -q
Reading symbols from /tmp/t...Missing separate debuginfo for /tmp/t
Try: yum --disablerepo='*' --enablerepo='*-debuginfo' install /usr/lib/debug/.build-id/01/f1df7f4971caacd934aca9523c4e4b5ae95332.debug
(no debugging symbols found)...done.
(gdb)
```
可以看到，gdb直接尝试从文件/tmp/t内读取符号了，而不是文件t.debug。

##### 2，利用gdb的命令设置搜索路径：set debug-file-directory directories    
  这是gdb官方文档提到的，可以设置搜索路径的命令，但是貌似并没有起作用，或者是我漏掉了什么。具体不说了，请看参考5。  

#### 参考：    
1. How to generate gcc debug symbol outside the build target?    
   http://stackoverflow.com/questions/866721/how-to-generate-gcc-debug-symbol-outside-the-build-target    
2. Creating separate debug info    
   https://blogs.oracle.com/dbx/entry/creating_separate_debug_info    
3. man objcopy    
4. .gnu_debuglink or Debugging system libraries with source code    
   https://blogs.oracle.com/dbx/entry/gnu_debuglink_or_debugging_system    
5. 18.2 Debugging Information in Separate Files    
   http://sourceware.org/gdb/onlinedocs/gdb/Separate-Debug-Files.html    
6. http://www.technovelty.org/code/separate-debug-info.html  


```
	#!/bin/sh
	# 可以改成：将要提取的文件加到参数中

	#set -x

	objcopyout()
	{
	#       if [ -f `file -N $1 | sed -n -e 's/^\(.*\):[   ]*.*ELF.*, not stripped/\1/p'` ]; then
		    val=`objdump -s -j .gnu_debuglink "$1" | grep 'Contents of section .gnu_debuglink:'`
		    if [ -z "$val" ]; then
		            #debug_out=".debug/$1.debug".`date +%s`
		            tmp_name=`echo "$1" | awk -F/ '{ print $NF}'`
		            debug_out=".debug/$tmp_name.debug".`date +%s`
		            objcopy --only-keep-debug "$1" "$debug_out"
		            objcopy --strip-debug "$1"
		            objcopy --add-gnu-debuglink="$debug_out" "$1"
		    fi
	#       objdump -s -j .gnu_debuglink "$1"
	}

	mkdir -p .debug/

	while [ $# -gt 0 ]; do
		    if [ -f "$1" ]; then
		            objcopyout "$1"
		    fi
		    shift
	done

	#find . -name *.ko -print |
	#while read f
	#do
	#       objcopyout "$f"
	#done
```

