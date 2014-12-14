---
layout: post
title: "kdump el5 --dump-dmesg 错误"
date: 2014-08-28 16:35:00 +0800
comments: false
categories:
- 2014
- 2014~08
- debug
- debug~kdump、crash
tags:
---
#### 原因：
http://vault.centos.org/5.11/os/SRPMS/kexec-tools-1.102pre-165.el5.src.rpm  
这个包的一个patch(kexec-tools-1.102pre-makedumpfile-dump-dmesg.patch)是为了得到dmesg的，  
但是它判断dmesg的结束是用logged_chars(看kernel/printk.c)，logged_chars应该是输出的结束，所以不对。  
改成log_end就行，  
```
diff --git a/kexec-tools-1.102pre-makedumpfile-dump-dmesg.patch b/kexec-tools-1.102pre-makedumpfile-dump-dmesg.patch
index 3938280..76c402a 100644
--- a/kexec-tools-1.102pre-makedumpfile-dump-dmesg.patch
+++ b/kexec-tools-1.102pre-makedumpfile-dump-dmesg.patch
@@ -68,7 +68,7 @@ diff -up kexec-tools-testing-20070330/makedumpfile/makedumpfile.c.orig kexec-too
 +dump_dmesg()
 +{
 +      int log_buf_len, length_log, length_oldlog, ret = FALSE;
-+      unsigned long log_addr, logged_chars, index;
++      unsigned long log_addr, logged_chars, log_end, index;
 +      char *log_buffer = NULL;
 +
 +      if (!open_files_for_creating_dumpfile())
@@ -101,10 +101,15 @@ diff -up kexec-tools-testing-20070330/makedumpfile/makedumpfile.c.orig kexec-too
 +               printf("Failed to get logged_chars.\n");
 +               return FALSE;
 +      }
++      if (!readmem(VADDR, SYMBOL(log_end), &log_end, sizeof(log_end))) {
++               printf("Failed to get log_end.\n");
++               return FALSE;
++      }
 +      DEBUG_MSG("\n");
 +      DEBUG_MSG("log_addr     : %lx\n", log_addr);
 +      DEBUG_MSG("log_buf_len  : %d\n", log_buf_len);
 +      DEBUG_MSG("logged_chars : %ld\n", logged_chars);
++      DEBUG_MSG("log_end      : %ld\n", log_end);
 +
 +      if ((log_buffer = malloc(log_buf_len)) == NULL) {
 +               ERRMSG("Can't allocate memory for log_buf. %s\n",
@@ -112,21 +117,16 @@ diff -up kexec-tools-testing-20070330/makedumpfile/makedumpfile.c.orig kexec-too
 +               return FALSE;
 +       }
 +
-+      if (logged_chars < log_buf_len) {
++      if (log_end < log_buf_len) {
 +               index = 0;
-+               length_log = logged_chars;
++               length_log = log_end;
 +
 +               if(!readmem(VADDR, log_addr, log_buffer, length_log)) {
 +                        printf("Failed to read dmesg log.\n");
 +                        goto out;
 +               }
 +      } else {
-+               if (!readmem(VADDR, SYMBOL(log_end), &index, sizeof(index))) {
-+                        printf("Failed to get log_end.\n");
-+                        goto out;
-+               }
-+               DEBUG_MSG("log_end      : %lx\n", index);
-+               index &= log_buf_len - 1;
++               index = log_end & (log_buf_len - 1);
 +               length_log = log_buf_len;
 +               length_oldlog = log_buf_len - index;
 +
```
----------------
----------------
#### 如果不修改上面bug，kdump得到vmcore后用 makedumpfile --dump-dmesg 无法解得dmesg，补救办法如下：  
kdump得到vmcore后  
 1、vmlinux没有debuginfo，crash不能运行  
 2、makedumpfile -F --dump-dmesg vmcore > dmesg 只能显示开头一下部分dmesg （不懂为什么）  
解决：

##### 方法一、
通过/boot/System.map 或者 /proc/kallsyms 找到 log_buf 地址，例如 0xffffffff81a9ac30
```
gdb vmlinux vmcore

set print repeats 100
set print elements 0
set logging file XXX
set pagination off
set logging on
p {char*} 0xffffffff81a9ac30
quit

---

vi XXX
:%s/\\n/\r/g
```
##### 方法二、
是另一命令，但不好用
```
cat /proc/kallsyms | grep log_end
ffffffff81e30de0 b log_end

x/1dw 0xffffffff81e30de0
0xffffffff81e30de0:     85689

x/1xg 0xffffffff81a9ac30
0xffffffff81a9ac30:     0xffffffff81e30ee0

显示最后4000字符
x/5s 0xffffffff81e30ee0+85689-4000
```
