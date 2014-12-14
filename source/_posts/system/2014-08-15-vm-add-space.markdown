---
layout: post
title: "VMware增加磁盘空间"
date: 2014-08-15 17:30:00 +0800
comments: false
categories:
- 2014
- 2014~08
- system
- system~base
tags:
---
#### 一 添加
选择“VM”----“setting”并打开，将光标定位在hard Disk这一选项，然后点击下方的Add按钮  
点击next，执行下一个步骤  
根据提示，创建一个虚拟的磁盘，并点击下一步  
按照默认的，选择SCSI格式的磁盘即可，点击next执行下一步  
按照默认的点击下一步即可完成虚拟磁盘的添加  

 则会多出一个/dev/sd?，这里的?代表硬盘编号，第一个硬盘编号为a即sda，第 二个就是sdb，第三个是 sdc，以此类推，一般来说，如果以前没有增加过硬盘，那么原来的硬盘就是sda，通过VMware菜单增加的虚拟硬盘编号就是sdb。如果添加的第二块 硬盘是IDE硬盘，就应该看到hdb，如果是SCSI硬盘，看到的就应该是sdb。

#### 二 分区
使用fdisk /dev/sda进入菜单项，m是列出菜单，p是列出分区表，n是增加分区，w是保存并推出。由于这里增加的磁盘只有5G，因此5G划为一个区。
对新建的磁盘进行分区及格式化的工作：   
输入 fdisk  /dev/sdb   
终端会提示：Command （m for help）：  
输入：m  则会出现提示  
然后根据提示输入：n  
会出现下面的提示，依次输入p 和 1 即可  
接着便会提示卷的起始地址和结束地址，都保持默认按回车的即可（意思是只分一个区）  
输入“w”保存并推出  
再次使用 “fdisk -l ”这个命令来查看会发现出现了/dev/sdb1（说明已经完成了分区工作）  


#### 三 对新建的分区进行格式化
格式化成ext3的文件系统即可  
使用mkfs.ext3 /dev/sda3    格式化分区  
```
[root@localhost ~]# mkfs.ext3 /dev/sda3
mke2fs 1.39 (29-May-2006)
Filesystem label=
OS type: Linux
Block size=4096 (log=2)
Fragment size=4096 (log=2)
656000 inodes, 1311305 blocks
65565 blocks (5.00%) reserved for the super user
First data block=0
Maximum filesystem blocks=1346371584
41 block groups
32768 blocks per group, 32768 fragments per group
16000 inodes per group
Superblock backups stored on blocks:
        32768, 98304, 163840, 229376, 294912, 819200, 884736


Writing inode tables: done                           
Creating journal (32768 blocks): done
Writing superblocks and filesystem accounting information: done


This filesystem will be automatically checked every 31 mounts or
180 days, whichever comes first.  Use tune2fs -c or -i to override.

[root@localhost ~]# cd /
[root@localhost /]# mkdir /cm				#增加一个/cm
[root@localhost /]# mount /dev/sda3 /cm			#挂载分区到   /cm        
[root@localhost /]# df -h				#挂载后的分区情况
文件系统              容量  已用 可用 已用% 挂载点
/dev/mapper/VolGroup00-LogVol00
                      8.6G  2.8G  5.4G  35% /
/dev/sda1              99M   12M   82M  13% /boot
tmpfs                 125M     0  125M   0% /dev/shm
/dev/sda3             5.0G  139M  4.6G   3% /cm
```

#### 四 设置开机自动加载    
创建加载点：mkdir /cm 挂载之后，      修改vi /etc/fstab  分区表文件，  
在文件最后加上      /dev/sda3  /cm   ext3    defaults    0 0     然后保存，重启即可。  

（注意：修改分区表如果有误，将导致进不了linux桌面系统，但这时系统会进入commandline模式，我们可以在commandline模式下对有误的fstab进行修复更改，不过默认情况下这个commandline模式会是Read-Only file system，这意味着你的任何修改操作都是不允许的，但可以通过命令 mount / -o remount,rw  来解除这个限制）。


#### vm虚拟机命令行
##### 1）开启虚拟机
vmrun start "/opt/VM_OS/RH_OS_B/Red Hat Enterprise Linux 5 64-bit.vmx" nogui|gui
##### 2）停止虚拟机
vmrun stop "/opt/VM_OS/RH_OS_B/Red Hat Enterprise Linux 5 64-bit.vmx" nogui|gui
##### 3）重启虚拟机
vmrun restart "/opt/VM_OS/RH_OS_B/Red Hat Enterprise Linux 5 64-bit.vmx" nogui|gui
##### 4）列出正在运行的虚拟机
vmrun list

