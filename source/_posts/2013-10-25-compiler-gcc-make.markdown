---
layout: post
title: "gcc编译安装"
date: 2013-10-25 09:42:00 +0800
comments: false
categories:
- 2013
- 2013~10
- compiler
- compiler~base
tags:
---
##### gcc编译安装过程
#### 1.先安装三个库 gmp mprc mpc 这三个库的源码要到官网去下载 
##### 1）安装gmp：
  首先建立源码同级目录 gmp-build,输入命令，第一次编译不通过，发现缺少一个叫m4的东西 于是就用apt-get下载了一个，继续编译，没有报错。make的时候出现大量信息并且生成一些文件在当前文件夹下，之后用make check检查一下，最后用make install安装

##### 2）安装mpfr：
  首先建立源码文件夹同级目录mpfr-build  
然后进入该目录输入../mpfr-2.4.2/configure --prefix=/usr/local/mpfr-2.4.2 --with-gmp=/usr/local/gmp-4.3.2  
然后  
 make  
 make check  
 make install  
##### 3）安装mpc
类似与上面 不过要把依赖关系包含进去具体命令如下  
../mpc-0.8.1/configure --prefix=/usr/local/mpc-0.8.1 --with-gmp=/usr/local/gmp-4.3.2 --with-mpfr=/usr/local/mpfr-2.4.2
然后同样是
  make  
  make check  
  make install  

#### 2.编译gcc
##### 1）建立一个objdir来存放目标文件 然后进入该文件夹输入
 /home/wulei/sourcecode/gcc-4.6.2/configure --prefix=/usr/local/gcc-4.6.2 --enable-threads=posix --disable-checking --disable-multilib --enable-languages=c --with-gmp=/usr/local/gmp-4.3.2/ --with-mpfr=/usr/local/mpfr-2.4.2/ --with-mpc=/usr/local/mpc-0.8.1/
最终用：../gcc-4.6.2/configure --prefix=/usr/gcc-4.6.9 --enable-threads=posix --disable-checking --disable-multilib --enable-languages=c --with-gmp=/usr/gmp-4.3.2 --with-mpfr=/usr/mpfr-2.4.2 --with-mpc=/usr/mpc-0.8.1
##### 2）
  make
  make check
  make install

##### 出现问题make的时候提示如下：
```
Checking for suffix of object files... configure: error: in `/home/wulei/sourcecode/gcc-4.6.2/i686-pc-linux-gnu/libgcc':
configure: error: cannot compute suffix of object files: cannot compile
See `config.log' for more details.
make[2]: *** [configure-stage1-target-libgcc] 错误 1
make[2]:正在离开目录 `/home/wulei/sourcecode/gcc-4.6.2'
make[1]: *** [stage1-bubble] 错误 2
make[1]:正在离开目录 `/home/wulei/sourcecode/gcc-4.6.2'
make: *** [all] 错误 2
```
于是 进入/home/wulei/sourcecode/gcc-4.6.2/i686-pc-linux-gnu/libgcc查看这个路径下的config.log  
发现如下的错误提示：  
/home/wulei/sourcecode/gcc-4.6.2/host-i686-pc-linux-gnu/gcc/cc1: error while loading shared libraries: libmpfr.so.1: cannot open shared object file: No such file or directory

#### 原因是因为linux在make的时候没有自动寻找新加入的库所以要用命令加入  
export LD_LIBRARY_PATH=/usr/local/mpc-0.8.1/lib:/usr/local/mpfr-2.4.2/lib:/usr/local/gmp-4.3.2/lib

#### Makefile:161: ../.././gcc/libgcc.mvars: No such file or directory  
编译gcc时，需要注意一个原则：不要再gcc的源码中直接执行./configure、make、make install等命令，需要在源码目录下另外新建一个目录，在新建的目录中执行以上命令。

