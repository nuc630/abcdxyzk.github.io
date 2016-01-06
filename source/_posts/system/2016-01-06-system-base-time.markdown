---
layout: post
title: "linux系统时间和硬件时钟问题(date和hwclock)"
date: 2016-01-06 10:48:00 +0800
comments: false
categories:
- 2016
- 2016~01
- system
- system~base
tags:
---

http://rpf413.blog.163.com/blog/static/4556376020122831444674/

#### 总结一下hwclock，这个容易晕：
1）/etc/sysconfig/clock 文件，只对 hwclock 命令有效，且只在系统启动和关闭的时候才有用（修改了其中的 UTC=true 到 UTC=false 的前后，执行 hwclock (`--utc`, 或 `--localtime`) 都没有变化，要重启系统后才生效）；

2）/etc/rc.d/rc.sysinit 文件，run once at boot time，其中有从硬件时钟同步时间到系统时间的操作；

3）`hwclock --localtime` 的输出，才是硬件时钟真正的时间。如果输出结果带时区（比如CST），还要看/etc/sysconfig/clock里的UTC参数，如果 UTC=false，那时区有意义；如果 UTC=true，那时区没意义，实际上是UTC时间。

4）在 /etc/sysconfig/clock 中 UTC=false 时，date、hwclock、`hwclcok --localtime` 输出的时间应该都一致，且此时 `hwclock --utc`是没有意义的；

5）在 /etc/sysconfig/clock 中 UTC=ture 时，date、hwclock 的输出是一致的，`hwclock --localtime` 的输出则是UTC时间；

6）如果不想在输出中带时区，则 export LANG=C ，然后再运行 hwclock 就没有什么CST了，免得时区误导你；

7）`hwclock --utc` 很闹腾，还是别看了，你会晕的。。。

8）系统关闭时会同步系统时间到硬件时钟，系统启动时会从硬件时钟读取时间更新到系统，这2个步骤都要根据 /etc/sysconfig/clock 文件中UTC的参数来设置时区转换。

#### 实际案例分析
修改了 /etc/sysconfig/clock 中UTC参数但系统未正常关闭的情况

修改 /etc/sysconfig/clock 文件后，如果系统内核突然崩溃，然后直接按电源重启，则系统没有进行 系统时间到硬件时钟的 同步；但是 系统启动时，又根据 /etc/sysconfig/clock 中UTC的参数，来同步硬件时钟到系统，这时就会出现时间问题：

0）假设系统的时区为CST（UTC+8）；  
1）假设原 /etc/sysconfig/clock 中 UTC=true，修改成 UTC=false；  
2）如果此时系统未正常关机，系统时间未按参数 UTC=false 同步时间到硬件时钟（没有+8小时）；  
3）但系统被按电源重启后，系统读取到 UTC=false，认为硬件时钟为CST时间，直接用于系统时间；  
4）那么此时，系统时间将少了8小时。  

=======================================================

http://hi.baidu.com/lujunqianglw/blog/item/bc2d9144d24fc48fb3b7dc1d.html

#### 一、首先要弄清几个概念：

##### 1. “系统时间”与“硬件时间”
系统时间: 一般说来就是我们执行 date 命令看到的时间，linux系统下所有的时间调用（除了直接访问硬件时间的命令）都是使用的这个时间。

硬件时间: 主板上BIOS中的时间，由主板电池供电来维持运行，系统开机时要读取这个时间，并根据它来设定系统时间（注意：系统启动时根据硬件时间设定系统时间的过程可能存在时区换算，这要视具体的系统及相关设置而定）。

##### 2. “UTC时间”与“本地时间”
UTC时间：Coordinated Universal 8 e2 i( H7 t0 ^/ ^Time 世界协调时间（又称世界标准时间、世界统一时间），在一般精度要求下，它与GMT（Greenwich Mean Time，格林威治标准时间）是一样的，其实也就是说 GMT≈UTC，但 UTC 是以原子钟校准的，更精确。

本地时间：由于处在不同的时区，本地时间一般与UTC是不同的，换算方法就是

本地时间 = UTC + 时区 或 UTC = 本地时间 - 时区

时区东为正，西为负，例如在中国，本地时间都使用北京时间，在linux上显示就是 CST（China Standard Time，中国标准时，注意美国的中部标准时Central Standard Time也缩写为CST，与这里的CST不是一回事！），时区为东八区，也就是 +8 区，所以 CST=UTC+(+8小时) 或 UTC=CST-(+8小时)。

#### 二、时间命令

##### 1. 系统时间 date
直接调用 date，得到的是本地时间。如果想得到UTC时间的话，使用 date -u。
```
	[12-01 19:07> ~]$ date
	2009年 12月 07日 星期一 14:22:20 CST
	[12-01 19:07> ~]$ date -u
	2009年 12月 07日 星期一 06:22:22 UTC
```

##### 2. 硬件时间 /sbin/hwclock
直接调用 /sbin/hwclock 显示的时间就是 BIOS 中的时间吗？未必！这要看 /etc/sysconfig/clock 中是否启用了UTC，如果启用了UTC（UTC=true），显示的其实是经过时区换算的时间而不是BIOS中真正的时间，如果加上 --localtime 选项，则得到的总是 BIOS 中实际的时间.

```
	[12-01 19:07> ~]# hwclock
	2009年12月07日 星期一 14时28分43秒 -0.611463 seconds
	[12-01 19:07> ~]# hwclock --utc
	2009年12月07日 星期一 14时28分46秒 -0.594189 seconds
	[12-01 19:07> ~]# hwclock --localtime
	2009年12月07日 星期一 06时28分50秒 -0.063875 seconds
```

##### 3. /etc/localtime
这个文件用来设置系统的时区，将 /usr/share/zoneinfo/ 中相应文件拷贝到/etc下并重命名为 localtime 即可修改时区设置，而且这种修改对 date 命令是及时生效的。不论是 date 还是 hwclock 都会用到这个文件，会根据这个文件的时区设置来进行UTC和本地之间之间的换算。

##### 4. /etc/sysconfig/clock
这个文件只对 hwclock 有效，而且似乎是只在系统启动和关闭的时候才有用，比如修改了其中的 UTC=true 到 UTC=false 的前后，执行 hwclock (`--utc`, 或 `--localtime`) 都没有变化，要重启系统后才生效。注：如果设置 UTC=false 并重启系统后,执行一些命令结果如下：

```
	date 2009年 12月 07日 星期一 19:26:29 CST
	date -u 2009年 12月 07日 星期一 11:26:29 UTC
	hwclock 2009年12月07日 星期一 19时26分30秒 -0.442668 seconds
	hwclock --utc 2009年12月08日 星期二 03时26分31秒 -0.999091 seconds
	hwclock --localtime 2009年12月07日 星期一 19时26分32秒 -0.999217 seconds
```

可见，如果不使用UTC，BIOS时间（红色部分）就是系统本地时间，而且注意这时执行 `hwclock --utc` 得到的结果没有任何意义，因为这里我们已经禁用了UTC，而且也明显不符合“本地时间=UTC+时区”的关系。

#### 三、linux与windows双系统间的时间同步
系统启动和关闭时，硬件时间与系统时间之间的同步有两种方式(假设在中国，用CST代表本地时间)：

方式A: 使用UTC（对linux就是 /etc/sysconfig/clock 中 UTC=true）

开机: BIOS------->UTC（将BIOS中的时间看成是UTC）------(时区变化)----->CST  
关机: CST -------(时区变化)----->UTC-------存储到------>BIOS  

方式B: 不使用UTC（对linux就是 /etc/sysconfig/clock 中 UTC=false）

开机: BIOS--------------------->CST（将BIOS中的时间看成是CST）  
关机: CST ---------存储到------>BIOS  


--------
FIX:

方式A: 使用UTC（对linux就是 /etc/sysconfig/clock 中 UTC=true）

关机: CST -------操作系统根据时区算出UTC时间-------存储到------>BIOS  
开机: BIOS------->BIOS中的时间是UTC-----------操作系统根据时区计算出localtime----------CST  

方式B: 不使用UTC（对linux就是 /etc/sysconfig/clock 中 UTC=false）

关机: CST --------操作系统中UTC=false，直接将localtime存储到------>BIOS  
开机: BIOS--------BIOS中的时间是localtime-----操作系统中UTC=false，BIOS时间当成localtime-------->CST（将BIOS中的时间看成是CST）  


--------


通过设定 /etc/sysconfig/clock，linux可以支持这两种方式，然而windows只支持方式B（至少是默认支持B，而我不知道怎么能让它支 持A），那么在双系统情况下，如果linux设成A方式，那么在linux与windows系统切换时一定会造成时间混乱的，解决办法就是将linux中 的UTC禁用，也设成B方式就可以了。

注：可以通过 `hwclock --hctosys` 来利用硬件时间来设置系统时间（注意不是简单的复制BIOS中的时间为系统时间，要看是否使用UTC，如果使用的话则要做时区换算），通过 `hwclock --systohc` 来根据系统时间设置硬件时间（也要看是否启用UTC来决定是否做时区换算）。

总之，不论使用 `--systohc` 还是 `--hctosys`，同步后直接运行不带参数的 hwclock 得到的时间与直接运行 date 得到的时间应该一致，这个时间是否就是BIOS中的时间（`hwclock --localtime`)那就不一定了，如果启用了UTC就不是，没启用UTC就是。

而且还要注意：在系统中手动使用 `hwclock hwclock --set --date='yyyy-mm-dd'` 来设置BIOS时间只在系统运行时有效，因为当系统关闭时，还会按设定好的方式根据系统时间来重设BIOS时间的，于是手动的设置便被覆盖掉了。


