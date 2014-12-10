---
layout: post
title: "数据交换sysctl + 定时器（code）"
date: 2013-07-05 15:35:00 +0800
comments: false
categories:
- 2013
- 2013~07
- kernel
- kernel~base
tags:
---
```
	#include <linux/module.h>
	#include <linux/kernel.h>
	#include <linux/init.h>
	#include <linux/types.h>

	#include <linux/sysctl.h>
	#include <linux/timer.h>

	int value;

	static struct ctl_table debug_table[] = {
		{
			.ctl_name       = CTL_UNNUMBERED,
			.procname       = "value",
			.data           = &value,
			.maxlen         = sizeof(value),
			.mode           = 0644,
			.proc_handler   = &proc_dointvec, },
		{ },
	};

	static struct ctl_table ws_dir_table[] = {
		{
			.ctl_name       = CTL_UNNUMBERED,
			.procname        = "debug",
			.mode            = 0555,
			.child           = debug_table, },
		{ },
	};

	static struct ctl_table ipv4_dir_table[] = {
		{
			.ctl_name       = NET_IPV4,
			.procname    = "ipv4",
			.mode        = 0555,
			.child       = ws_dir_table, },
		{ },
	};

	static ctl_table net_dir_table[] = {
		{
			.ctl_name       = CTL_NET,
			.procname    = "net",
			.mode        = 0555,
			.child           = ipv4_dir_table, },
		{ },
	};

	struct timer_list timer_last_stat;
	static void output_value(unsigned long data)
	{
		printk("value = %d\n", value);
		mod_timer(&timer_last_stat, jiffies+HZ*5);
	}

	struct ctl_table_header *ctl_header = NULL;
	static int __init file_test_init(void)
	{
		printk("sysctl test init\n");
		value = 111;
		ctl_header= register_sysctl_table (net_dir_table, 0);
		if(!ctl_header){
			printk(KERN_ERR"SYNPROXY: sp_sysctl_init() calls failed.");
			return -1;
		}
		setup_timer(&timer_last_stat, output_value, 0);
		mod_timer(&timer_last_stat, jiffies+HZ*5);
		return 0;
	}

	static void __exit file_test_exit(void)
	{
		if (ctl_header)
			unregister_sysctl_table(ctl_header);
		del_timer(&timer_last_stat);
		printk("sysctl test exit\n");
	}

	module_init(file_test_init);
	module_exit(file_test_exit);

	MODULE_LICENSE("GPL");
```

---------------

```
$ dmesg
...
value = 111
$ echo 123 > /proc/sys/net/ipv4/debug/value
$ dmesg
...
value = 111
value = 123
```
