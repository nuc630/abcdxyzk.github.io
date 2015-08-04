---
layout: post
title: "CentOS 6 使用 LXC"
date: 2015-08-04 09:41:00 +0800
comments: false
categories:
- 2015
- 2015~08
- system
- system~cgroup
tags:
---
http://purplegrape.blog.51cto.com/1330104/1343766/

LXC 自kernel 2.6.27 加入linux 内核，依赖Linux 内核的cgroup和namespace功能而实现，非常轻量级，设计用于操作系统内部应用级别的隔离。


不同于vmware，kvm等虚拟化技术，它是一种类似chroot的容器技术，非常的轻量级。

与传统的硬件虚拟化技术相比有以下优势：

a、更小的虚拟化开销。Linux内核本身是一个很好的硬件资源调度器，LXC的诸多特性基本由内核提供，而内核实现这些特性只有极少的花费，CPU，内存，硬盘都是直接使用。

b、更快的启动速度。lxc容器技术将操作系统抽象到了一个新的高度。直接从init启动，省去了硬件自检、grub引导、加载内核、加载驱动等传统启动项目，因此启动飞速。

c、更快速的部署。lxc与带cow特性的后端文件系统相结合，一旦建好了模板，利用快照功能，半秒钟即可实现克隆一台lxc虚拟机。LXC虚拟机本质上只是宿主机上的一个目录，这也为备份和迁移提供了极大便利。

d、更高内存使用效率。普通虚拟机一般会独占一段内存，即使闲置，其他虚拟机也无法使用，例如KVM。而容器可以只有一个内存上限，没有下限。如果它只使用1MB内存，那么它只占用宿主机1MB内存。宿主机可以将富余内存作为他用。


LXC 目前已经比较成熟，官方在2014年2月推出1.0版本后就开始了长期维护，目前最新版本已经是1.07，CentOS 从6.5 开始支持LXC技术。


将LXC投入生产环境完全没有问题，因为LXC并不是什么新技术，而是重新聚合了已经成熟了的技术。


环境CentOS 6.5 x64

#### 1、安装LXC
```
	yum install libcgroup lxc lxc-templates --enablerepo=epel
	/etc/init.d/cgconfig start
	/etc/init.d/lxc start
```

#### 2、检查环境
```
	lxc-checkconfig
```
输出如下即是OK
```
	Kernel configuration not found at /proc/config.gz; searching...
	Kernel configuration found at /boot/config-2.6.32-431.1.2.0.1.el6.x86_64
	--- Namespaces ---
	Namespaces: enabled
	Utsname namespace: enabled
	Ipc namespace: enabled
	Pid namespace: enabled
	User namespace: enabled
	Network namespace: enabled
	Multiple /dev/ptsinstances: enabled
	--- Control groups---
	Cgroup: enabled
	Cgroup namespace: enabled
	Cgroup device: enabled
	Cgroup sched: enabled
	Cgroup cpu account: enabled
	Cgroup memory controller: enabled
	Cgroup cpuset: enabled
	--- Misc ---
	Veth pair device: enabled
	Macvlan: enabled
	Vlan: enabled
	File capabilities: enabled
	Note : Before booting a new kernel, you can check its configuration
	usage : CONFIG=/path/to/config/usr/bin/lxc-checkconfig
```

/usr/share/lxc/templates/ 自带了常用的模板可供选择，debian/ubuntu,centos/redhat 都有。


#### 3、使用模板安装一个centos 6 虚拟机
```
	lxc-create -n vm01 -t centos
```
或者
```
	lxc-create -n vm01 -t download -- -d centos -r 6 -a amd64
```

安装后，虚拟机默认位于/var/lib/lxc/vm01/rootfs，配置文件为/var/lib/lxc/vm01/config

a、如果你系统里恰好有个lvm VG 名字叫做lxc，那么lxc会识别到，加上一个参数 -B lvm，创建的虚拟机配置文件依然是/var/lib/lxc/vm01/config，但是lxc镜像会在/dev/lxc/vm01 这个LV 上 （默认500M大小）；

示例：
```
	lxc-create -n vm01 -t centos -B lvm --thinpool --fssize 250G --fstype xfs
```
上面的命令将会在lvm上创建一个lv，名为vm01，最大容量250G（因为加了thinpool参数，用多少占多少），文件系统是xfs。


b、如果你的/var 单独分区，恰好使用的是btrfs文件系统，lxc也会识别，创建lxc容器时自动创建子卷，并将容器镜像放在里面；


#### 4、lxc容器

打开lxc容器并进入开机console，
```
	lxc-start -n vm01
```

在后台运行虚拟机，并通过console连接过去 (使用ctrl+a+q退出console)
```
	lxc-start -n vm01 -d
	lxc-console -n vm01
```

直接连上虚拟机，不需要密码，连上后passwd设置root密码
```
	lxc-attach -n vm01
```

查看lxc容器相关信息(名称、是否在运行、PID，CPU使用、IO使用、内存使用、IP地址、网络吞吐量)
```	
	lxc-info -n vm01
```
监视lxc容器的资源使用
```
	lxc-top
```

#### 5、配置虚拟机网络，

新版lxc自带一个桥接lxcbr0 (10.0.3.1)，物理网卡通过NAT桥接到lxcbr0 ，网段为10.0.3.0/24。

如果上面新创建的虚拟机启动失败，很可能是lxcbr0 没有启动。


编辑文件/var/lib/lxc/vm01/config，确保文件包含一下内容
```
	lxc.network.type= veth
	lxc.network.link = lxcbr0
	lxc.network.flags = up
	lxc.network.name = eth0
	lxc.network.ipv4 = 10.0.3.2/24
	lxc.network.ipv4.gateway = 10.0.3.1
```

如果需要第二块网卡，则继续在/var/lib/lxc/vm01/config添加一组配置
```
	lxc.network.type = veth
	lxc.network.link = lxcbr0
	lxc.network.flags = up
	lxc.network.name = eth1
	lxc.network.ipv4 = 10.0.3.3/24
```

虚拟机网络默认由dnsmasq分配，如果没有在lxc中指定，则由虚拟机内部dhcp获得。


veth依赖网卡桥接，且可以与任何机器（宿主机，其他虚拟机，局域网其他机器）通讯。


在网络层，可以采取下面的方式加固安全：

如果要隔绝虚拟机与宿主机的通讯（虚拟机之间可以通信，与局域网其他机器也可以通信），网卡可选择macvlan中的bridge模式
```
	lxc.network.type = macvlan
	lxc.network.macvlan.mode = bridge
	lxc.network.flags = up
	lxc.network.link = eth0
```
如果要进一步隔离同一宿主机上不同虚拟机之间的通讯（仅可与局域网其他机器通信），网卡还要选择macvlan中的vepa模式
```
	lxc.network.type = macvlan
	lxc.network.macvlan.mode = vepa
	lxc.network.flags = up
	lxc.network.link = eth0
```

下面是三种特殊的网络
```
	lxc.network.type = none
```
none表示停用网络空间的namespace，复用宿主机的网络。

据说关闭容器也会关闭宿主机，ubuntu phone通过lxc里的安卓容器，使用网络复用达到兼容安卓应用的目的。（个人没有测试通过）
```
	lxc.network.type = empty
```
empty表示容器没有网卡，仅有一个回环lo，无法通过网络层与外部通信。用于某些特殊的场合。比如将宿主机的某个图片目录挂载到容器里，容器利用有限的资源对图片进行处理，如果放在宿主机上处理，图片处理占用的资源可能不好控制，影响整体性能。

```
	lxc.network.type = vlan
```
这种模式需要上联的物理交换机支持，用不同的vlan id 隔离容器与宿主机之间的通信。


#### 6、控制虚拟机的资源

虚拟机默认与宿主机共享硬件资源，CPU，内存，IO等，也可以用cgroup实现资源隔离。
```
	#设置虚拟机只使用0，1两个CPU核心
	lxc-cgroup -n centos cpuset.cpus 0,1
	#设置虚拟机可用内存为512M
	lxc-cgroup -n centos memory.limit_in_bytes 536870912
	#设置虚拟机消耗的CPU时间
	 lxc-cgroup -n centos cpu.shares 256
	#设置虚拟机消耗的IO权重
	 lxc-cgroup -n centos blkio.weight 500
```

另一种限制资源的方法是将具体的限制写入虚拟机的配置文件，可选的参数如下：
```
	#设置虚拟机只使用0，1两个CPU核心
	lxc.cgroup.cpuset.cpus  = 0,1
	#设置虚拟机消耗的CPU时间
	lxc.cgroup.cpu.shares  = 256
	#设置虚拟机可用内存为512M
	lxc.cgroup.memory.limit_in_bytes = 512M
	#限制虚拟机可用的内存和swap空间一共1G
	lxc.cgroup.memory.memsw.limit_in_bytes = 1G
	#设置虚拟机可使用的IO权重
	lxc.cgroup.blkio.weight=500
```

#### 7、安装ubuntu 12.04

LXC强大到有点变态，在centos上运行ubuntu？没错，因为内核对于LInux发行版来说是通用的。
```
	lxc-create -n ubuntu -t ubuntu -- -r precise
```
或者加上MIRROR参数（仅适用于ubuntu，用于选择较近的软件源）
```
	MIRROR="http://cn.archive.ubuntu.com/ubuntu"  lxc-create -n ubuntu-test -t ubuntu -- -r precise
```
点到为止，不深入。


#### 8、容器克隆

你可以创建一个标准化的lxc容器作为模板，然后对它进行克隆，避免重新安装，实现横向扩展和环境的标准化。下面以基于lvm卷的容器为例
```
	lxc-clone vm01 webserver01 -B lvm
```
克隆后的容器，是一个独立的lvm逻辑卷，默认与原来的大小一致（也可以指定大小），仅仅会改变mac地址和主机名。


如果你想节约空间，克隆时带上 -s （--snapshot） 参数，可以创建一个源容器的可读写快照，它几乎不占用空间，使得在一个机器上运行成百上千个容器成为可能，仅支持lvm和btrfs，因为它们都有cow功能 。-L 参数可以指定快照的大小。更多参数详见 man lxc-clone 。
```
	lxc-clone vm01 webserver01 -s -B lvm
```

#### 9、lxc容器的系统安全

lxc容器里的系统完全可以不需要用到root密码和ssh，可以设置空密码或者超级长的密码，openssh服务可以不必启动甚至不必安装。因为从宿主机运行下面的命令可以直接获得root shell，相当于chroot

```	
	lxc-attach -n webserver01
```
如果是应用容器，则更简单，因为容器里只有应用进程，比如httpd，连init 都木有。具体实现参考模板lxc-sshd 。


lxc 1.0还支持非特权容器，利用uidmap映射技术，将容器里的root映射为宿主机上的普通用户，允许以普通用户身份运行LXC容器，大大提高了宿主机的安全性。


使用方法省略，见我的另一篇文章。《ubuntu 14.04 体验LXC非特权容器》

http://purplegrape.blog.51cto.com/1330104/1528503

