---
layout: post
title: "ubuntu安装kvm虚拟机"
date: 2015-07-07 14:35:00 +0800
comments: false
categories:
- 2015
- 2015~07
- system
- system~ubuntu
tags:
---

```
	sudo apt-get install qemu-kvm libvirt-bin virt-manager
```

用 virt-manager

参考 http://nmszh.blog.51cto.com/4609205/1539502

------------

http://www.sysstem.at/category/linux/

#### 问题一：

```
	ERROR internal error: Process exited while reading console log output: char device redirected to /dev/pts/45 (label charserial0)
	ioctl(KVM_CREATE_VM) failed: 16 Device or resource busy
	failed to initialize KVM: Device or resource busy
```
  This is mostly because you have either VirtualBox or VMware running on the same machine. The reason (at least that’s what I think) is that the kernel module of VirtualBox or VMware and KVM can’t take Advantage of Intel VT-x or AMD-V at the same time.

关闭virtualbox等其他虚拟机就好

-----------

http://ask.xmodulo.com/hda-duplex-not-supported-in-this-qemu-binary.html

#### 问题二：

```
	Unable to complete install: 'unsupported configuration: hda-duplex not supported in this QEMU library
```

##### Solution One: Virt-Manager

On virt-manager, open the VM's virtual hardware details menu, go to sound device section, and change the device model from default to ac97.

Click on "Apply" button to save the change. See if you can start the VM now.

也就是 最后一步 “勾选安装之前配置“，完成，然后将声卡改成ac97即可

##### Solution Two: Virsh
If you are using virsh, not virt-manager, you can edit the VM's XML file accordingly. Look for sound section inside <device> section, and change the sound model to ac97 as follows.
```
	  <devices>
		. . .
		<sound model='ac97'>
		  <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
		</sound>
		. . .
	  </device>
```


--------------

http://wiki.ubuntu.org.cn/Kvm%E6%95%99%E7%A8%8B

