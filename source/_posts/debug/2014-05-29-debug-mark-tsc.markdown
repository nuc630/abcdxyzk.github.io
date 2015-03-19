---
layout: post
title: "TSC时间错误"
date: 2014-05-29 14:03:00 +0800
comments: false
categories:
- 2014
- 2014~05
- debug
- debug~mark
tags:
---
arch/x86/kernel/tsc.c:  
  开机初始化会调用tsc_init() -> set_cyc2ns_scale() 设置per_cpu变量cyc2ns、cyc2ns_offset。以供后面shced_clock()->native_sched_clock()->__cycles_2_ns()调用。

在cpufreq_tsc()中如果  
   //cpu具有稳定的tsc   
    if (boot_cpu_has(X86_FEATURE_CONSTANT_TSC))   
        return 0;  
  所以一般不会注册time_cpufreq_notifier函数，也就不会再调用set_cyc2ns_scale。  

* 现象：top、ps出来的TIME和CPU的值非常异常。

```
	// 查看TSC寄存器的值
	#include <stdio.h>

	int main()
	{
		    unsigned long low, high, val;
		    asm volatile("rdtsc": "=a" (low), "=d" (high));
		    val = ((low) | ((unsigned long)(high) << 32));
		    printf("%lu\n", val);
		    return 0;
	}
```

-------------

https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=733043

Xeon E5 has a bug, it doesn't reset TSC on warm reboot, just keep it instead.
 see "BT81. X X X No Fix TSC is Not Affected by Warm Reset" http://www.intel.com/content/dam/www/public/us/en/documents/specification-updates/xeon-e5-family-spec-update.pdf  

 And also kernel 2.6.32 has a bug.  
 Xeon bug + kernel bug = hung after warm reboot (or kexec) after 208.5 days  
 since booting. So, administrators should shutdown it once at all, then  
 boot it again because "shutdown -r" causes hang up. 

 Red Hat has released a fix for this as kernel 2.6.32-220, 2.6.32-279  
 and 2.6.32-358 series (RHEL6.x) https://access.redhat.com/site/solutions/433883 (for detail subscriber only :-(  

 Attached patch is based on upstream patch.  
 see http://kernel.opensuse.org/cgit/kernel/patch/?id=9993bc635d01a6ee7f6b833b4ee65ce7c06350b1



--------

  Red Hat Enterprise Linux 6.1 (kernel-2.6.32-131.26.1.el6 and newer)  
  Red Hat Enterprise Linux 6.2 (kernel-2.6.32-220.4.2.el6 and newer)  
  Red Hat Enterprise Linux 6.3 (kernel-2.6.32-279 series)  
  Red Hat Enterprise Linux 6.4 (kernel-2.6.32-358 series)  
  Any Intel® Xeon® E5, Intel® Xeon® E5 v2, or Intel® Xeon® E7 v2 series processor  

-------

From 9993bc635d01a6ee7f6b833b4ee65ce7c06350b1 Mon Sep 17 00:00:00 2001  
From: Salman Qazi <`sqazi@google.com`>  
Date: Sat, 10 Mar 2012 00:41:01 +0000  
Subject: sched/x86: Fix overflow in cyc2ns_offset  

When a machine boots up, the TSC generally gets reset.  However,
when kexec is used to boot into a kernel, the TSC value would be
carried over from the previous kernel.  The computation of
cycns_offset in set_cyc2ns_scale is prone to an overflow, if the
machine has been up more than 208 days prior to the kexec.  The
overflow happens when we multiply *scale, even though there is
enough room to store the final answer.

We fix this issue by decomposing tsc_now into the quotient and
remainder of division by CYC2NS_SCALE_FACTOR and then performing
the multiplication separately on the two components.

Refactor code to share the calculation with the previous
fix in __cycles_2_ns().

Signed-off-by: Salman Qazi <`sqazi@google.com`>  
Acked-by: John Stultz <`john.stultz@linaro.org`>  
Acked-by: Peter Zijlstra <`a.p.zijlstra@chello.nl`>  
Cc: Paul Turner <`pjt@google.com`>  
Cc: john stultz <`johnstul@us.ibm.com`>  
Link: http://lkml.kernel.org/r/20120310004027.19291.88460.stgit@dungbeetle.mtv.corp.google.com  
Signed-off-by: Ingo Molnar <`mingo@elte.hu`>  

-------

patch： http://kernel.opensuse.org/cgit/kernel/patch/?id=9993bc635d01a6ee7f6b833b4ee65ce7c06350b1

```
diff --git a/arch/x86/include/asm/timer.h b/arch/x86/include/asm/timer.h
index 431793e..34baa0e 100644
--- a/arch/x86/include/asm/timer.h
+++ b/arch/x86/include/asm/timer.h
@@ -57,14 +57,10 @@ DECLARE_PER_CPU(unsigned long long, cyc2ns_offset);
 
 static inline unsigned long long __cycles_2_ns(unsigned long long cyc)
 {
-	unsigned long long quot;
-	unsigned long long rem;
 	int cpu = smp_processor_id();
 	unsigned long long ns = per_cpu(cyc2ns_offset, cpu);
-	quot = (cyc >> CYC2NS_SCALE_FACTOR);
-	rem = cyc & ((1ULL << CYC2NS_SCALE_FACTOR) - 1);
-	ns += quot * per_cpu(cyc2ns, cpu) +
-		((rem * per_cpu(cyc2ns, cpu)) >> CYC2NS_SCALE_FACTOR);
+	ns += mult_frac(cyc, per_cpu(cyc2ns, cpu),
+			(1UL << CYC2NS_SCALE_FACTOR));
 	return ns;
 }
 
diff --git a/arch/x86/kernel/tsc.c b/arch/x86/kernel/tsc.c
index a62c201..183c592 100644
--- a/arch/x86/kernel/tsc.c
+++ b/arch/x86/kernel/tsc.c
@@ -620,7 +620,8 @@ static void set_cyc2ns_scale(unsigned long cpu_khz, int cpu)
 
 	if (cpu_khz) {
 		*scale = (NSEC_PER_MSEC << CYC2NS_SCALE_FACTOR)/cpu_khz;
-		*offset = ns_now - (tsc_now * *scale >> CYC2NS_SCALE_FACTOR);
+		*offset = ns_now - mult_frac(tsc_now, *scale,
+					     (1UL << CYC2NS_SCALE_FACTOR));
 	}
 
 	sched_clock_idle_wakeup_event(0);
diff --git a/include/linux/kernel.h b/include/linux/kernel.h
index e834342..d801acb 100644
--- a/include/linux/kernel.h
+++ b/include/linux/kernel.h
@@ -85,6 +85,19 @@
 }							\
 )
 
+/*
+ * Multiplies an integer by a fraction, while avoiding unnecessary
+ * overflow or loss of precision.
+ */
+#define mult_frac(x, numer, denom)(			\
+{							\
+	typeof(x) quot = (x) / (denom);			\
+	typeof(x) rem  = (x) % (denom);			\
+	(quot * (numer)) + ((rem * (numer)) / (denom));	\
+}							\
+)
+
+
 #define _RET_IP_		(unsigned long)__builtin_return_address(0)
 #define _THIS_IP_  ({ __label__ __here; __here: (unsigned long)&&__here; }) 
```

