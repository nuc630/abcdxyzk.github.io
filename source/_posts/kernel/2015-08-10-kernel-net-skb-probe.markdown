---
layout: post
title: "监控skb释放"
date: 2015-08-10 15:53:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~net
tags:
---
#### skb_probe.c

```
	#include <linux/kernel.h>
	#include <linux/module.h>
	#include <linux/kprobes.h>

	#include <linux/net.h>
	#include <linux/socket.h>
	#include <linux/sockios.h>
	#include <linux/in.h>
	#include <linux/inet.h>
	#include <linux/inetdevice.h>
	#include <linux/netdevice.h>
	#include <linux/etherdevice.h>

	#include <net/snmp.h>
	#include <net/ip.h>
	#include <net/protocol.h>
	#include <net/route.h>
	#include <linux/skbuff.h>
	#include <net/sock.h>
	#include <net/arp.h>
	#include <net/icmp.h>
	#include <net/raw.h>
	#include <net/checksum.h>
	#include <linux/netfilter_ipv4.h>
	#include <net/xfrm.h>
	#include <linux/mroute.h>
	#include <linux/netlink.h>

	int count = 0;

	struct ctl_table_header *ctl_header = NULL;
	static struct ctl_table debug_table[] = {	
		{
			.procname       = "pr_count",
			.data           = &count,
			.maxlen         = sizeof(count),
			.mode           = 0644,
			.proc_handler   = &proc_dointvec, },
		{ },
	};

	static struct ctl_table ipv4_dir_table[] = {
		{
			.procname    = "ipv4",
			.mode        = 0555,
			.child       = debug_table, },
		{ },
	};

	static ctl_table net_dir_table[] = {
		{ 
			.procname    = "net",
			.mode        = 0555,
			.child       	= ipv4_dir_table, },
		{ },
	};

	int dump_stack_skb(void)
	{
		if (count > 0) {
			dump_stack();
			count--;
		}
		return 0;
	}

	/*
	// ip_rcv call skb_orphan, skb_orphan will reset skb->destructor
	int j_ip_rcv(struct sk_buff *skb, struct net_device *dev, struct packet_type *pt, struct net_device *orig_dev)
	{
		skb->destructor = (void*)dump_stack_skb;
		jprobe_return();
		return 0;
	}

	static struct jprobe jp_ip_rcv = {
		.entry = j_ip_rcv,
		.kp = {
			.symbol_name	= "ip_rcv",
		}
	};
	*/

	int j_ip_rcv_finish(struct sk_buff *skb)
	{
		skb->destructor = (void*)dump_stack_skb;
		jprobe_return();
		return 0;
	}

	static struct jprobe jp_ip_rcv_finish = {
		.entry = j_ip_rcv_finish,
		.kp = {
			.symbol_name	= "ip_rcv_finish",
		}
	};


	static int __init kprobe_init(void)
	{
		int ret;
		ctl_header = register_sysctl_table(net_dir_table);
		if(!ctl_header){
			printk(KERN_ERR"SYNPROXY: sp_sysctl_init() calls failed.");
			return -1;
		}

	//	ret = register_jprobe(&jp_ip_rcv);
		ret = register_jprobe(&jp_ip_rcv_finish);
		if (ret < 0) {
			unregister_sysctl_table(ctl_header);
			printk(KERN_INFO "register_jprobe failed, returned %d\n", ret);
			return -1;
		}
	//	printk(KERN_INFO "Planted jprobe at %p, handler addr %p\n", jp_ip_rcv.kp.addr, jp_ip_rcv.entry);
		printk(KERN_INFO "Planted jprobe at %p, handler addr %p\n", jp_ip_rcv_finish.kp.addr, jp_ip_rcv_finish.entry);
		return 0;
	}

	static void __exit kprobe_exit(void)
	{
		if (ctl_header)
			unregister_sysctl_table(ctl_header);

	//	unregister_jprobe(&jp_ip_rcv);
	//	printk(KERN_INFO "kprobe at %p unregistered\n", jp_ip_rcv.kp.addr);
		unregister_jprobe(&jp_ip_rcv_finish);
		printk(KERN_INFO "kprobe at %p unregistered\n", jp_ip_rcv_finish.kp.addr);
	}

	module_init(kprobe_init)
	module_exit(kprobe_exit)
	MODULE_LICENSE("GPL");
```
#### Makefile
```
	obj-m := skb_probe.o

	KDIR:=/lib/modules/`uname -r`/build
	PWD=$(shell pwd)

	KBUILD_FLAGS += -w

	all:
		make -C $(KDIR) M=$(PWD) modules
	clean:
		make -C $(KDIR) M=$(PWD) clean
```

#### 运行

打印10次释放

```
	echo 10 > /proc/sys/net/ipv4/pr_count
```

