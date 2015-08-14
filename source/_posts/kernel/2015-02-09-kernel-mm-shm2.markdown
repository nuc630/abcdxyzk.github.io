---
layout: post
title: "修改共享内存大小"
date: 2015-02-09 15:33:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~mm
tags:
---
http://blog.csdn.net/l_yangliu/article/details/11193187

```
beijibing@bjb-desktop:/proc/sys/kernel$ cat shmmax 
33554432
beijibing@bjb-desktop:/proc/sys/kernel$ cat shmmni
4096
beijibing@bjb-desktop:/proc/sys/kernel$ cat msgmax
8192
beijibing@bjb-desktop:/proc/sys/kernel$ cat msgmni
622
beijibing@bjb-desktop:/proc/sys/kernel$ cat msgmnb
16384
```

#### System V IPC 参数
<table border="1">
<tr>
	<th>名字</th> <th>描述</th> <th>合理取值</th>
</tr>
<tr>
	<td>SHMMAX</td> <td>最大共享内存段尺寸（字节）</td> <td>最少若干兆（见文本）</td>
</tr>
<tr>
	<td>SHMMIN</td> <td>最小共享内存段尺寸（字节）</td> <td>1</td>
</tr>
<tr>
	<td>SHMALL</td> <td>可用共享内存的总数量（字节或者页面）</td> <td>如果是字节，就和 SHMMAX 一样；如果是页面，ceil(SHMMAX/PAGE_SIZE)</td>
</tr>
<tr>
	<td>SHMSEG</td> <td>每进程最大共享内存段数量</td> <td>只需要 1 个段，不过缺省比这高得多。</td>
</tr>
<tr>
	<td>SHMMNI</td> <td>系统范围最大共享内存段数量</td> <td>类似 SHMSEG 加上用于其他应用的空间</td>
</tr>
<tr>
	<td>SEMMNI</td> <td>信号灯标识符的最小数量（也就是说，套）</td> <td>至少 ceil(max_connections / 16)</td>
</tr>
<tr>
	<td>SEMMNS</td> <td>系统范围的最大信号灯数量</td> <td>ceil(max_connections / 16) * 17 加上用于其他应用的空间</td>
</tr>
<tr>
	<td>SEMMSL</td> <td>每套信号灯最小信号灯数量</td> <td>至少 17</td>
</tr>
<tr>
	<td>SEMMAP</td> <td>信号灯映射里的记录数量</td> <td>参阅文本</td>
</tr>
<tr>
	<td>SEMVMX</td> <td>信号灯的最大值</td> <td>至少 1000 （缺省通常是32767，除非被迫，否则不要修改）</td>
</tr>
</table>

  最重要的共享内存参数是 SHMMAX ， 以字节记的共享内存段可拥有的最大尺寸。如果你收到来自shmget 的类似Invalid argument 这样的错误信息，那么很有可能是你超过限制了。

  有些系统对系统里面共享内存的总数（SHMALL ）还有限制。 请注意这个数值必须足够大。（注意：SHMALL 在很多系统上是用页面数，而不是字节数来计算的。）

  系统里的最大信号灯数目是由SEMMNS 设置的，因此这个值应该至少和 max_connections 设置一样大，并且每十六个联接还要另外加一个。  参数SEMMNI 决定系统里一次可以存在的信号灯集的数目。 因此这个参数至少应该为 ceil(max_connections % 16) 。降低允许的联接数目是一个临时的绕开失败的方法，这个启动失败通常被来自函数semget 的错误响应 No space left on device 搞得很让人迷惑。

  有时候还可能有必要增大SEMMAP ，使之至少按照 SEMMNS 配置。这个参数定义信号灯资源映射的尺寸，可用的每个连续的信号灯块在这个映射中存放一条记录。每当一套信号灯被释放，那么它要么会加入到该映射中一条相连的已释放的块的入口中，要么注册成一条新的入口。如果映射填满了碎片，那么被释放的信号灯就丢失了（除非重起）。因此时间长信号灯空间的碎片了会导致可用的信号灯比应该有的信号灯少。

SEMMSL 参数，决定一套信号灯里可以有多少信号灯，

#### 更改方法
  缺省设置只适合小安装（缺省最大共享内存是 32 MB）。不过，其它的缺省值都相当大，通常不需要改变。最大的共享内存段设置可以用 sysctl 接口设置。 比如，要允许 128 MB，并且最大的总共享内存数为 2097152 页（缺省）：
```
	$ sysctl -w kernel.shmmax=134217728
	$ sysctl -w kernel.shmall=2097152
```
  你可以把这些设置放到 /etc/sysctl.conf 里，在重启后保持有效。


  老版本里可能没有 sysctl 程序，但是同样的改变可以通过操作 /proc 文件系统来做：
```
	$ echo 134217728 > /proc/sys/kernel/shmmax
	$ echo 2097152 > /proc/sys/kernel/shmall
```

