---
layout: post
title: "cgroups介绍、使用"
date: 2015-07-31 14:53:00 +0800
comments: false
categories:
- 2015
- 2015~07
- system
- system~cgroup
tags:
---
http://blog.csdn.net/jesseyoung/article/details/39077829

http://tech.meituan.com/cgroups.html

http://www.cnblogs.com/lisperl/tag/%E8%99%9A%E6%8B%9F%E5%8C%96%E6%8A%80%E6%9C%AF/

#### 1 cgroup简介

Cgroups是control groups的缩写，是Linux内核提供的一种可以限制、记录、隔离进程组（process groups）所使用的物理资源（如：cpu,memory,IO等等）的机制。最初由google的工程师提出，后来被整合进Linux内核。也是目前轻量级虚拟化技术 lxc （linux container）的基础之一。

#### 2 cgroup作用

Cgroups最初的目标是为资源管理提供的一个统一的框架，既整合现有的cpuset等子系统，也为未来开发新的子系统提供接口。现在的cgroups适用于多种应用场景，从单个进程的资源控制，到实现操作系统层次的虚拟化（OS Level Virtualization）。Cgroups提供了以下功能：

1.限制进程组可以使用的资源数量（Resource limiting ）。比如：memory子系统可以为进程组设定一个memory使用上限，一旦进程组使用的内存达到限额再申请内存，就会出发OOM（out of memory）。

2.进程组的优先级控制（Prioritization ）。比如：可以使用cpu子系统为某个进程组分配特定cpu share。

3.记录进程组使用的资源数量（Accounting ）。比如：可以使用cpuacct子系统记录某个进程组使用的cpu时间

4.进程组隔离（Isolation）。比如：使用ns子系统可以使不同的进程组使用不同的namespace，以达到隔离的目的，不同的进程组有各自的进程、网络、文件系统挂载空间。

5.进程组控制（Control）。比如：使用freezer子系统可以将进程组挂起和恢复。

#### 3 cgroup相关概念

##### 3.1 相关概念

1.任务（task）。在cgroups中，任务就是系统的一个进程。

2.控制族群（control group）。控制族群就是一组按照某种标准划分的进程。Cgroups中的资源控制都是以控制族群为单位实现。一个进程可以加入到某个控制族群，也从一个进程组迁移到另一个控制族群。一个进程组的进程可以使用cgroups以控制族群为单位分配的资源，同时受到cgroups以控制族群为单位设定的限制。

3.层级（hierarchy）。控制族群可以组织成hierarchical的形式，既一颗控制族群树。控制族群树上的子节点控制族群是父节点控制族群的孩子，继承父控制族群的特定的属性。

4.子系统（subsystem）。一个子系统就是一个资源控制器，比如cpu子系统就是控制cpu时间分配的一个控制器。子系统必须附加（attach）到一个层级上才能起作用，一个子系统附加到某个层级以后，这个层级上的所有控制族群都受到这个子系统的控制。

##### 3.2 相互关系

1.每次在系统中创建新层级时，该系统中的所有任务都是那个层级的默认 cgroup（我们称之为 root cgroup ，此cgroup在创建层级时自动创建，后面在该层级中创建的cgroup都是此cgroup的后代）的初始成员。

2.一个子系统最多只能附加到一个层级。

3.一个层级可以附加多个子系统

4.一个任务可以是多个cgroup的成员，但是这些cgroup必须在不同的层级。

5.系统中的进程（任务）创建子进程（任务）时，该子任务自动成为其父进程所在 cgroup 的成员。然后可根据需要将该子任务移动到不同的 cgroup 中，但开始时它总是继承其父任务的cgroup。

#### 4 cgroup子系统介绍
```
	blkio   -- 这个子系统为块设备设定输入/输出限制，比如物理设备（磁盘，固态硬盘，USB 等等）。
	cpu     -- 这个子系统使用调度程序提供对 CPU 的 cgroup 任务访问。
	cpuacct -- 这个子系统自动生成 cgroup 中任务所使用的 CPU 报告。
	cpuset  -- 这个子系统为 cgroup 中的任务分配独立 CPU（在多核系统）和内存节点。
	devices -- 这个子系统可允许或者拒绝 cgroup 中的任务访问设备。
	freezer -- 这个子系统挂起或者恢复 cgroup 中的任务。
	memory  -- 这个子系统设定 cgroup 中任务使用的内存限制，并自动生成由那些任务使用的内存资源报告。
	net_cls -- 这个子系统使用等级识别符（classid）标记网络数据包，可允许 Linux 流量控制程序（tc）识别从具体 cgroup 中生成的数据包。
	ns      -- 名称空间子系统。
```

#### 5 cgroup安装（centos下）

若系统未安装则进行安装，若已安装则进行更新。

```
	[root@localhost ~]# yum install libcgroup  
```

查看运行状态，并启动服务

```
	[root@localhost ~]# service cgconfig status  
	Stopped  
	[root@localhost ~]# service cgconfig start  
	Starting cgconfig service:                                 [  OK  ]  
	[root@localhost ~]# service cgconfig status  
	Running  
```

#### 6 cgroup配置

##### 6.1 配置文件介绍

6.1.1 cgroup配置文件所在位置

```
	/etc/cgconfig.conf  
```

6.1.2 默认配置文件内容

```
	mount {  
		cpuset  = /cgroup/cpuset;  
		cpu     = /cgroup/cpu;  
		cpuacct = /cgroup/cpuacct;  
		memory  = /cgroup/memory;  
		devices = /cgroup/devices;  
		freezer = /cgroup/freezer;  
		net_cls = /cgroup/net_cls;  
		blkio   = /cgroup/blkio;  
	}  
```

相当于执行命令

```
	mkdir /cgroup/cpuset  
	mount -t cgroup -o cpuset red /cgroup/cpuset  
	……  
	mkdir /cgroup/blkio  
	mount -t cgroup -o cpuset red /cgroup/blkio  
```

6.1.3 cgroup section的语法格式如下

```
	group <name> {  
		[<permissions>]  
		<controller> {  
			<param name> = <param value>;  
			…  
		}  
	…}  
```

name: 指定cgroup的名称  
permissions：可选项，指定cgroup对应的挂载点文件系统的权限，root用户拥有所有权限。  
controller： 子系统的名称  
param name 和 param value：子系统的属性及其属性值

#### 7 cgroup实例分析（限制mysql资源使用）

##### 7.1 配置对mysql实例的资源限制

前提：mysql数据库已在机器上安装

7.1.1 修改cgconfig.conf文件

```
	mount {  
		cpuset  = /cgroup/cpuset;  
		cpu = /cgroup/cpu;  
		cpuacct = /cgroup/cpuacct;  
		memory  = /cgroup/memory;  
		blkio   = /cgroup/blkio;  
	}  

	group mysql_g1 {    
		cpu {  
			cpu.cfs_quota_us = 50000;  
			cpu.cfs_period_us = 100000;  
		}  
		cpuset {    
			cpuset.cpus = "3";    
			cpuset.mems = "0";    
		}    
		cpuacct{  
	  
		}  
		memory {    
			memory.limit_in_bytes=104857600;  
			memory.swappiness=0;  
			# memory.max_usage_in_bytes=104857600;  
			# memory.oom_control=0;  
		}   
		blkio  {  
			blkio.throttle.read_bps_device="8:0 524288";  
			blkio.throttle.write_bps_device="8:0 524288";  
		}   
	}   
```

7.1.2 配置文件的部分解释。

cpu：cpu使用时间限额。

  cpu.cfs_period_us和cpu.cfs_quota_us来限制该组中的所有进程在单位时间里可以使用的cpu时间。这里的cfs是完全公平调度器的缩写。cpu.cfs_period_us就是时间周期(微秒)，默认为100000，即百毫秒。cpu.cfs_quota_us就是在这期间内可使用的cpu时间(微秒)，默认-1，即无限制。(cfs_quota_us是cfs_period_us的两倍即可限定在双核上完全使用)。

cpuset：cpu绑定

  我们限制该组只能在0一共1个超线程上运行。cpuset.mems是用来设置内存节点的。

  本例限制使用超线程0上的第四个cpu线程。

  其实cgconfig也就是帮你把配置文件中的配置整理到/cgroup/cpuset这个目录里面，比如你需要动态设置mysql_group1/ cpuset.cpus的CPU超线程号，可以采用如下的办法。

```
	[root@localhost ~]# echo "0" > mysql_group1/ cpuset.cpus  
```

cpuacct：cpu资源报告

memory：内存限制 

  内存限制我们主要限制了MySQL可以使用的内存最大大小memory.limit_in_bytes=256M。而设置swappiness为0是为了让操作系统不会将MySQL的内存匿名页交换出去。

blkio：BLOCK IO限额

blkio.throttle.read_bps_device="8:0 524288"; #每秒读数据上限  
blkio.throttle.write_bps_device="8:0 524288"; #每秒写数据上限  

其中8:0对应主设备号和副设备号，可以通过ls -l /dev/sda查看

```
	[root@localhost /]# ls -l /dev/sda  
	brw-rw----. 1 root disk 8, 0 Sep 15 04:19 /dev/sda
```

7.1.4 修改cgrules.conf文件

```
	[root@localhost ~]# vi /etc/cgrules.conf  
	# /etc/cgrules.conf  
	#The format of this file is described in cgrules.conf(5)  
	#manual page.  
	#  
	# Example:  
	#<user>         <controllers>   <destination>  
	#@student       cpu,memory      usergroup/student/  
	#peter          cpu             test1/  
	#%              memory          test2/  

	*:/usr/local/mysql/bin/mysqld * mysql_g1  

```
注：共分为3个部分，分别为需要限制的实例，限制的内容（如cpu，memory），挂载目标。

#### 7.2 使配置生效

```
	[root@localhost ~]# /etc/init.d/cgconfig restart  
	Stopping cgconfig service:                                 [  OK  ]  
	Starting cgconfig service:                                 [  OK  ]  
	[root@localhost ~]# /etc/init.d/cgred restart  
	Stopping CGroup Rules Engine Daemon...                     [  OK  ]  
	Starting CGroup Rules Engine Daemon:                       [  OK  ]  
```
注：重启顺序为cgconfig -> cgred ，更改配置文件后两个服务需要重启，且顺序不能错。

##### 7.3 启动MySQL，查看MySQL是否处于cgroup的限制中

```
	[root@localhost ~]# ps -eo pid,cgroup,cmd | grep -i mysqld  
	29871 blkio:/;net_cls:/;freezer:/;devices:/;memory:/;cpuacct:/;cpu:/;cpuset:/ /bin/sh ./bin/mysqld_safe --defaults-file=/etc/my.cnf --basedir=/usr/local/mysql/ --datadir=/usr/local/mysql/data/  
	30219 blkio:/;net_cls:/;freezer:/;devices:/;memory:/;cpuacct:/;cpu:/;cpuset:/mysql_g1 /usr/local/mysql/bin/mysqld --defaults-file=/etc/my.cnf --basedir=/usr/local/mysql/ --datadir=/usr/local/mysql/data/ --plugin-dir=/usr/local/mysql//lib/plugin --user=mysql --log-error=/usr/local/mysql/data//localhost.localdomain.err --pid-file=/usr/local/mysql/data//localhost.localdomain.pid --socket=/tmp/mysql.sock --port=3306  
	30311 blkio:/;net_cls:/;freezer:/;devices:/;memory:/;cpuacct:/;cpu:/;cpuset:/ grep -i mysqld  
```

---------------------
---------------------

### 不改配置文件，用命令实时配置

比如通过命令
```
	cgcreate -t sankuai:sankuai -g cpu:test
```
就可以在 cpu 子系统下建立一个名为 test 的节点。

当需要删除某一个 cgroups 节点的时候，可以使用 cgdelete 命令，比如要删除上述的 test 节点，可以使用 cgdelete -r cpu:test命令进行删除


然后可以通过写入需要的值到 test 下面的不同文件，来配置需要限制的资源。每个子系统下面都可以进行多种不同的配置，需要配置的参数各不相同，详细的参数设置需要参考 cgroups 手册。使用 cgset 命令也可以设置 cgroups 子系统的参数，格式为 cgset -r parameter=value path_to_cgroup。


把进程加入到 cgroups 子节点也有多种方法，可以直接把 pid 写入到子节点下面的 task 文件中。也可以通过 cgclassify 添加进程，格式为 
```
	cgclassify -g subsystems:path_to_cgroup pidlist
```
也可以直接使用 cgexec 在某一个 cgroups 下启动进程，格式为
```
	gexec -g subsystems:path_to_cgroup1 -g subsystems:path_to_cgroup2 command arguments.
```


#### 把任务的cpu资源使用率限制在了50%。

首先在 cpu 子系统下面创建了一个 halfapi 的子节点：
```
	cgcreate abc:abc -g cpu:halfapi
```

然后在配置文件中写入配置数据：
```
	echo 50000 > /cgroup/cpu/halfapi/cpu.cfs_quota_us
```
cpu.cfs_quota_us中的默认值是100000，写入50000表示只能使用50%的 cpu 运行时间。

最后在这个cgroups中启动这个任务：
```
	cgexec -g "cpu:/halfapi" php halfapi.php half >/dev/null 2>&1
```



