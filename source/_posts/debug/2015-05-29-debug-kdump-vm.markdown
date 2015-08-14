---
layout: post
title: "VMware 'Host SMBus controller not enabled!'"
date: 2015-05-29 14:21:00 +0800
comments: false
categories:
- 2015
- 2015~05
- debug
- debug~kdump、crash
tags:
---
https://www.centos.bz/faq/111/

Ubuntu/CentOS guest instances in VMware sometimes come up with the boot error message:
```
	piix4_smbus 0000:00:007.3: Host SMBus controller not enabled!
```

This error is being caused because VMware doesn’t actually provide that level interface for CPU access, but Ubuntu try to load the kernel module anyway.

How to fix it:   
在虚拟机中
```
	sudo vim /etc/modprobe.d/blacklist.conf
```
add the line:
```
	blacklist i2c-piix4
```

reboot


-------------------

似乎这个错误在centos6 + 3.10* 的内核，有时kdump不起作用。
