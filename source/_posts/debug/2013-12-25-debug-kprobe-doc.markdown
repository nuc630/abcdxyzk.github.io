---
layout: post
title: "kprobes Documentation"
date: 2013-12-25 14:04:00 +0800
comments: false
categories:
- 2013
- 2013~12
- debug
- debug~kprobe
tags:
---
https://www.kernel.org/doc/Documentation/kprobes.txt

Documentation/kprobes.txt

#### 1.4 How Does Jump Optimization Work?

If your kernel is built with CONFIG_OPTPROBES=y (currently this flag  
is automatically set 'y' on x86/x86-64, non-preemptive kernel) and  
the "debug.kprobes_optimization" kernel parameter is set to 1 (see  
sysctl(8)), Kprobes tries to reduce probe-hit overhead by using a jump  
instruction instead of a breakpoint instruction at each probepoint.  

##### 1.4.1 Init a Kprobe

When a probe is registered, before attempting this optimization,  
Kprobes inserts an ordinary, breakpoint-based kprobe at the specified  
address. So, even if it's not possible to optimize this particular  
probepoint, there'll be a probe there.  

##### 1.4.2 Safety Check

Before optimizing a probe, Kprobes performs the following safety checks:  

- Kprobes verifies that the region that will be replaced by the jump  
instruction (the "optimized region") lies entirely within one function.  
(A jump instruction is multiple bytes, and so may overlay multiple  
instructions.)  

- Kprobes analyzes the entire function and verifies that there is no  
jump into the optimized region.  Specifically:  
  - the function contains no indirect jump;  
  - the function contains no instruction that causes an exception (since  
  the fixup code triggered by the exception could jump back into the  
  optimized region -- Kprobes checks the exception tables to verify this);  
  and  
  - there is no near jump to the optimized region (other than to the first  
  byte).  

- For each instruction in the optimized region, Kprobes verifies that  
the instruction can be executed out of line.  

##### 1.4.3 Preparing Detour Buffer

Next, Kprobes prepares a "detour" buffer, which contains the following  
instruction sequence:  
- <span style="color:red">code to push the CPU's registers (emulating a breakpoint trap)</span>  
- <span style="color:red">a call to the trampoline code which calls user's probe handlers.</span>  
- <span style="color:red">code to restore registers</span>  
- <span style="color:red">the instructions from the optimized region</span>  
- <span style="color:red">a jump back to the original execution path.</span>  

##### 1.4.4 Pre-optimization

After preparing the detour buffer, Kprobes verifies that none of the  
following situations exist:  
- <span style="color:red">The probe has either a break_handler (i.e., it's a jprobe) or a post_handler.</span>  
- <span style="color:red">Other instructions in the optimized region are probed.</span>  
- <span style="color:red">The probe is disabled.</span>  

In any of the above cases, Kprobes won't start optimizing the probe.  
Since these are temporary situations, Kprobes tries to start  
optimizing it again if the situation is changed.  

If the kprobe can be optimized, Kprobes enqueues the kprobe to an  
optimizing list, and kicks the kprobe-optimizer workqueue to optimize  
it.  If the to-be-optimized probepoint is hit before being optimized,  
Kprobes returns control to the original instruction path by setting  
the CPU's instruction pointer to the copied code in the detour buffer  
-- thus at least avoiding the single-step.  

##### 1.4.5 Optimization

The Kprobe-optimizer doesn't insert the jump instruction immediately;  
rather, it calls synchronize_sched() for safety first, because it's  
possible for a CPU to be interrupted in the middle of executing the  
optimized region(*).  As you know, synchronize_sched() can ensure  
that all interruptions that were active when synchronize_sched()  
was called are done, but only if CONFIG_PREEMPT=n.  So, this version  
of kprobe optimization supports only kernels with CONFIG_PREEMPT=n.(**)  

After that, the Kprobe-optimizer calls stop_machine() to replace  
the optimized region with a jump instruction to the detour buffer,  
using text_poke_smp().  

##### 1.4.6 Unoptimization

When an optimized kprobe is unregistered, disabled, or blocked by  
another kprobe, it will be unoptimized.  If this happens before  
the optimization is complete, the kprobe is just dequeued from the  
optimized list.  If the optimization has been done, the jump is  
replaced with the original code (except for an int3 breakpoint in  
the first byte) by using text_poke_smp().  

(*)Please imagine that the 2nd instruction is interrupted and then  
the optimizer replaces the 2nd instruction with the jump *address*  
while the interrupt handler is running. When the interrupt  
returns to original address, there is no valid instruction,  
and it causes an unexpected result.  

(**)This optimization-safety checking may be replaced with the  
stop-machine method that ksplice uses for supporting a CONFIG_PREEMPT=y  
kernel.  

NOTE for geeks:  
<span style="color:red">The jump optimization changes the kprobe's pre_handler behavior.</span>  
<span style="color:red">Without optimization, the pre_handler can change the kernel's execution</span>  
<span style="color:red">path by changing regs->ip and returning 1.  However, when the probe</span>  
<span style="color:red">is optimized, that modification is ignored.  Thus, if you want to</span>  
<span style="color:red">tweak the kernel's execution path, you need to suppress optimization,</span>  
<span style="color:red">using one of the following techniques:</span>  
- <span style="color:blue">Specify an empty function for the kprobe's post_handler or break_handler.</span>  
 or  
- <span style="color:blue">Execute 'sysctl -w debug.kprobes_optimization=n'</span>  


....................


#### 5. Kprobes Features and Limitations

Kprobes allows multiple probes at the same address.  Currently,  
however, there cannot be multiple jprobes on the same function at  
the same time.  Also, a probepoint for which there is a jprobe or  
a post_handler cannot be optimized.  So if you install a jprobe,  
or a kprobe with a post_handler, at an optimized probepoint, the  
probepoint will be unoptimized automatically.  

In general, you can install a probe anywhere in the kernel.  
In particular, you can probe interrupt handlers.  Known exceptions  
are discussed in this section.  

The register_*probe functions will return -EINVAL if you attempt  
to install a probe in the code that implements Kprobes (mostly  
kernel/kprobes.c and arch/*/kernel/kprobes.c, but also functions such  
as do_page_fault and notifier_call_chain).  

If you install a probe in an inline-able function, Kprobes makes  
no attempt to chase down all inline instances of the function and  
install probes there.  gcc may inline a function without being asked,  
so keep this in mind if you're not seeing the probe hits you expect.  

A probe handler can modify the environment of the probed function  
-- e.g., by modifying kernel data structures, or by modifying the  
contents of the pt_regs struct (which are restored to the registers  
upon return from the breakpoint).  So Kprobes can be used, for example,  
to install a bug fix or to inject faults for testing.  Kprobes, of  
course, has no way to distinguish the deliberately injected faults  
from the accidental ones.  Don't drink and probe.  

Kprobes makes no attempt to prevent probe handlers from stepping on  
each other -- e.g., probing printk() and then calling printk() from a  
probe handler.  If a probe handler hits a probe, that second probe's  
handlers won't be run in that instance, and the kprobe.nmissed member  
of the second probe will be incremented.  

As of Linux v2.6.15-rc1, multiple handlers (or multiple instances of  
the same handler) may run concurrently on different CPUs.  

Kprobes does not use mutexes or allocate memory except during  
registration and unregistration.  

Probe handlers are run with preemption disabled.  Depending on the  
architecture and optimization state, handlers may also run with  
interrupts disabled (e.g., kretprobe handlers and optimized kprobe  
handlers run without interrupt disabled on x86/x86-64).  In any case,  
your handler should not yield the CPU (e.g., by attempting to acquire  
a semaphore).  

Since a return probe is implemented by replacing the return  
address with the trampoline's address, stack backtraces and calls  
to `__builtin_return_address()` will typically yield the trampoline's  
address instead of the real return address for kretprobed functions.  
(As far as we can tell, `__builtin_return_address()` is used only  
for instrumentation and error reporting.)  

If the number of times a function is called does not match the number  
of times it returns, registering a return probe on that function may  
produce undesirable results. In such a case, a line:  
kretprobe BUG!: Processing kretprobe d000000000041aa8 @ c00000000004f48c  
gets printed. With this information, one will be able to correlate the  
exact instance of the kretprobe that caused the problem. We have the  
do_exit() case covered. do_execve() and do_fork() are not an issue.  
We're unaware of other specific cases where this could be a problem.  

If, upon entry to or exit from a function, the CPU is running on  
a stack other than that of the current task, registering a return  
probe on that function may produce undesirable results.  For this  
reason, Kprobes doesn't support return probes (or kprobes or jprobes)  
on the x86_64 version of `__switch_to()`; the registration functions  
return -EINVAL.  

<kk style="color:red">
On x86/x86-64, since the Jump Optimization of Kprobes modifies  
instructions widely, there are some limitations to optimization. To  
explain it, we introduce some terminology. Imagine a 3-instruction  
sequence consisting of a two 2-byte instructions and one 3-byte  
instruction.  
</kk>

```  
	        IA  
	         |  
	[-2][-1][0][1][2][3][4][5][6][7]  
	        [ins1][ins2][  ins3 ]  
	        [<-     DCR       ->]  
	           [<- JTPR ->]  
```  
<kk style="color:red">
ins1: 1st Instruction  
ins2: 2nd Instruction  
ins3: 3rd Instruction  
IA:  Insertion Address  
JTPR: Jump Target Prohibition Region  
DCR: Detoured Code Region  
</kk>

<kk style="color:red">
The instructions in DCR are copied to the out-of-line buffer  
of the kprobe, because the bytes in DCR are replaced by  
a 5-byte jump instruction. So there are several limitations.  
</kk>

<kk style="color:red">
a) The instructions in DCR must be relocatable.  
b) The instructions in DCR must not include a call instruction.  
c) JTPR must not be targeted by any jump or call instruction.  
d) DCR must not straddle the border between functions.  
</kk>

<kk style="color:red">
Anyway, these limitations are checked by the in-kernel instruction  
decoder, so you don't need to worry about that.  
</kk>

#### 6. Probe Overhead

On a typical CPU in use in 2005, a kprobe hit takes 0.5 to 1.0  
microseconds to process.  Specifically, a benchmark that hits the same  
probepoint repeatedly, firing a simple handler each time, reports 1-2  
million hits per second, depending on the architecture.  A jprobe or  
return-probe hit typically takes 50-75% longer than a kprobe hit.  
When you have a return probe set on a function, adding a kprobe at  
the entry to that function adds essentially no overhead.  

Here are sample overhead figures (in usec) for different architectures.  
k = kprobe; j = jprobe; r = return probe; kr = kprobe + return probe  
on same function; jr = jprobe + return probe on same function  

i386: Intel Pentium M, 1495 MHz, 2957.31 bogomips  
k = 0.57 usec; j = 1.00; r = 0.92; kr = 0.99; jr = 1.40  

x86_64: AMD Opteron 246, 1994 MHz, 3971.48 bogomips  
k = 0.49 usec; j = 0.76; r = 0.80; kr = 0.82; jr = 1.07  

ppc64: POWER5 (gr), 1656 MHz (SMT disabled, 1 virtual CPU per physical CPU)  
k = 0.77 usec; j = 1.31; r = 1.26; kr = 1.45; jr = 1.99  

##### 6.1 Optimized Probe Overhead

Typically, an optimized kprobe hit takes 0.07 to 0.1 microseconds to  
process. Here are sample overhead figures (in usec) for x86 architectures.  
k = unoptimized kprobe, b = boosted (single-step skipped), o = optimized kprobe,  
r = unoptimized kretprobe, rb = boosted kretprobe, ro = optimized kretprobe.  

i386: Intel(R) Xeon(R) E5410, 2.33GHz, 4656.90 bogomips  
k = 0.80 usec; b = 0.33; o = 0.05; r = 1.10; rb = 0.61; ro = 0.33  

x86-64: Intel(R) Xeon(R) E5410, 2.33GHz, 4656.90 bogomips  
<span style="color:red">k = 0.99 usec; b = 0.43; o = 0.06; r = 1.24; rb = 0.68; ro = 0.30</span>  

