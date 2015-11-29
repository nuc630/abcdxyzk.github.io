---
layout: post
title: "编译I9507V内核"
date: 2015-1-3 14:52:00 +0800
comments: false
categories:
- 2015
- 2015~01
- android
- android~I9507V
tags:
---
源码地址 http://opensource.samsung.com/reception/receptionSub.do?method=sub&sub=F&searchValue=9507

好像三星android4.3版本后的bootloader会检测是否三星自编译内核，不是的会开机提示一下，不影响正常使用。

按照README_Kernel.txt的做。

内核中说明是用4.7编译器，但是4.7编译出来的装上去会挂，不知道为什么。  
但是换成4.6编译器就没问题。

```
	make VARIANT_DEFCONFIG=jftdd_eur_defconfig jf_defconfig SELINUX_DEFCONFIG=selinux_defconfig
```

最后作成boot.img
```
	mkbootimg --kernel zImage --ramdisk boot.img-ramdisk.cpio.gz --base 80200000 --ramdisk_offset 1FF8000 --pagesize 2048 --cmdline "console=null androidboot.hardware=qcom user_debug=31 msm_rtb.filter=0x3F ehci-hcd.park=3 maxcpus=4" -o boot.img

	tar cf boot.img.tar boot.img
	用odin3.10，选择AP项刷入
```

#### 修改

```
	diff --git a/Makefile b/Makefile
	index 16603ac..6d2b29f 100755
	--- a/Makefile
	+++ b/Makefile
	@@ -193,7 +193,7 @@ SUBARCH := $(shell uname -m | sed -e s/i.86/i386/ -e s/sun4u/sparc64/ \
	 # Note: Some architectures assign CROSS_COMPILE in their arch/*/Makefile
	 export KBUILD_BUILDHOST := $(SUBARCH)
	 ARCH		?=arm
	-CROSS_COMPILE	?=/opt/toolchains/arm-eabi-4.7/bin/arm-eabi-
	+CROSS_COMPILE	?=/home/kk/android/gcc-arm-none-eabi-4_6-2012q4/bin/arm-none-eabi-
	 
	 # Architecture as present in compile.h
	 UTS_MACHINE 	:= $(ARCH)
	diff --git a/arch/arm/configs/jftdd_eur_defconfig b/arch/arm/configs/jftdd_eur_defconfig
	index 389a204..2c53b92 100755
	--- a/arch/arm/configs/jftdd_eur_defconfig
	+++ b/arch/arm/configs/jftdd_eur_defconfig
	@@ -2,3 +2,5 @@ CONFIG_MACH_JF_EUR=y
	 CONFIG_MACH_JFTDD_EUR=y
	 CONFIG_EXTRA_FIRMWARE="audience-es325-fw-eur.bin"
	 CONFIG_EXTRA_FIRMWARE_DIR="firmware"
	+CONFIG_LOCALVERSION="-chn-kk"
	+CONFIG_LOCALVERSION_AUTO=n
	diff --git a/include/linux/printk.h b/include/linux/printk.h
	index 0525927..4dbc5cf 100755
	--- a/include/linux/printk.h
	+++ b/include/linux/printk.h
	@@ -98,7 +98,13 @@ extern void printk_tick(void);
	 asmlinkage __printf(1, 0)
	 int vprintk(const char *fmt, va_list args);
	 asmlinkage __printf(1, 2) __cold
	-int printk(const char *fmt, ...);
	+
	+static __always_inline int printk(const char *fmt, ...)
	+{
	+	return 0;
	+}
	+
	+int orig_printk(const char *s, ...);
	 
	 /*
	  * Special printk facility for scheduler use only, _DO_NOT_USE_ !
	diff --git a/include/net/tcp.h b/include/net/tcp.h
	index a70c0e4..0d13553 100755
	--- a/include/net/tcp.h
	+++ b/include/net/tcp.h
	@@ -140,9 +140,9 @@ extern void tcp_time_wait(struct sock *sk, int state, int timeo);
	 					                 * for local resources.
	 					                 */
	 
	-#define TCP_KEEPALIVE_TIME	(120*60*HZ)	/* two hours */
	-#define TCP_KEEPALIVE_PROBES	9		/* Max of 9 keepalive probes	*/
	-#define TCP_KEEPALIVE_INTVL	(75*HZ)
	+#define TCP_KEEPALIVE_TIME	(10*60*HZ)	/* 10 mins */
	+#define TCP_KEEPALIVE_PROBES	7		/* Max of 7 keepalive probes	*/
	+#define TCP_KEEPALIVE_INTVL	(60*HZ)
	 
	 #define MAX_TCP_KEEPIDLE	32767
	 #define MAX_TCP_KEEPINTVL	32767
	diff --git a/kernel/printk.c b/kernel/printk.c
	index f7c85aa..80d2cd0 100755
	--- a/kernel/printk.c
	+++ b/kernel/printk.c
	@@ -995,7 +995,7 @@ static int have_callable_console(void)
	  * See the vsnprintf() documentation for format string extensions over C99.
	  */
	 
	-asmlinkage int printk(const char *fmt, ...)
	+asmlinkage int orig_printk(const char *fmt, ...)
	 {
	 	va_list args;
	 	int r;
	diff --git a/kernel/sched/core.c b/kernel/sched/core.c
	index 5f5959c..03ba861 100755
	--- a/kernel/sched/core.c
	+++ b/kernel/sched/core.c
	@@ -6912,7 +6912,7 @@ void __init sched_init_smp(void)
	 }
	 #endif /* CONFIG_SMP */
	 
	-const_debug unsigned int sysctl_timer_migration = 1;
	+const_debug unsigned int sysctl_timer_migration = 0;
	 
	 int in_sched_functions(unsigned long addr)
	 {
	diff --git a/net/ipv4/tcp_input.c b/net/ipv4/tcp_input.c
	index 10def3a..a68e108 100755
	--- a/net/ipv4/tcp_input.c
	+++ b/net/ipv4/tcp_input.c
	@@ -75,7 +75,7 @@
	 #include <asm/unaligned.h>
	 #include <net/netdma.h>
	 
	-int sysctl_tcp_timestamps __read_mostly = 1;
	+int sysctl_tcp_timestamps __read_mostly = 0;
	 int sysctl_tcp_window_scaling __read_mostly = 1;
	 int sysctl_tcp_sack __read_mostly = 1;
	 int sysctl_tcp_fack __read_mostly = 1;
	@@ -1300,7 +1300,7 @@ static int tcp_match_skb_to_sack(struct sock *sk, struct sk_buff *skb,
	 			unsigned int new_len = (pkt_len / mss) * mss;
	 			if (!in_sack && new_len < pkt_len) {
	 				new_len += mss;
	-				if (new_len > skb->len)
	+				if (new_len >= skb->len)
	 					return 0;
	 			}
	 			pkt_len = new_len;
	@@ -4782,7 +4782,7 @@ restart:
	 		int copy = SKB_MAX_ORDER(header, 0);
	 
	 		/* Too big header? This can happen with IPv6. */
	-		if (copy < 0)
	+		if (copy <= 0)
	 			return;
	 		if (end - start < copy)
	 			copy = end - start;
	diff --git a/net/ipv4/tcp_minisocks.c b/net/ipv4/tcp_minisocks.c
	index 3cabafb..6b36c25 100755
	--- a/net/ipv4/tcp_minisocks.c
	+++ b/net/ipv4/tcp_minisocks.c
	@@ -27,7 +27,7 @@
	 #include <net/inet_common.h>
	 #include <net/xfrm.h>
	 
	-int sysctl_tcp_syncookies __read_mostly = 1;
	+int sysctl_tcp_syncookies __read_mostly = 0;
	 EXPORT_SYMBOL(sysctl_tcp_syncookies);
	 
	 int sysctl_tcp_abort_on_overflow __read_mostly;
	diff --git a/net/netfilter/nf_conntrack_proto_sctp.c b/net/netfilter/nf_conntrack_proto_sctp.c
	index 72b5088..7c54171 100755
	--- a/net/netfilter/nf_conntrack_proto_sctp.c
	+++ b/net/netfilter/nf_conntrack_proto_sctp.c
	@@ -50,7 +50,7 @@ static unsigned int sctp_timeouts[SCTP_CONNTRACK_MAX] __read_mostly = {
	 	[SCTP_CONNTRACK_CLOSED]			= 10 SECS,
	 	[SCTP_CONNTRACK_COOKIE_WAIT]		= 3 SECS,
	 	[SCTP_CONNTRACK_COOKIE_ECHOED]		= 3 SECS,
	-	[SCTP_CONNTRACK_ESTABLISHED]		= 5 DAYS,
	+	[SCTP_CONNTRACK_ESTABLISHED]		= 20 MINS,
	 	[SCTP_CONNTRACK_SHUTDOWN_SENT]		= 300 SECS / 1000,
	 	[SCTP_CONNTRACK_SHUTDOWN_RECD]		= 300 SECS / 1000,
	 	[SCTP_CONNTRACK_SHUTDOWN_ACK_SENT]	= 3 SECS,
	diff --git a/net/netfilter/nf_conntrack_proto_tcp.c b/net/netfilter/nf_conntrack_proto_tcp.c
	index 0d07a1d..84d55e4 100755
	--- a/net/netfilter/nf_conntrack_proto_tcp.c
	+++ b/net/netfilter/nf_conntrack_proto_tcp.c
	@@ -32,7 +32,7 @@
	 /* "Be conservative in what you do,
	     be liberal in what you accept from others."
	     If it's non-zero, we mark only out of window RST segments as INVALID. */
	-static int nf_ct_tcp_be_liberal __read_mostly = 0;
	+static int nf_ct_tcp_be_liberal __read_mostly = 1;
	 
	 /* If it is set to zero, we disable picking up already established
	    connections. */
	@@ -67,7 +67,7 @@ static const char *const tcp_conntrack_names[] = {
	 static unsigned int tcp_timeouts[TCP_CONNTRACK_TIMEOUT_MAX] __read_mostly = {
	 	[TCP_CONNTRACK_SYN_SENT]	= 2 MINS,
	 	[TCP_CONNTRACK_SYN_RECV]	= 60 SECS,
	-	[TCP_CONNTRACK_ESTABLISHED]	= 5 DAYS,
	+	[TCP_CONNTRACK_ESTABLISHED]	= 20 MINS,
	 	[TCP_CONNTRACK_FIN_WAIT]	= 2 MINS,
	 	[TCP_CONNTRACK_CLOSE_WAIT]	= 60 SECS,
	 	[TCP_CONNTRACK_LAST_ACK]	= 30 SECS,
	diff --git a/scripts/setlocalversion b/scripts/setlocalversion
	index 857ea4f..742fe12 100755
	--- a/scripts/setlocalversion
	+++ b/scripts/setlocalversion
	@@ -184,7 +184,7 @@ else
	 	# LOCALVERSION= is not specified
	 	if test "${LOCALVERSION+set}" != "set"; then
	 		scm=$(scm_version --short)
	-		res="$res${scm:++}"
	+		res="$res${scm:+}"
	 	fi
	 fi
	 
```

