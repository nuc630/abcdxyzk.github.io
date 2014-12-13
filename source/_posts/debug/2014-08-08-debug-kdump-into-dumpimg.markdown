---
layout: post
title: "kexec-tools-1.102pre-164.el5 之前的有问题"
date: 2014-08-08 16:49:00 +0800
comments: false
categories:
- 2014
- 2014~08
- debug
- debug~kdump、crash
tags:
---
kexec-tools-1.102pre-154.el5 会直接进入 *dump.img，于是便看到单CPU在跑，内存只有crashkernel中大小的情况。但是指定了ext* /dev/sd* 后就能正常。其他问题就是它通过网络时只会走eth0，不然就失败。

```
e2fsck 1.38 (30-Jun-2005)
fsck.ext3: while determining whether /dev/sda2 is mounted.
/: recovering journal
/: clean, 100877/4653056 files, 1236284/4648809 blocks
Mounting root filesystem.
Trying mount -t ext4 /dev/sda2 /sysroot
Trying mount -t ext3 /dev/sda2 /sysroot
Using ext3 on root filesystem
Switching to new root and running init.
^MINIT: version 2.86 booting^M
            Welcome to  CentOS release 5.8 (Final)
            Press 'I' to enter interactive startup.
Cannot access the Hardware Clock via any known method.
Use the --debug option to see the details of our search for an access method.
Setting clock  (utc): Tue Aug  5 19:18:49 PDT 2014 [  OK  ]^M
Starting udev: [  OK  ]^M
```

-------------------

ftp://ftp.redhat.com/pub/redhat/linux/enterprise/5Client/en/os/SRPMS/kexec-tools-1.102pre-154.el5.src.rpm

vim mkdumprd

-----------

https://bugzilla.redhat.com/show_bug.cgi?id=788678

Hmm, after a second thought, did you put the block device mounted on /var into your /etc/kdump.conf? Something like:

ext3 /dev/sdbX  #the device mounted on /var
path crash  #relative path inside /var

? Please share your kdump.conf if possible.

Thanks!

--

The point is to _not_ touch the default kdump.conf, and mkdumprd should just work, like it does in RHEL6.

If I do put the ext3 and path directives into kdump.conf, then of course things work fine, but it shouldn't be needed for the stock case where you just want to dump to /var/crash on your local filesystem.

--

Yeah... I saw how RHEL6 handles this, will try to backport it to RHEL5.
Thanks!

--

Created [attachment 594144](https://bugzilla.redhat.com/attachment.cgi?id=594144&action=diff) [details](https://bugzilla.redhat.com/attachment.cgi?id=594144&action=edit)Proposed Patch v3

Ok, let's just remove the UUID converting code.

--

Yep - it works now!

--

... almost. I'm pretty sure that the RHEL6 default mkdumprd uses makedumpfile by default so it isn't just using "cp" to create the vmcore file.

The currently-patched version appears to just use "cp" instead.

--

Yeah, this is expected, because we don't have a chance to change the default core_collector to makedumpfile on RHEL5, so "cp" is still the default one. :)

Thanks for testing!

