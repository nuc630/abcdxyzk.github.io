---
layout: post
title: "CentOS各种设置"
date: 2015-04-01 23:39:00 +0800
comments: false
categories:
- 2015
- 2015~04
- system
- system~centos
tags:
---

vmware虚拟机mkinitrd提示no module ehci-hcd 错误的话，加：
```
 --builtin=ehci-hcd --builtin=ohci-hcd --builtin=uhci-hcd 
```

-----------

CentOS6.0 下默认开selinux时出现httpd 报“SELinux policy enabled; httpd running as context unconfined_u:system”的解决方案
```
	yum install policycoreutils-python

	# To allow httpd to use nfs dirs in CentOS-6
	setsebool -P httpd_use_nfs 1
	setsebool -P httpd_enable_homedirs 1
```

-----------

#### CentOS 关闭防火墙
1） 永久性生效，重启后不会复原  
开启： chkconfig iptables on  
关闭： chkconfig iptables off  

2） 即时生效，重启后复原  
开启： service iptables start  
关闭： service iptables stop  

------------

#### CentOS安装软件：/lib/ld-linux.so.2: bad ELF interpreter 解决
是因为64位系统中安装了32位程序, 解决方法：
```
	yum install glibc.i686
```

其他包
```
	yum install libstdc++.i686
```

-------------

#### gcc, c++
```
	yum install glibc
	yum install glibc-devel
	yum install gcc-c++
	yum install libstdc++
```

