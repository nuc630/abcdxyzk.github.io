---
layout: post
title: "patch / git patch"
date: 2014-10-30 10:44:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~command
tags:
- patch
- git
---
#### 1、diff
```
diff [options] from-file to-file  
```
简单的说，diff的功能就是用来比较两个文件的不同，然后记录下来，也就是所谓的diff补丁。语法格式：diff 【选项】 源文件（夹） 目的文件（夹），就是要给源文件（夹）打个补丁，使之变成目的文件（夹），术语也就是“升级”。下面介绍三个最为常用选项：  
>    -r 是一个递归选项，设置了这个选项，diff会将两个不同版本源代码目录中的所有对应文件全部都进行一次比较，包括子目录文件。  
>    -N 选项确保补丁文件将正确地处理已经创建或删除文件的情况。  
>    -u 选项以统一格式创建补丁文件，这种格式比缺省格式更紧凑些  

#### 2、patch
```
patch [options] [originalfile [patchfile]]
but usually just
patch -pnum <patchfile>
```
简单的说，patch就是利用diff制作的补丁来实现源文件（夹）和目的文件（夹）的转换。这样说就意味着你可以有源文件（夹）――>目的文件（夹），也可以目的文件（夹）――>源文件（夹）。下面介绍几个最常用选项：  
>    -p0 选项要从当前目录查找目的文件（夹）  
>    -p1 选项要忽略掉第一层目录，从当前目录开始查找。

************************************************************
在这里以实例说明：
```
--- old/modules/pcitable       Mon Sep 27 11:03:56 1999
+++ new/modules/pcitable       Tue Dec 19 20:05:41 2000
```
如果使用参数-p0，那就表示从当前目录找一个叫做old的文件夹，在它下面寻找modules下的pcitable文件来执行patch操作。  
如果使用参数-p1， 那就表示忽略第一层目录（即不管old），从当前目录寻找modules的文件夹，在它下面找pcitable。这样的前提是当前目 录必须为modules所在的目录。而diff补丁文件则可以在任意位置，只要指明了diff补丁文件的路径就可以了。当然，可以用相对路径，也可以用绝 对路径。不过我一般习惯用相对路径。  
>	-E 选项说明如果发现了空文件，那么就删除它  
>	-R 选项说明在补丁文件中的“新”文件和“旧”文件现在要调换过来了（实际上就是给新版本打补丁，让它变成老版本）  

#### 单个文件
```
diff –uN from-file to-file >to-file.patch
patch –p0 < to-file.patch
patch –RE –p0 < to-file.patch
```
#### 目录
```
diff –uNr from-docu to-docu >to-docu.patch
patch –p1 < to-docu.patch
patch –R –p1 <to-docu.patch
```
-------------------

#### git diff或者其他UNIX的diff命令生成patch的过程：
```
	git diff  > patch
	git diff  --cached > patch
	git diff  branchname --cached > patch
```
这个时候当前目录下就会有一个patch文件，这是一个非git环境也可以使用的patch。对于这种patch，在git上使用要用git apply命令，如下：
```
	git apply patch
```

由于这是一个类似UNIX下更新文件的操作，所以执行完上述操作之后，实际上是等于手动修改了文件，还要做一些git commit之类的操作。git apply 是一个事务性操作的命令，也就是说，要么所有补丁都打上去，要么全部放弃。可以先用git apply --check 查看补丁是否能够干净顺利地应用到当前分支中：git apply --check patch，如果执行完该命令之后没有任何输出，表示我们可以顺利采纳该补丁，接下来就是git上的提交了。

git format-patch生成的补丁，这是git专用的。常用命令如下：  
1. 两个节点之间的提交： git format-patch  节点A   节点B  
2. 单个节点： git format-patch -1 节点A （-n就表示要生成几个节点的提交）  
3. 最近一次提交节点的patch ：git format-patch HEAD^ 依次类推……  

使用git format-patch命令生成的patch文件，包含了提交的附加信息：比如作者，时间等。再次基础上使用git am命令即可将此补丁应用到当前分支。注意应用完之后，你会发现当前分支多了一次提交记录，并且有完整的信息，而不是简单的修改文件。在对比一下，git diff 和git format-patch生成的patch一个重要不同之处，实际使用中会发现git diff一次只会生成一个patch文件，不管差别了多少个提交，都是一个；而git format-patch是根据提交的节点来的，一个节点一个patch。

#### git两种patch的比较：
兼容性：很明显，git diff生成的Patch兼容性强。如果你在修改的代码的官方版本库不是Git管理的版本库，那么你必须使用git diff生成的patch才能让你的代码被项目的维护人接受。

除错功能：对于git diff生成的patch，你可以用git apply --check 查看补丁是否能够干净顺利地应用到当前分支中；如果git format-patch 生成的补丁不能打到当前分支，git am会给出提示，并协助你完成打补丁工作，你也可以使用git am -3进行三方合并，详细的做法可以参考git手册或者《Progit》。从这一点上看，两者除错功能都很强。

版本库信息：由于git format-patch生成的补丁中含有这个补丁开发者的名字，因此在应用补丁时，这个名字会被记录进版本库，显然，这样做是恰当的。因此，目前使用Git的开源社区往往建议大家使用format-patch生成补丁。

