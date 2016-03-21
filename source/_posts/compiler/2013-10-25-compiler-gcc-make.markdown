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

ftp://ftp.gnu.org/pub/gnu/gcc/gcc-4.6.2/gcc-4.6.2.tar.gz

ftp://gcc.gnu.org/pub/gcc/infrastructure/gmp-4.3.2.tar.bz2

ftp://gcc.gnu.org/pub/gcc/infrastructure/mpfr-2.4.2.tar.bz2

ftp://gcc.gnu.org/pub/gcc/infrastructure/mpc-0.8.1.tar.gz

### 安装依赖
```
	gcc configure: error: Building GCC requires GMP 4.2+, MPFR 2.3.1+ and MPC 0.8.0+
```

从错误中可以看出：GCC编译需要GMP， MPFR， MPC这三个库（有的系统已经安装了就没有这个提示，我的没有安装），有两种安装方法（建议第二种）：

#### 手动安装

我使用的版本为gmp-4.3.2，mpfr-2.4.2和mpc-0.8.1，在 ftp://gcc.gnu.org/pub/gcc/infrastructure/ 下载，根据提示的顺序分别安装GMP，MPFR和MPC（mpfr依赖gmp，mpc依赖gmp和mpfr），这里全部自己指定了安装目录，如果没有指定则默认分装在在/usr/include、/usr/lib和/usr/share，管理起来不方便，比如想卸载的时候还得一个个去找：

```
	安装gmp:  ./configure --prefix=/usr/local/gmp-4.3.2; make install
	安装mpfr: ./configure --prefix=/usr/local/mpfr-2.4.2 --with-gmp=/usr/local/gmp-4.3.2/; make install
	安装mpc:  ./configure --prefix=/usr/local/mpc-0.8.1 --with-gmp=/usr/local/gmp-4.3.2/ --with-mpfr=/usr/local/mpfr-2.4.2/; make install
```

#### gcc自带脚本安装

gcc源码包中自带了一个gcc依赖库安装脚本download_prerequisites，位置在gcc源码目录中的contrib/download_prerequisites，因此只需要进入该目录，直接运行脚本安装即可：./download_prerequisites
```
	MPFR=mpfr-2.4.2
	GMP=gmp-4.3.2
	MPC=mpc-0.8.1

	wget ftp://gcc.gnu.org/pub/gcc/infrastructure/$MPFR.tar.bz2 || exit 1
	tar xjf $MPFR.tar.bz2 || exit 1
	ln -sf $MPFR mpfr || exit 1

	wget ftp://gcc.gnu.org/pub/gcc/infrastructure/$GMP.tar.bz2 || exit 1
	tar xjf $GMP.tar.bz2  || exit 1
	ln -sf $GMP gmp || exit 1

	wget ftp://gcc.gnu.org/pub/gcc/infrastructure/$MPC.tar.gz || exit 1
	tar xzf $MPC.tar.gz || exit 1
	ln -sf $MPC mpc || exit 1

	rm $MPFR.tar.bz2 $GMP.tar.bz2 $MPC.tar.gz || exit 1
```

#### 配置环境变量

我这里指定了安装位置，如果没有指定则这几个库的默认位置是/usr/local/include和/usr/local/lib，不管有没有指定GCC编译时都可能会找不到这三个库，需要确认库位置是否在环境变量LD_LIBRARY_PATH中，查看环境变量内容可以用命令
```
	echo $LD_LIBRARY_PATH
```
设置该环境变量命令如下：

```
	指定安装：export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/gmp-4.3.2/lib:/usr/local/mpfr-2.4.2/lib:/usr/local/mpc-0.8.1/lib

	默认安装：export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/lib
```

不指定环境变量会出错：
```
	configure: error: cannot compute suffix of object files: cannot compile
```

#### 2.编译gcc
##### 1）建立一个objdir来存放目标文件 然后进入该文件夹输入
```
	/home/wulei/sourcecode/gcc-4.6.2/configure --prefix=/usr/local/gcc-4.6.2 --enable-threads=posix --disable-checking --disable-multilib --enable-languages=c --with-gmp=/usr/local/gmp-4.3.2/ --with-mpfr=/usr/local/mpfr-2.4.2/ --with-mpc=/usr/local/mpc-0.8.1/
	最终用：../gcc-4.6.2/configure --prefix=/usr/gcc-4.6.9 --enable-threads=posix --disable-checking --disable-multilib --enable-languages=c --with-gmp=/usr/gmp-4.3.2 --with-mpfr=/usr/mpfr-2.4.2 --with-mpc=/usr/mpc-0.8.1
```

##### 2）
```
	make
	make check
	make install
```

##### 错误1
```
	/usr/bin/ld: .libs/expat_justparse_interface.o: relocation R_X86_64_32 against `a local symbol' can not be used when making a shared object; recompile with -fPIC
	.libs/expat_justparse_interface.o: could not read symbols: Bad value
```
解决
```
	make CXXFLAGS=-fPIC CFLAGS=-fPIC
```

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
```
	/home/wulei/sourcecode/gcc-4.6.2/host-i686-pc-linux-gnu/gcc/cc1: error while loading shared libraries: libmpfr.so.1: cannot open shared object file: No such file or directory
```

#### 原因是因为linux在make的时候没有自动寻找新加入的库所以要用命令加入  
```
	export LD_LIBRARY_PATH=/usr/local/mpc-0.8.1/lib:/usr/local/mpfr-2.4.2/lib:/usr/local/gmp-4.3.2/lib
```

#### Makefile:161: ../.././gcc/libgcc.mvars: No such file or directory  
编译gcc时，需要注意一个原则：不要再gcc的源码中直接执行./configure、make、make install等命令，需要在源码目录下另外新建一个目录，在新建的目录中执行以上命令。

