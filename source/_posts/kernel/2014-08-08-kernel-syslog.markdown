---
layout: post
title: "log_buf(ring buffer)(syslog)(printk)"
date: 2014-08-08 09:43:00 +0800
comments: false
categories:
- 2014
- 2014~08
- kernel
- kernel~base
tags:
---
##### printk 的输出都是保存在log_buf里的
How to read it the ring buffer? Here is a beautiful illustration from IBM Developerworks
dmesg would be your first resort! How does dmesg accomplish its task? By a call to syslog()! How does syslog do its job? Through the system call interface which in turn call do_syslog(). do_syslog() does the finishing act like this

![alt](/images/kernel/2014-08-08.gif)

// 模仿kernel/printk.c中do_syslog，在module 中读printk输出的最后4k
```
        char **log_buf;
        int *log_buf_len, *log_start, *log_end;

        int MASK;
        int end, len;
        unsigned i, j, limit, count;
        char c;
        int ret;


        log_buf = (char**) 0xffffffff803270e0;
        log_buf_len = (int*)0xffffffff803270d8;
        log_start = (int*) 0xffffffff804eabd0;
        log_end = (int*) 0xffffffff804eabe0;

        i = 0;
        end = *log_end;
        len = *log_buf_len;
        MASK = len - 1;

        count = L;
        if (count > len) count = len;
        limit = end;

        for (i=0;i<count;i++) {
                j = limit-1-i;
                c = *(*log_buf + (j&MASK));
                if (c == '\0') c = '\n';
                buf[count-1-i] = c;
        }

// 输出

        file = filp_open(file_path, O_RDWR|O_CREAT|O_APPEND, 0777);
        if(IS_ERR(file)) {
                printk("Open file %s failed..\n", file_path);
                return 0;
        }
        old_fs = get_fs();
        set_fs(get_ds());
        ret = file->f_op->write(file, buf, i, &file->f_pos);
        file->f_op->fsync(file, file->f_dentry, 0);
        set_fs(old_fs);
        filp_close(file, NULL);
```
