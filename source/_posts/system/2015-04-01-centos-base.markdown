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


```
	lsattr /etc/passwd /etc/group /etc/shadow /etc/gshadow
	chattr -i /etc/passwd /etc/group /etc/shadow /etc/gshadow
```

-------------

binkernel.spec
```
	%pre
	mkdir -p /usr/local/kernel/etc/
	echo "version=%{version}-%{release}" > /usr/local/kernel/etc/install.conf

	%post
	/sbin/new-kernel-pkg --package kernel --mkinitrd --depmod --install 2.6.32-358.6.1.ws5.b.5.1.11t25

	%preun
	rm -rf /usr/local/kernel/

	%postun
	/sbin/new-kernel-pkg  --remove 2.6.32-358.6.1.ws5.b.5.1.11t25
```

-------------

更改 bash_history 默认历史记录

```
	vim ~/.bashrc

	# 忽略[连续]重复命令
	HISTCONTROL=ignoredups

	# 清除重复命令
	# HISTCONTROL=erasedups

	# 忽略特定命令
	HISTIGNORE="[   ]*:ls:ll:cd:vi:pwd:sync:exit:history*"

	# 命令历史文件大小10M
	HISTFILESIZE=1000000000

	# 保存历史命令条数10W
	HISTSIZE=1000000

	以上配置可以通过 set | grep HIST 查看可选项.


	多终端追加
	当打开多个终端，关闭其中一个终端时会覆盖其他终端的命令历史，这里我们采用追加的方式避免命令历史文件.bash_history 文件被覆盖。

	shopt -s histappend

	更多 shopt 可选项可以通过 echo $SHELLOPTS 命令查看。
```

-----------

关闭CentOS6启动进度条，显示详细自检信息。vim /boot/grub/grub.conf，将"rhgb"和 "quiet"去掉，保存即可

-----------

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
开启：
```
	chkconfig iptables on
	chkconfig ip6tables on
```
关闭：
```
	chkconfig iptables off
	chkconfig ip6tables off
```

2） 即时生效，重启后复原  
开启：
```
	service iptables start
	service ip6tables start
```
关闭：
```
	service iptables stop
	service ip6tables stop
```

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

