---
layout: post
title: "开机自动挂载硬盘"
date: 2014-05-28 21:42:00 +0800
comments: false
categories:
- 2014
- 2014~05
- system
- system~base
tags:
---
#### 一、Linux磁盘分区UUID的获取
```
1、$ ls -l /dev/disk/by-uuid/
2、$ blkid /dev/sdb1
```

#### 二、开机自动挂载
```
vim /etc/fstab
UUID=XXXX /XXXX ext4 defaults 0 0
```

----------

我们在linux中常常用mount命令把硬盘分区或者光盘挂载到文件系统中。/etc/fstab就是在开机引导的时候自动挂载到linux的文件系统。
在linux中/etc/fstab的数据项如下所示：
```
/dev/device   mountpoint   type   rules   dump   order
设备名称        挂载点          分区类型   挂载选项     dump选项    fsck选项
```

例如这是一个普通的/etc/fstab:
```
/dev/hda2     /                    ext3        defaults   0 1
/dev/hda3     swap             swap      defaults   0 0
/dev/hda5     /usr               ext3        defaults   0 0
/dev/fdo        /mnt/flopy     ext3        noauto     0 0
/dev/cdrom    /mnt/cdrom   iso9660  noauto,ro 0 0
```
#### (1)设备名称
/dev/device就是需要挂载的设备，/hda2就是第一个IDE插槽上的主硬盘的第二个分区。如果是第二个IDE插槽主硬盘的第三个分区，那就是/dev/hdc3，具体可以在linux下使用fdisk -l  查看。

#### (2)挂载点
mountpoint 就是挂载点。/、 /usr、 swap 都是系统安装时分区的默认挂载点。  
如果你要挂载一个新设备，你就要好好想想了，因为这个新设备将作为文件系统永久的一部分，需要根据FSSTND（文件系统标准），以及它的作用，用户需求来决定。比如你想把它做为一个共享资源，放在/home下面就是一个不错选择。

#### (3)分区类型
type 是指文件系统类型，下面列举几个常用的：
```
Linux file systems: ext2, ext3, jfs, reiserfs, reiser4, xfs, swap.
Windows:
vfat = FAT 32, FAT 16
ntfs= NTFS
Note: For NTFS rw ntfs-3g
CD/DVD/iso: iso9660
Network file systems:
nfs: server:/shared_directory /mnt/nfs nfs <options> 0 0
smb: //win_box/shared_folder /mnt/samba smbfs rw,credentials=/home/user_name/winbox-credentials.txt 0 0
auto: The file system type (ext3, iso9660, etc) it detected automatically. Usually works. Used for removable devices (CD/DVD, Floppy drives, or USB/Flash drives) as the file system may vary on thesedevices.
```

#### (4)挂载选项
rules 是指挂载时的规则。下面列举几个常用的：
```
auto 开机自动挂载
default 按照大多数永久文件系统的缺省值设置挂载定义
noauto 开机不自动挂载
nouser 只有超级用户可以挂载
ro 按只读权限挂载
rw 按可读可写权限挂载
user 任何用户都可以挂载
```
请注意光驱和软驱只有在装有介质时才可以进行挂载，因此它是noauto

#### (5)dump选项
这一项为0，就表示从不备份。如果上次用dump备份，将显示备份至今的天数。

#### (6)fsck选项
order 指fsck（启动时fsck检查的顺序）。为0就表示不检查，（/）分区永远都是1，其它的分区只能从2开始，当数字相同就同时检查（但不能有两1）。  
如果我要把第二个IDE插槽主硬盘上的windows C 区挂到文件系统中，那么数据项是：
```
/dev/hdc1 /c vfat defaults 0 0
(/c 是事先建立的文件夹，作为c盘的挂载点。)
```
当你修改了/etc/fstab后，一定要重新引导系统才会有效。  
fstab中存放了与分区有关的重要信息，其中每一行为一个分区记录，每一行又可分为六个部份，下面以/dev/hda7 / ext2 defaults 1 1为例逐个说明：

1. 第一项是您想要mount的储存装置的实体位置，如hdb或如上例的/dev/hda7。  
2. 第二项就是您想要将其加入至哪个目录位置，如/home或如上例的/,这其实就是在安装时提示的挂入点。  
3. 第三项就是所谓的local filesystem，其包含了以下格式：如ext、ext2、msdos、iso9660、nfs、swap等，或如上例的ext2，可以参见/prco/filesystems说明。  
4. 第四项就是您mount时，所要设定的状态，如ro（只读）或如上例的defaults（包括了其它参数如rw、suid、exec、auto、nouser、async），可以参见「mount nfs」。  
5. 第五项是提供DUMP功能，在系统DUMP时是否需要BACKUP的标志位，其内定值是0。  
6. 第六项是设定此filesystem是否要在开机时做check的动作，除了root的filesystem其必要的check为1之外，其它皆可视需要设定，内定值是0。  

