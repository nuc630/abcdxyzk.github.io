---
layout: post
title: "SystemTap---嵌入C代码"
date: 2015-06-01 15:36:00 +0800
comments: false
categories:
- 2015
- 2015~06
- debug
- debug~systemtap
tags:
---

* 访问参数的值是以STAP_ARG_+参数名的形式，返回值`STAP_RETVALUE=xxx`，这种方式是最新版本的SystemTap中的方式。1.7及更早的版本是通过THIS->+参数名的方式, 返回值`THIS->__returnval=xxx`

-----------

http://www.4byte.cn/learning/53860.html

  SystemTap支持guru模式，通过-g选项来以这种模式执行SystemTap脚本。在guru模式下，嵌入的C代码在“%{"和“%}"标记之间，这些代码会原封不动地放到生成的模块中。嵌入的C代码不仅可以作为函数体，还可以出现在SystemTap描述中（例如函数等），示例如下：
```
	%{
		#include <linux/in.h>
		#include <linux/ip.h>
	%} /* <-- top level */

	function read_iphdr:long(skb:long)
	%{
		struct iphdr *iph = ip_hdr((struct sk_buff *)STAP_ARG_skb);
		STAP_RETVALUE = (long)iph;
	%}

	/* Determines whether an IP packet is TCP, based on the iphdr: */
	function is_tcp_packet:long(iphdr)
	{
		protocol = @cast(iphdr, "iphdr")->protocol
		return (protocol == %{ IPPROTO_TCP %}) /* <-- expression */
	}

	probe begin {
		printf("SystemTap start!\n");
	}

	probe kernel.function("ip_local_deliver") {
		iph = read_iphdr(pointer_arg(1));
		printf("tcp packet ? %s\n", is_tcp_packet(iph) ? "yes" : "no");
	}
```

在这里read_iphdr函数就是使用嵌入的C代码作为函数体，is_tcp_packet中是作为systemtap辅助函数中的一部分。

在使用嵌入C代码作为函数体的函数中，访问参数的值是以STAP_ARG_+参数名的形式，这种方式是最新版本的SystemTap中的方式。1.7及更早的版本是通过THIS->+参数名的方式。CentOS6.4中的SystemTap版本是1.8，所以你如果在SystemTap脚本中仍然使用老的访问方式会报错。同样，最新的设置返回值的方式是STAP_RETVALUE，1.7及更早的版本是THIS->__retvalue。

由于在guru模式下，SystemTap对嵌入的C代码没有做任何的处理，所以如果在C代码中出现异常的访问或者其他错误，就会导致内核crash。不过SystemTap提供了kread宏来安全地访问指针，如下所示：

```
	struct net_device *dev;
	char *name;
	dev = kread(&(skb->dev));
	name = kread(&(dev->name));
```

还有一点要特别注意，所有的SystemTap函数和probe都是在关闭中断下执行，所以在所有嵌入的C代码中都不能睡眠！


