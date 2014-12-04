---
layout: post
title: "VirtualBox压缩vdi"
date: 2014-10-15 01:15:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~vm
tags:
---
http://blog.csdn.net/zcg1041bolg/article/details/7870170

VirtualBox guest os用久了vdi文件就会越来越大，就算在guest os中删除了一些文件，vdi也不会变小。

#### 如果guest os 是windows:
1. 先在guest os上运行磁盘碎片管理器，将各个磁盘的磁盘碎片减少；  
2. 下载sdelete（http://technet.microsoft.com/en-us/sysinternals/bb897443.aspx）;  
3. 运行sdelete -c -z  c:    
4. 关闭guest os 和 VirtualBox  
5. 在host os上运行VBoxManage modifyhd --compact yourImage.vdi  

 

#### 如果guest os 是Linux:
1. 进入su  
2. $ dd if=/dev/zero of=test.file  
3. $ rm test.file  
4. 关闭guest os 和 VirtualBox  
5. 在host os上 运行 $ VBoxManage modifyhd --compact yourImage.vdi  

这样在guest上看到占用的空间就和host上看到的空间就一样了。  


#### CMD下 的命令行：
```
C:\Program Files>cd Oracle
C:\Program Files\Oracle>cd VirtualBox
C:\Program Files\Oracle\VirtualBox>VBoxManage.exe modifyhd --compact E:\ubuntu-virtualbox\ubuntu-virtualBox.vdi
0%...10%...20%...30%...40%...50%...60%...70%...80%...90%...100%
C:\Program Files\Oracle\VirtualBox>
```
