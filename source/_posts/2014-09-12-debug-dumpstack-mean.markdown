---
layout: post
title: "The meaning of '?' in Linux kernel panic call trace"
date: 2014-06-12 09:42:00 +0800
comments: true
categories:
- 2014
- 2014~06
- debug
- debug~base
tags:
- debug
---

* '?' means that the information about this stack entry is probably not reliable.

The stack output mechanism (see the implementation of dump_trace() function) was unable to prove that the address it has found is a valid return address in the call stack.

'?' itself is output by printk_stack_address().

The stack entry may be valid or not. Sometimes one may simply skip it. It may be helpful to investigate the disassembly of the involved module to see which function is called at ClearFunctionName+0x88 (or, on x86, immediately before that position).

Concerning reliability

On x86, when dump_stack() is called, the function that actually examines the stack is print_context_stack() defined in arch/x86/kernel/dumpstack.c. Take a look at its code, I'll try to explain it below.

I assume DWARF2 stack unwind facilities are not available in your Linux system (most likely, they are not, if it is not OpenSUSE or SLES). In this case, print_context_stack() seems to do the following.

It starts from an address ('stack' variable in the code) that is guaranteed to be an address of a stack location. It is actually the address of a local variable in dump_stack().

The function repeatedly increments that address (while (valid_stack_ptr ...) { ... stack++}) and checks if what it points to could also be an address in the kernel code (if (__kernel_text_address(addr)) ...). This way it attempts to find the functions' return addresses pushed on stack when these functions were called.

Of course, not every unsigned long value that looks like a return address is actually a return address. So the function tries to check it. If frame pointers are used in the code of the kernel (%ebp/%rbp registers are employed for that if CONFIG_FRAME_POINTER is set), they can be used to traverse the stack frames of the functions. The return address for a function lies just above the frame pointer (i.e. at %ebp/%rbp + sizeof(unsigned long)). print_context_stack checks exactly that.

If there is a stack frame for which the value 'stack' points to is the return address, the value is considered a reliable stack entry. ops->address will be called for it with reliable == 1, it will eventually call printk_stack_address() and the value will be output as a reliable call stack entry. Otherwise the address will be considered unreliable. It will be output anyway but with '?' prepended.

[NB] If frame pointer information is not available (e.g. like it was in Debian 6 by default), all call stack entries will be marked as unreliable for this reason.

The systems with DWARF2 unwinding support (and with CONFIG_STACK_UNWIND set) is a whole another story.

