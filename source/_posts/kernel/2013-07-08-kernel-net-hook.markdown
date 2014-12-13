---
layout: post
title: "Netfilter HOOK"
date: 2013-07-08 11:26:00 +0800
comments: false
categories:
- 2013
- 2013~07
- kernel
- kernel~net
tags:
---
下图是Netfilter的IPV4下的结构

![](/images/kernel/2013-07-08.jpg)

可以看到这是基于早期版本内核的，如今内核挂载点的宏定义发生了变化，从NF_IP_XXX => NF_INET_XXX

每个注册的钩子函数经过处理后都将返回下列值之一，告知Netfilter核心代码处理结果，以便对报文采取相应的动作：  
NF_ACCEPT：继续正常的报文处理；  
NF_DROP：将报文丢弃；  
NF_STOLEN：由钩子函数处理了该报文，不要再继续传送；  
NF_QUEUE：将报文入队，通常交由用户程序处理；  
NF_REPEAT：再次调用该钩子函数。  

// code
```
	#include <linux/module.h>
	#include <linux/init.h>
	#include <linux/kernel.h>
	#include <linux/net.h>
	#include <net/tcp.h>
	#include <linux/skbuff.h>
	#include <linux/netfilter.h>
	#include <linux/netfilter_ipv4.h>
	#include <net/ip_vs.h>
	#include <net/sock.h>
	#include <linux/gfp.h>
	#include <linux/kallsyms.h>
	#include <linux/version.h>

	static unsigned int test_runit(unsigned int hooknum,
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 32)
			truct sk_buff **skb,
	#else
			struct sk_buff *skb,
	#endif
			const struct net_device *in,
			const struct net_device *out,
			int (*okfn)(struct sk_buff *))
	{
		...
		return NF_ACCEPT;
	}

	static struct nf_hook_ops hook_test = {
		.hook    = test_runit,
		.owner    = THIS_MODULE,
		.pf    = PF_INET,
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 32)
		.hooknum        = NF_IP_LOCAL_OUT,
	#else
		.hooknum        = NF_INET_LOCAL_OUT,
	#endif
		.priority       = 100,
	};

	static int  __init test_start_init(void)
	{
		printk("Hi test pre\n");
		nf_register_hook(&hook_test);
		return 0;
	}

	static void __exit test_start_exit(void)
	{
		nf_unregister_hook(&hook_test);
		printk("Bye test pre\n");
	}
	module_init(test_start_init);
	module_exit(test_start_exit);
	MODULE_LICENSE("GPL");
```

