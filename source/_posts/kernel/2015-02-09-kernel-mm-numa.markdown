---
layout: post
title: "玩转CPU Topology"
date: 2015-02-09 16:19:00 +0800
comments: false
categories:
- 2015
- 2015~02
- kernel
- kernel~mm
tags:
---
http://www.searchtb.com/2012/12/%E7%8E%A9%E8%BD%ACcpu-topology.html

#### 先温习几个概念
请原谅对部分术语笔者直接引用了wikipedia上的英文解释，因为哥实在做不到比wikipedia上更准确描述。我会试着解释部分的术语，并在本节的最后梳理一下这些术语之间的关系。注意，笔者对由于不准确的描述导致的性能下降，进程crash等任何问题不承担任何责任☺

NUMA：Non-Uniform Memory Access (NUMA) is a computer memory design used in multiprocessing, where the memory access time depends on the memory location relative to a processor. Under NUMA, a processor can access its own local memory faster than non-local memory, that is, memory local to another processor or memory shared between processors.NUMA architectures logically follow in scaling from symmetric multiprocessing (SMP) architectures.

提到NUMA就不能不对比SMP，

SMP：Symmetric multiprocessing (SMP) involves a multiprocessor computer hardware architecture where two or more identical processors are connected to a single shared main memory and are controlled by a single OS instance.

说了这么多其实都是为了介绍NUMA Node:

A fairly technically correct and also fairly ugly definition of a node is: a region of memory in which every byte has the same distance from each CPU.  
A more common definition is: a block of memory and the CPUs, I/O, etc. physically on the same bus as the memory.

CPU：这个不解释，原因你懂得。想当年CPU拼的是频率，频率越高越NB，但是提升频率和制程密切相关。

![](/images/kernel/2015-02-09-11.jpg)

Intel cpu制程  
但是制程这玩意有一个物理天花板，提升越来越难，有报道指出，现阶段普遍应用的硅晶体管在尺寸上有一个10nm的物理极限。为了提升性能cpu走上了多核的道路，即在一个封装（socket或者processor）里放多个core。这还不够，又发明了超线程技术Hyper-threading

HT：HT Technology is used to improve parallelization of computations (doing multiple tasks at once) performed on PC microprocessors. For each processor core that is physically present, the operating system addresses two virtual or logical cores, and shares the workload between them when possible. They appear to the OS as two processors, thus the OS can schedule two processes at once. 一个core 在HT之后OS看到的就是2个Logical Processor。

下图展示了这些术语之间的逻辑关系：

![](/images/kernel/2015-02-09-12.jpg)

#### cpu 概念逻辑关系
一个NUMA node包括一个或者多个Socket，以及与之相连的local memory。一个多核的Socket有多个Core。如果CPU支持HT，OS还会把这个Core看成 2个Logical Processor。为了避免混淆，在下文中统一用socket指代Processor or Socket;为了偷懒，下文中用Processor指代Logical Processor，击键能省则省不是。

#### 查看CPU Topology
本文以笔者能访问的某台Red Hat Enterprise Linux Server release 5.4为例介绍，其他系统请自行google。

##### NUMA Node
第一种方法使用numactl查看
```
numactl --hardware
available: 2 nodes (0-1)  //当前机器有2个NUMA node,编号0&amp;1
node 0 size: 12091 MB  //node 0 物理内存大小
node 0 free: 988 MB    //node 0 当前free内存大小
node 1 size: 12120 MB
node 1 free: 1206 MB
node distances:        //node 距离，可以简单认为是CPU本node内存访问和跨node内存访问的成本。从下表可知跨node的内存访问成本（20）是本地node内存（10）的2倍。
node   0   1
  0:  10  20
  1:  20  10
```

第二种方法是通过sysfs查看，这种方式可以查看到更多的信息
```
ls /sys/devices/system/node/
1
```
node0  node1 //两个目标表示本机有2个node，每个目录内部有多个文件和子目录描述node内cpu，内存等信息。比如说node0/meminfo描述了node0内存相关信息。

##### Socket
可以直接通过/proc/cpuinfo查看，cpuinfo里的physical id描述的就是Socket的编号，
```
cat /proc/cpuinfo | grep "physical id"
physical id     : 0
physical id     : 0
physical id     : 0
physical id     : 0
physical id     : 1
physical id     : 1
physical id     : 1
physical id     : 1
physical id     : 0
physical id     : 0
physical id     : 0
physical id     : 0
physical id     : 1
physical id     : 1
physical id     : 1
physical id     : 1
```
由上可知本机有2个Socket，编号为0和1。
还可以简单的使用如下命令直接查看Socket个数
```
cat /proc/cpuinfo|grep "physical id" | sort -u | wc –l
2   //本机有2个物理CPU封装
```

##### Core
仍然是可以通过/proc/cpuinfo查看，cpuinfo中跟core相关的信息有2行。
```
cpu cores : 4 //一个socket有4个核，
core id : 1 //一个core在socket内的编号
```
通过如下命令可以直接查看core的数量
```
cat /proc/cpuinfo | grep "cpu cores" | uniq | cut -d: -f2
4  //1个socket有4个core
```

* 本机有2个socket，每个有4个core，所以一共有8个core

还可以查看core在Socket里的编号
```
cat /proc/cpuinfo | grep "core id" | sort -u
core id         : 0
core id         : 1
core id         : 10
core id         : 9
```

一个socket里面4个core的编号为0,1,9,10。是的，core id是不连续的。如果谁知道为啥麻烦通知我，先谢了。

##### Logical Processor
仍然是可以通过/proc/cpuinfo查看在OS的眼里有多少个Logical Processor
```
cat /proc/cpuinfo | grep processor | wc –l
16
```
Ok，8个core变成了16个Logical Processor，所以本机开启了HT。

问题来了，cpuinfo里面16个Processor编号为0-15，Core的id为0,1,9,10，Socket的id为0,1。这些编号是如何对应的呢？

我们查看一个Processor完整的cpuinfo就比较清楚了，我剔除了不相关的行：
```
processor : 0 	processor : 5
physical id : 0
siblings : 8
core id : 0
cpu cores : 4 	physical id : 1
siblings : 8
core id : 1
cpu cores : 4
```
明白了？  
Processor 0:在socket 0的core 0 里。  
Processor 5：在socket 1的core 1 里。  

##### Cache
仍然可以通过/proc/cpuinfo查看，OMG， cpuinfo难道是万能的？
```
processor       : 0
cache size      : 12288 KB //cpu cache 大小
cache_alignment : 64 
```

问题又来了，我们知道CPU cache分为L1，L2，L3, L1一般还分为独立的指令cache和数据cache。Cpuinfo里这个cache size指的是？

好吧，cpuinfo也不是万能的。详细的cache信息可以通过sysfs查看
```
ls /sys/devices/system/cpu/cpu0/cache/
index0  index1  index2  index3
```

4个目录   
index0: 1级数据cache  
index1: 1级指令cache  
index2: 2级cache  
index3: 3级cache ,对应cpuinfo里的cache  

目录里的文件是cache信息描述，以本机的cpu0/index0为例简单解释一下：
<table border="1">
<tr>
<td>文件</td>
<td>内容</td>
<td>说明</td>
</tr>
<tr>
<td>type</td>
<td>Data</td>
<td>数据cache，如果查看index1就是Instruction</td>
</tr>
<tr>
<td>Level</td>
<td>1</td>
<td>L1</td>
</tr>
<tr>
<td>Size</td>
<td>32K</td>
<td>大小为32K</td>
</tr>
<tr>
<td>coherency_line_size</td>
<td>64</td>
<th rowspan="4">64*4*128=32K</th>
</tr>
<tr>
<td>physical_line_partition</td>
<td>1</td>
</tr>
<tr>
<td>ways_of_associativity</td>
<td>4</td>
</tr>
<tr>
<td>number_of_sets</td>
<td>128</td>
</tr>
<tr>
<td>shared_cpu_map</td>
<td>00000101</td>
<td>表示这个cache被CPU0和CPU8 share</td>
</tr>
</table>
<p>解释一下shared_cpu_map内容的格式：<br />
表面上看是2进制，其实是16进制表示，每个bit表示一个cpu，1个数字可以表示4个cpu<br />
截取00000101的后4位，转换为2进制表示</p>
<table border="1">
<tr>
<td>CPU id</td>
<td>15</td>
<td>14</td>
<td>13</td>
<td>12</td>
<td>11</td>
<td>10</td>
<td>9</td>
<td>8</td>
<td>7</td>
<td>6</td>
<td>5</td>
<td>4</td>
<td>3</td>
<td>2</td>
<td>1</td>
<td>0</td>
</tr>
<tr>
<td>0&#215;0101的2进制表示</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>1</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>1</td>
</tr>
</table>

0101表示cpu8和cpu0，即cpu0的L1 data cache是和cpu8共享的。  
验证一下？
```
cat /sys/devices/system/cpu/cpu8/cache/index0/shared_cpu_map
00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000101
```
再看一下index3 shared_cpu_map的例子
```
cat /sys/devices/system/cpu/cpu0/cache/index3/shared_cpu_map
00000000,00000000,00000000,00000000,00000000,00000000,00000000,00000f0f
```
<table border="1">
<tr>
<td>CPU id</td>
<td>15</td>
<td>14</td>
<td>13</td>
<td>12</td>
<td>11</td>
<td>10</td>
<td>9</td>
<td>8</td>
<td>7</td>
<td>6</td>
<td>5</td>
<td>4</td>
<td>3</td>
<td>2</td>
<td>1</td>
<td>0</td>
</tr>
<tr>
<td>0x0f0f的2进制表示</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>1</td>
<td>1</td>
<td>1</td>
<td>1</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>0</td>
<td>1</td>
<td>1</td>
<td>1</td>
<td>1</td>
</tr>
</table>

cpu0,1,2,3和cpu8,9,10,11共享L3 cache

#### 小结
综合以上信息可以绘制出以下的cpu topology图:

![](/images/kernel/2015-02-09-13.jpg)

抱歉，图比较大，网页上看不清楚，下面放大单node图，另一个node基本上可以类推。

![](/images/kernel/2015-02-09-14.jpg)

##### 使用CPU Topology

好吧，现在我们知道了如何查看CPU topology。那么这与各位攻城狮的工作有什么关系呢？

以淘宝搜索常见的服务模型为例，服务端把离线处理的数据load到内存中，开始监听某个服务端口，接收到客户端请求后从线程池中分配一个工作线程，该线程解析请求，读取内存中对应的数据，进行一些计算，然后把结果返回给客户端。

把这个过程简化简化再简化，抽象抽象再抽象，可以得到一个简单的测试程序，程序流程为：  
1. 主线程申请2块256M的内存，使用memset初始化这两块内存的每个byte  
2. 启动2个子线程，每个线程内循环16M次，在每次循环中随机读取2块内存中的各1K数据，对每个byte进行简单加和，返回。  
3. 主线程等待子线程结束，打印每个线程的结果，结束。  
```
	#include <stdio.h>
	#include <pthread.h>
	#include <stdlib.h>
	#include <string.h>

	char *p1, *p2;

	int run(unsigned r)
	{
		    int i,j,k,ret=0;
		    unsigned r1,r2;
		    srand(r);
		    for (i=0;i<(16<<20);i++) {
		            r1 = (unsigned)(rand() % ((256<<20)-(1<<10)));
		            r2 = (unsigned)(rand() % ((256<<20)-(1<<10)));
		            k = 0;
		            for (j=0;j<(1<<10);j++) {
		                    k += *(p1+r1+j);
		                    k += *(p2+r2+j);
		            }
		            ret += k;
		    }
		    return ret;
	}

	int main()
	{
		    int i,j;
		    pthread_t pth1, pth2;
		    p1 = (char*)malloc(256<<20);
		    p2 = (char*)malloc(256<<20);
		    memset(p1, sizeof(p1), 0);
		    memset(p2, sizeof(p2), 0);
		    pthread_create(&pth1, NULL, run, 123);
		    pthread_create(&pth2, NULL, run, 456);
		    pthread_join(pth1, NULL);
		    pthread_join(pth2, NULL);
		    return 0;
	}
```

使用-O2编译出可执行文件test，分别使用下面2个命令运行该程序。运行时间和机器配置以及当前load有关，绝对值没有意义，这里仅比较相对值。
<table border="1">
<tr>
<td>命令</td>
<td>time ./test</td>
<td>time numactl -m 0 &#8211;physcpubind=2,3  ./test</td>
</tr>
<tr>
<td>用时</td>
<td><strong>real    0m38.678s</strong><br />
user    1m6.270s<br />
sys     0m5.569s
</td>
<td><strong>real    0m28.410s</strong><br />
user    0m54.997s<br />
sys     0m0.961s
</td>
</tr>
</table>

发生了什么？为什么有这么大的差异？
第一个命令直观，那么我们看一下第二个命令具体做了什么：
```
	numactl -m 0 --physcpubind=2,3 ./test
	-m 0：在node 0上分配内存
	--physcpubind=2,3：在cpu 2和3上运行程序，即一个线程运行在cpu2上，另一个运行在cpu3上。
```

参考上面的CPUtopology图就很容易理解了，由于线程绑定cpu2和3执行，共享了L3 cache，且全部内存都是本node访问，运行效率自然比随机选择cpu运行，运行中还有可能切换cpu，内存访问有可能跨node的第一种方式要快了。

接下来，让我们看看完整的表格，读者可以看看有没有惊喜：
<table border="1">
<tr>
<td>情况</td>
<td>命令</td>
<td>用时</td>
<td>解释</td>
</tr>
<tr>
<td>完全由OS控制</td>
<td>time ./test</td>
<td>real    0m38.678s<br />
user    1m6.270s<br />
sys     0m5.569s
</td>
<td>乐观主义者，甩手掌柜型</td>
</tr>
<tr>
<td>绑定跨node的Cpu执行</td>
<td>time numactl &#8211;physcpubind=2,6  ./test</td>
<td>real    0m38.657s<br />
user    1m7.126s<br />
sys     0m5.045s
</td>
<td>Cpu 2和6不在同一个node，不能share L3 cache</td>
</tr>
<tr>
<td>绑定单node的Cpu执行</td>
<td>time numactl &#8211;physcpubind=2,3  ./test</td>
<td>real    0m28.605s<br />
user    0m55.161s<br />
sys     0m0.856s
</td>
<td>Cpu 2和3在同一个node，share L3 cache。内存使用由OS控制，一般来说node 0和1内存都会使用。</td>
</tr>
<tr>
<td>跨node内存访问+绑定单node CPU执行</td>
<td>time numactl -m 1 &#8211;physcpubind=2,3  ./test</td>
<td>real    0m33.218s<br />
user    1m4.494s<br />
sys     0m0.911s
</td>
<td>内存全使用node1，2个cpu在node0，内存访问比较吃亏</td>
</tr>
<tr>
<td>单node内存访问+绑定本node CPU执行</td>
<td>time numactl -m 0 &#8211;physcpubind=2,3  ./test</td>
<td>real    0m28.367s<br />
user    0m55.062s<br />
sys     0m0.825s
</td>
<td>内存&amp;cpu都使用node0</td>
</tr>
<tr>
<td>单node内存访问+绑定本node 单core执行</td>
<td>time numactl -m 0 &#8211;physcpubind=2,10  ./test</td>
<td>real    0m58.062s<br />
user    1m55.520s<br />
sys     0m0.270s
</td>
<td>CPU2和10不但在同一个node，且在同一个core，本意是希望共享L1，L2cache，提升性能。但是不要忘了，CPU2和10是HT出来的logical Processor，在本例cpu密集型的线程中硬件争用严重，效率急剧下降。有没有发现和上一个case的时间比率很有意思？</td>
</tr>
</table>

现在谁还能说了解点cpu topology没用呢？☺

#### Tips
补充几个小tips，方便有兴趣的同学分析上面表格的各个case
##### 1.查看进程的内存numa node分布

简单的说可以查看进程的numa_maps文件
```
cat /proc/pid/numa_maps
```
文件格式可以直接：man numa_maps  
为了避免输入数字pid，我使用如下命令查看：
```
cat /proc/$(pidof test|cut –d” ” -f1)/numa_maps
```

##### 2.查看线程run在哪个processor
可以使用top命令查看一个进程的各个线程分别run在哪个processor上  
同样，为了避免输入数字pid，我使用如下命令启动top：
```
top -p$(pidof test |sed -e ‘s/ /,/g’)
```
在默认配置下不显示线程信息，需要进入Top后按“shift+H”，打开线程显示。  
另外，如果没有P列，还需要按“f”，按“j”，添加，这一列显示的数字就是这个线程上次run的processor id。  
关于top的使用，请读者自行man top

##### 3.另一种绑定cpu执行的方法
如果读者的程序不涉及大量内存的访问，可以通过taskset绑定cpu执行。别怪我没提醒你，仔细判断是否应该绑定到同一个core的processor上哦。  
关于命令的使用，请读者自行Man taskset

