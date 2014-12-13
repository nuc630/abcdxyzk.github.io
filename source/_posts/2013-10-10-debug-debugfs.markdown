---
layout: post
title: "通过blktrace, debugfs分析磁盘IO"
date: 2013-10-10 16:25:00 +0800
comments: false
categories:
- 2013
- 2013~10
- debug
- debug~base
tags:
---
如何通过blktrace+debugfs找到发生IO的文件，然后再结合自己的应用程序，分析出这些IO到底是 谁产生的，最终目的当然是尽量减少不必要的IO干扰，提高程序的性能。

blktrace是Jens Axobe写的一个跟踪IO请求的工具，Linux系统发起的IO请求都可以通过blktrace捕获并分析，关于这个工具的介绍请自行google之，这里推荐我们部门的[褚霸](http://blog.yufeng.info/)同学的blog，里面有好几篇文章分别介绍了blktrace, blkparse以及blkiomon等工具的使用。

debugfs是ext2, ext3, ext4文件系统提供的文件系统访问工具，通过它我们可以不通过mount文件系统而直接访问文件系统的内容，它是e2fsprogs的一部分，默认应该都是安装的，详细的说明可以通过man debugfs得到。

下面我来演示一下如何通过这两个工具的配合来找到磁盘IO的源头。

先看一个简单的例子：  
在一个终端会输入如下命令：  
```
while [ 1 ];do dd if=/dev/zero of=test_file bs=4k count=20 seek=$RANDOM oflag=sync;done
```
随机的在test_file里面写数据造成较大的IO压力，现在看看如何通过blktrace和debugfs抓到它。

1、通过iostat观察到有很大的磁盘压力
```
Device:         rrqm/s   wrqm/s     r/s     w/s   rsec/s   wsec/s avgrq-sz avgqu-sz   await  svctm  %util
sdb               0.00  2759.00    0.00 3515.50     0.00 50196.00    14.28     0.90    0.26   0.24  85.70
```

2、我们看到sdb压力很大，这时候就需要通过blktrace抓取对应盘的数据  
  blktrace /dev/sdb   有IO压力的时候一会儿就可以了，通过ctrl+c停止抓取。  
  blktrace是需要debugfs支持的，如果系统提示debugfs没有mount，需要先mount上  
  mount -t debugfs none /sys/kernel/debug 再执行blktrace命令  

3、将blktrace抓出来的二进制文件转成文本格式。  
  blkparse sdb.blktrace.* > 1.log  
或blktrace  -d /dev/sda -o - |blkparse -i - > 1.log

4、开始分析日志
```
  grep ‘ A ‘ 1.log|head -n 5

8,16   0       39     0.001242727  2872  A  WS 420143 + 8 <- (8,17) 420080
8,16   0       52     0.001361766  2872  A  WS 420151 + 8 <- (8,17) 420088
8,16   0       65     0.001440210  2872  A  WS 420159 + 8 <- (8,17) 420096
8,16   0       78     0.001518207  2872  A  WS 420167 + 8 <- (8,17) 420104
8,16   0       91     0.001596083  2872  A  WS 420175 + 8 <- (8,17) 420112
```

为啥要grep ‘ A ‘呢？因为这条信息是上层一个读写请求进入到Linux IO协议栈的第一步，只有在这里我们可以看到清晰的请求原始信息。比如
```
8,16   0       39     0.001242727  2872  A  WS 420143 + 8 <- (8,17) 420080
```
这条说明是设备（8，17）也就是sdb1上产生的扇区为420080的写请求（读请求的话会在WS对应的位置出现‘R’），长度是8，它被映射到（8，16）上位置为420143。这个IO请求的完整生命周期是这样的：
```
 8,16   0       39     0.001242727  2872  A  WS 420143 + 8 <- (8,17) 420080
 8,16   0       41     0.001244984  2872  G  WS 420143 + 8 [dd]
 8,16   0       43     0.001246609  2872  I  WS 420143 + 8 [dd]
 8,16   0       45     0.001255064  2872  D  WS 420143 + 8 [dd]
 8,16   0       46     0.001325168     0  C  WS 420143 + 8 [0]
```
可以看到从’ A ‘的下一条开始都是以整个设备的扇区号为标识的，不方便我们找到对应的分区。

5、下面就开始通过debugfs来分析这条读写请求的来源了。
(8, 17)是sdb1, 420080是扇区号(IO层的基本单位是扇区sector，大小是512bytes)，而文件系统层是通过块block来管理的，一般的 ext3,ext4的块block大小是4096[1]，由此可得这个请求对应到文件系统的块block号是420080/8=52510, debugfs提供了命令icheck可以通过block号找到它对应的文件的inode。
```
#debugfs -R ‘icheck 52510′ /dev/sdb1
debugfs 1.43-WIP (1-Aug-2012)
Block Inode number
52510 12
```
6、通过inode number找到对应的文件名，很幸运，debugfs又提供了另外一条命令ncheck可以找到inode对应的文件名[2]。
```
#debugfs -R ‘ncheck 12′ /dev/sdb1
debugfs 1.43-WIP (1-Aug-2012)
Inode Pathname
12 //test_file
```
大家可以看到，我们现在已经成功找到了test_file这个文件啦，至此块设备层和文件系统层的分析工作已经结束了，下面就可以结合应用看看为啥会对这个文件有如此频繁的读写操作了！



[1] 块大小实际上也能够通过debugfs来得到。
```
debugfs -R ‘stats’ /dev/sdb1|grep “Block size”
```
[2] 有的同学找到的inode number是8，然后却无法找到对应的文件名。这是因为8是ext3/4文件系统中的日志文件的inode，它是隐藏文件，所以无法找到，可以再试试其他的block号哦！

根据inode你就可以找到对应的文件是什么了  
find / -inum your_inode

