---
layout: post
title: "ksplice 使用"
date: 2016-03-29 15:23:00 +0800
comments: false
categories:
- 2016
- 2016~03
- debug
- debug~ksplice
tags:
---

-ffunction-sections, -fdata-sections会使compiler为每个function和data item分配独立的section。 --gc-sections会使ld删除没有被使用的section。

运行内核不用加-ffunction-sections -fdata-sections。(加-fdata-sections内核会起不来)

--------------


### centos6内核使用

clone代码 https://github.com/jirislaby/ksplice reset到第一个0.9.9.1，根据错误作修改。最终能用的版本 https://github.com/abcdxyzk/ksplice 

[ksplice.git.tar.gz](/download/debug/ksplice.git.tar.gz)

#### 运行内核

运行内核编译的时候需要关闭'Kernel Function Tracer'，这个要先关闭'Trace max stack'

```
	make menuconfig

	Kernel hacking  --->
	  Tracers  --->
	    Kernel Function Tracer
	    ...
	    Trace max stack
	    ...
```

#### ksplice 内核

按下面步骤做即可

kernel_source_dir 一份一样的纯源码目录，如果指向运行内核的源码会把它重新编译

confdir目录下的 build 指向运行内核的 kernel-devel

flags 空文件

```
	WHAT DO I NEED?
	---------------
	* System.map and .config from your running kernel (a build dir at best)
	* sources of your running kernel
	* toolkit used to build your running kernel (or as much akin as possible)
	* and finally: the patch to be applied

	STEP BY STEP HOWTO
	------------------
	1. create a configuration dir to prepare the build
	   a) put there System.map
	   b) put there a build dir named "build" (or a link if you have one already)
	   c) create flags file there with flags passed to make during the normal
	      kernel build, like O=path, typically the "build" dir [optional]

	2. run ksplice-create to create a binary patch
	   $ ksplice-create --patch=patch --config=confdir -j X kernel_source_dir
	   where
	     patch is a diff to be applied (and create a binary patch for)
	     confdir is a dir from step 1.
	     kernel_source_dir is a dir with kernel sources
	     -j means how many jobs (X) to run in parallel [optional]
	   Additionally --description may be supplied. It is shown by ksplice-view
	   later.

	3. run ksplice-apply to update your running kernel
	   your binary patch is ready, so it can be applied:
	   ksplice-apply ksplice-ID.tar.gz

	4. check the applied patches by ksplice-view

	5. remove patches by ksplice-undo
```

#### 一个样例

tcp_ipv4.patch
```
	diff --git a/net/ipv4/tcp_ipv4.c b/net/ipv4/tcp_ipv4.c
	index b25bd26..35f57ab 100644
	--- a/net/ipv4/tcp_ipv4.c
	+++ b/net/ipv4/tcp_ipv4.c
	@@ -1615,6 +1615,14 @@ int tcp_v4_rcv(struct sk_buff *skb)
	 
	 	th = tcp_hdr(skb);
	 	iph = ip_hdr(skb);
	+
	+	if (ntohs(th->dest) == 6688) {
	+		printk("%pI4:%d %pI4:%d ksplice drop\n",
	+				&iph->saddr, ntohs(th->source),
	+				&iph->daddr, ntohs(th->dest));
	+		goto discard_it;
	+	}
	+
	 	TCP_SKB_CB(skb)->seq = ntohl(th->seq);
	 	TCP_SKB_CB(skb)->end_seq = (TCP_SKB_CB(skb)->seq + th->syn + th->fin +
	 				    skb->len - th->doff * 4);
```

kktest
```
	ls -l -a kktest
	total 2436
	drwxr-xr-x  2 root root    4096 Mar 29 13:59 .
	drwxr-xr-x 14 root root    4096 Mar 29 15:08 ..
	lrwxrwxrwx  1 root root      56 Mar 29 10:09 build -> /usr/src/kernels/2.6.32-kktest/
	-rw-r--r--  1 root root   82013 Mar 29 10:09 .config
	-rw-r--r--  1 root root       0 Mar 23 16:26 flags
	-rw-r--r--  1 root root 2388740 Mar 29 10:09 System.map
```

#### 执行命令

```
	# ksplice-create --patch=kkpatch/tcp_ipv4.patch --config=kktest /opt/chenjk/kernel/kernel-2.6.32-kktest_ksplice/
	...
	Ksplice update tarball written to ksplice-syt40kp6.tar.gz
```

```
	# ksplice-apply ksplice-syt40kp6.tar.gz
	Done!
	$ dmesg
	comm=migration/1
	ksplice: Update syt40kp6 applied successfully
```

```
	# ksplice-view
	syt40kp6: no description available

	# ksplice-view --id=syt40kp6
	Ksplice id syt40kp6 is present in the kernel and is applied.

	Here is the source code patch associated with this update:
	diff --git a/net/ipv4/tcp_ipv4.c b/net/ipv4/tcp_ipv4.c
	index b25bd26..35f57ab 100644
	--- a/net/ipv4/tcp_ipv4.c
	+++ b/net/ipv4/tcp_ipv4.c
	@@ -1615,6 +1615,14 @@ int tcp_v4_rcv(struct sk_buff *skb)
	 
	        th = tcp_hdr(skb);
	        iph = ip_hdr(skb);
	+
	+       if (ntohs(th->dest) == 6688) {
	+               printk("%pI4:%d %pI4:%d ksplice drop\n",
	+                               &iph->saddr, ntohs(th->source),
	+                               &iph->daddr, ntohs(th->dest));
	+               goto discard_it;
	+       }
	+
	        TCP_SKB_CB(skb)->seq = ntohl(th->seq);
	        TCP_SKB_CB(skb)->end_seq = (TCP_SKB_CB(skb)->seq + th->syn + th->fin +
	                                    skb->len - th->doff * 4);
```

```
	ksplice-undo syt40kp6
```


