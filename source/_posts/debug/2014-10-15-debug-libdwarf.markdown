---
layout: post
title: "libdwarf 安装使用"
date: 2014-10-15 18:16:00 +0800
comments: false
categories:
- 2014
- 2014~10
- debug
- debug~dwarf
tags:
---
下载[http://www.prevanders.net/dwarf.html](http://www.prevanders.net/dwarf.html)

依赖[http://directory.fsf.org/wiki/Libelf](http://directory.fsf.org/wiki/Libelf)

dwarf格式文档[http://www.dwarfstd.org/Home.php](http://www.dwarfstd.org/Home.php)

#### 动态编译
直接./configure，make就好。
```
	./configure
	make
```

#### 静态编译
比较新的版本要替换 optind 和 opterr ，因为会和libc.a冲突
```
	find . -name '*.[c|h]' -exec sed -i -e 's/optind/optind_kk/g' {} \;
	find . -name '*.[c|h]' -exec sed -i -e 's/opterr/opterr_kk/g' {} \;
```

先动态编译，为了生成libdwarf/libdwarf.a
```
	./configure
	make
```

静态编译
```
	rm -rf dwarfdump/dwarfdump
	make CFLAGS+="-static -I`pwd`/libdwarf -I`pwd`/dwarfdump" LDFLAGS+="-static -L`pwd`/libdwarf -ldwarf -lelf"
```

使用
```
	./dwarfdump/dwarfdump -Wc -S match=dev_queue_xmit /tmp/vmlinux
```
获取vmlinux中dev_queue_xmit函数的.debug信息

