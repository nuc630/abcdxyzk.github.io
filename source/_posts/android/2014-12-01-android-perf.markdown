---
layout: post
title: "编译Android的perf"
date: 2014-12-01 12:34:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~base
tags:
---
#### 1 编译elfutils
[elfutils源码](https://android.googlesource.com/platform/external/elfutils.git/+/android-4.4.4_r2.0.1)  
```
cp -r /home/kk/andr-perf/android-ndk-r10c/platforms/android-21/arch-arm arch-arm-21-ok
```

```
	cd elfutils
	./configure --host=arm-none-linux-gnueabi

	sed -i -e 's/^CC = gcc/CC = $(CROSS_COMPILE)gcc/g' *Makefile
	sed -i -e 's/^CC = gcc/CC = $(CROSS_COMPILE)gcc/g' */Makefile
	sed -i -e 's/^AR = ar/AR = $(CROSS_COMPILE)ar/g' */Makefile

	Makefile
	-SUBDIRS = config m4 lib libelf libebl libdwfl libdw libcpu libasm backends \
	+SUBDIRS = config libelf
	+#SUBDIRS = config m4 lib libelf libebl libdwfl libdw libcpu libasm backends \

	libelf/Makefile
	-AM_CFLAGS = $(am__append_1) -Wall -Wshadow -Werror \
	+AM_CFLAGS = $(am__append_1) -Wall -Wshadow \

	-               -Wl,--soname,$@.$(VERSION),-z,-defs,-z,relro $(libelf_so_LDLIBS)
	+               -Wl,--soname,$@.$(VERSION),-defs,-z,relro $(libelf_so_LDLIBS)

	bionic-fixup/AndroidFixup.h
	-static inline char *stpcpy(char *dst, const char *src)
	+static inline char *stpcpy_noneed(char *dst, const char *src)

	host-darwin-fixup/AndroidFixup.h
	-static inline size_t strnlen (const char *__string, size_t __maxlen)
	+static inline size_t strnlen_noneed (const char *__string, size_t __maxlen)

	libelf/elf32_updatefile.c
	libelf/elf_begin.c
	libelf/elf_getarsym.c
	#include "bionic-fixup/AndroidFixup.h"
	#include "host-darwin-fixup/AndroidFixup.h"

	libelf/elf_error.c
	#include "host-darwin-fixup/AndroidFixup.h"

	export NDK_SYSROOT=/home/kk/andr-perf/arch-arm-21-ok
	export NDK_TOOLCHAIN=/home/kk/andr-perf/android-ndk-r10c/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-
	make ARCH=arm CROSS_COMPILE=${NDK_TOOLCHAIN} CFLAGS="--sysroot=${NDK_SYSROOT} -I`pwd`/bionic-fixup"
```

#### 2 编译内核
```
make goldfish_defconfig

Makefile:
 195 ARCH            ?= arm
 196 CROSS_COMPILE   ?= /home/kk/android/gcc-arm-none-eabi-4_8-2014q3/bin/arm-none-eabi-

make
```

#### 3 编译perf，perf要放在goldfish-android-goldfish-3.4/tools/
```
	cp /home/kk/android/android-ndk-r10c/platforms/android-19/arch-arm/usr/include/asm/page.h /home/kk/andr-perf/arch-arm-21-ok/usr/include/asm

	pwd
	/home/kk/andr-perf/elfutils-android-4.4.4_r2.0.1/libelf
	cp elf.h gelf.h libelf.h /home/kk/andr-perf/arch-arm-21-ok/usr/include/
	cp libelf.a libelf.so /home/kk/andr-perf/arch-arm-21-ok/usr/lib/

	pwd
	/home/kk/andr-perf/goldfish-android-goldfish-3.4/tools/linux-tools-perf-android-4.4.4_r2.0.1
	cp /home/kk/andr-perf/goldfish-android-goldfish-3.4/lib/rbtree.o util/
	```

	Makefile
	-EXTLIBS = -lpthread -lrt -lelf -lm
	+EXTLIBS = -lelf -lm

	-               msg := $(error No gnu/libc-version.h found, please install glibc-dev[el]/glibc-static);
	+#              msg := $(error No gnu/libc-version.h found, please install glibc-dev[el]/glibc-static);


	-$(OUTPUT)util/rbtree.o: ../../lib/rbtree.c $(OUTPUT)PERF-CFLAGS
	-       $(QUIET_CC)$(CC) -o $@ -c $(ALL_CFLAGS) -DETC_PERFCONFIG='"$(ETC_PERFCONFIG_SQ)"' $<
	+#$(OUTPUT)util/rbtree.o: ../../lib/rbtree.c $(OUTPUT)PERF-CFLAGS
	+#      $(QUIET_CC)$(CC) -o $@ -c $(ALL_CFLAGS) -DETC_PERFCONFIG='"$(ETC_PERFCONFIG_SQ)"' $<


	perf.h
	+#define __used__
	+#define __force


	util/util.h
	+#include <linux/types_ws.h>  // 他会找到util/include/linux/types.h，导致没有include<linux/types.h>，会报没有__be32等错误


	pwd
	/home/kk/andr-perf/arch-arm-21-ok
	cp ./usr/include/linux/types.h ./usr/include/linux/types_ws.h

	/home/kk/andr-perf/arch-arm-21-ok/usr/include/linux/tcp.h 删掉下面这部分
	 enum {
	  TCP_FLAG_CWR = __constant_cpu_to_be32(0x00800000),
	  TCP_FLAG_ECE = __constant_cpu_to_be32(0x00400000),
	  TCP_FLAG_URG = __constant_cpu_to_be32(0x00200000),
	/* WARNING: DO NOT EDIT, AUTO-GENERATED CODE - SEE TOP FOR INSTRUCTIONS */
	  TCP_FLAG_ACK = __constant_cpu_to_be32(0x00100000),
	  TCP_FLAG_PSH = __constant_cpu_to_be32(0x00080000),
	  TCP_FLAG_RST = __constant_cpu_to_be32(0x00040000),
	  TCP_FLAG_SYN = __constant_cpu_to_be32(0x00020000),
	/* WARNING: DO NOT EDIT, AUTO-GENERATED CODE - SEE TOP FOR INSTRUCTIONS */
	  TCP_FLAG_FIN = __constant_cpu_to_be32(0x00010000),
	  TCP_RESERVED_BITS = __constant_cpu_to_be32(0x0F000000),
	  TCP_DATA_OFFSET = __constant_cpu_to_be32(0xF0000000)
	 };


	export NDK_SYSROOT=/home/kk/andr-perf/arch-arm-21-ok
	export NDK_TOOLCHAIN=/home/kk/andr-perf/android-ndk-r10c/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-

	// 
	make ARCH=arm CROSS_COMPILE=${NDK_TOOLCHAIN} CFLAGS="--sysroot=${NDK_SYSROOT} -I`pwd`" LDFLAGS+=-static
```


