---
layout: post
title: "centos安装kvm虚拟机"
date: 2015-07-07 14:33:00 +0800
comments: false
categories:
- 2015
- 2015~07
- system
- system~centos
tags:
---

* 最好在centos6装

* TODO 虚拟机网桥连接没试

http://docs.openstack.org/zh_CN/image-guide/content/virt-install.html

#### 安装
```
	yum install qemu-kvm libvirt virt-manager
```

#### 管理界面

```
	virt-manager
```
图形化安装过程见： http://nmszh.blog.51cto.com/4609205/1539502


#### 命令行创建安装
```
	qemu-img create -f qcow2 ttt.img 10G
```

```
	virt-install --virt-type kvm --name centos-6.4 --ram 1024 \
	--cdrom=/data/CentOS-6.4-x86_64-netinstall.iso \
	--disk path=/data/centos-6.4.qcow2,size=10,format=qcow2 \
	--network network=default \
	--graphics vnc,listen=0.0.0.0 --noautoconsole \
	--os-type=linux --os-variant=rhel6

	Starting install...
	Creating
	domain...  |    0 B     00:00
	Domain installation still in progress. You can reconnect to
	the console to complete the installation process.
```
  KVM 虚拟化使用 centos-6.4 名称，1024MB内存启动虚拟机。虚拟机还有一个关联文件/data/CentOS-6.4-x86_64-netinstall.iso 的虚拟的 CD-ROM，并拥有 10GB 的qcow2格式的硬盘，硬盘文件位置在 /data/centos-6.4.qcow2。虚拟机配置了网络使用 libvirt 的默认网络。且 VNC 服务监听所有的网卡，并且 libvirt 不会自动启动 VNC 客户端也不会显示字符界面控制台（--no-autoconsole）。最后，libvirt 将尝试以RHEL 6.x 发行版来优化虚拟机配置。

  运行
```
	virt-install --os-variant list
```
命令查看 `--os-variant` 允许的选项范围。


  使用命令获取 VNC 端口号。
```
	virsh vncdisplay vm-name

  # virsh vncdisplay centos-6.4
  :1
```

在上面的示例中，虚拟机 centos-6.4 使用 VNC 显示器 :1，对应的 TCP 端口是 5901。你应该使用本地 VNC 客户端连接到远程服务器的 ：1 显示器并且完成安装步骤。

用vncviewer连接虚拟机完成安装
```
	vncviewer IP:5901
```

* 装好后会生成 /etc/libvirt/qemu/ttt.xml 配置文件，可以修改

----------------

http://os.51cto.com/art/201404/435193.htm

http://tianhao936.blog.51cto.com/1043670/1343767

#### 虚拟机操作

常用virsh指令
```
	1）virsh list               列出当前虚拟机列表，不包括未启动的
	2）virsh list --all         列出所有虚拟机，包括所有已经定义的虚拟机
	3）virsh start vm-name      启动虚拟机
	4）virsh destroy vm-name    关闭虚拟机	
	5）virsh undefine vm-name   删除虚拟机
	6）virsh shutdown vm-name   停止虚拟机
	7）virsh reboot vm-name     重启虚拟机
	8）virsh edit vm-name       编辑虚拟机xml文件
	9）virsh autostart vm-name  虚拟机随宿主机启动 
```


-----------

http://blog.csdn.net/justlinux2010/article/details/8977705

http://www.centoscn.com/image-text/config/2014/0801/3407.html

-----------

错误
```
	Could not initialize SDL(No available video device) - exiting
```

需要在桌面环境运行qemu-kvm
