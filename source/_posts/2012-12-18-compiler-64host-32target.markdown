---
layout: post
title: "在64位主机上编译产生32位的目标代码"
date: 2012-12-18 14:55:00 +0800
comments: false
categories:
- 2012
- 2012~12
- compiler
- compiler~base
tags:
---
  64位平台跟32位平台有很大的不同，包括参数传递方式，指令集都有很大的变化，那怎么能够让它正常运行呢？利用 gcc的-m32参数编译产生32位的目标代码，而不是64位的目标代码，因为32位的目标代码可以运行在64位的主机上。
```
$ gcc -m32 manydots.s -o manydots
$ ./manydots 
How many dots do you want to see? 10
..........
$ file manydots
manydots: ELF 32-bit LSB executable, Intel 80386, version 1 (SYSV), dynamically linked (uses shared libs), for GNU/Linux 2.6.8, not stripped
```
  可以看到，这样就okay了。  
  实际上，我们还可以分步来做：先汇编，后链接。这样可以减少目标代码的大小，先看看原来的大小。
```
$ wc -c manydots
6495 manydots
```
我们分步汇编、链接：
```
// 这个时候是需要一个默认的_start入口的，如果不指定，会默认设置一个程序入口地址，因为这个时候没有人给我们设置一个真正的入口_start了。
$ sed -i -e "s/main/_start/g" manydots.s 
$ as --32 manydots.s -o manydots.o
$ ld -m elf_i386 manydots.o -o manydots
$ wc -c manydots
1026 manydots
$ echo "6495-1026" | bc 
5469
$ ./manydots 
How many dots do you want to see? 10
..........
```
  可以发现，这样也可以正常工作，不过目标减少了5469个字节。为什么会有这样的效果呢？资料[2]给出了详细的解释，如果感兴趣，可以研究一下。  
  对了，“as --32 manydots.s -o manydots.o”可以直接用“$ gcc -m32 -c manydots.s -o manydots.o” 来做，他们两个实际上做了同一个事情，你可以通过gcc的--verbose查看：  
```
$ gcc --verbose -m32 -c manydots.s -o manydots.o
Using built-in specs.
Target: x86_64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Debian 4.3.1-9' --with-bugurl=file:///usr/share/doc/gcc-4.3/README.Bugs --enable-languages=c,c++,fortran,objc,obj-c++ --prefix=/usr --enable-shared --with-system-zlib --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --enable-nls --with-gxx-include-dir=/usr/include/c++/4.3 --program-suffix=-4.3 --enable-clocale=gnu --enable-libstdcxx-debug --enable-objc-gc --enable-mpfr --enable-cld --enable-checking=release --build=x86_64-linux-gnu --host=x86_64-linux-gnu --target=x86_64-linux-gnu
Thread model: posix
gcc version 4.3.1 (Debian 4.3.1-9) 
COLLECT_GCC_OPTIONS='-v' '-m32' '-c' '-o' 'manydots.o' '-mtune=generic'
 as -V -Qy --32 -o manydots.o manydots.s
GNU assembler version 2.18.0 (x86_64-linux-gnu) using BFD version (GNU Binutils for Debian) 2.18.0.20080103
COMPILER_PATH=/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/
LIBRARY_PATH=/usr/lib/gcc/x86_64-linux-gnu/4.3.1/32/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/32/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/../../../../lib32/:/lib/../lib32/:/usr/lib/../lib32/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/:/usr/lib/gcc/x86_64-linux-gnu/4.3.1/../../../:/lib/:/usr/lib/
COLLECT_GCC_OPTIONS='-v' '-m32' '-c' '-o' 'manydots.o' '-mtune=generic'
```

#### 最后总结一下，在64位主机上编译产生32位目标代码的办法：
##### 一、办法一：直接通过gcc汇编、链接
1、确保不要有重复的_start入口，把_start替换成main  
2、用gcc加上-m32参数进行汇编和链接  
##### 二、办法二：分步汇编、链接
1、汇编的时候，用gcc加上-m32参数或者用as加上--32参数。  
2、在链接的时候，用ld加上-m elf_i386参数。  

