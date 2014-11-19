---
layout: post
title: "crash vs gdb work"
date: 2014-11-06 10:51:00 +0800
comments: true
categories:
- 2014
- 2014~11
- debug
- debug~kdump、crash
tags:
- crash
- gdb
---
[贴自https://www.redhat.com/archives/crash-utility/2014-October/msg00002.html](https://www.redhat.com/archives/crash-utility/2014-October/msg00002.html)  
Yes, sure. GDB works very differently from crash. There main conceptual  
difference is that GDB only handles with VIRTUAL addresses, while the  
crash utility first translates everything to PHYSICAL addresses.  
Consequently, GDB ignores the PhysAddr field in ELF program headers,  
and crash ignores the VirtAddr field.  
  
I have looked at some of my ELF dump files, and it seems to me that  
VirtAddr is not filled correctly, except for kernel text and static  
data (address range 0xffffffff80000000-0xffffffff9fffffff). Your linked  
list is most likely allocated in the direct mapping  
(0xffff880000000000-0xffffc7ffffffffff). However, I found out that the  
virtual addresses for the direct mapping segments are wrong, e.g. my  
dump file specifies it at 0xffff810000000000 (hypervisor area). This is  
most likely a bug in the kernel code that implements /proc/vmcore.  
  
But that's beside the point. Why?  The Linux kernel maps many physical  
pages more than once into the virtual address space. It would be waste  
of space if you saved it multiple times (for each virtual address that  
maps to it). The crash utility can translate each virtual address to  
the physical address and map it onto ELF segments using PhysAddr.  
Incidentally, the PhysAddr fields are correct in my dump files...  
  
I'm glad you're interested in using GDB to read kernel dump files,  
especially if you're willing to make it work for real. I have proposed  
more than once that the crash utility be re-implemented in pure gdb.  
Last time I looked (approx. 1.5 years ago) the main missing pieces were:  
  
  1. Use of physical addresses (described above)  
  2. Support for multiple virtual address spaces (for different process  
     contexts)  
  3. Ability to read compressed kdump files  
  4. Ability to use 64-bit files on 32-bit platforms (to handle PAE)  
  
HTH,  
Petr Tesarik
