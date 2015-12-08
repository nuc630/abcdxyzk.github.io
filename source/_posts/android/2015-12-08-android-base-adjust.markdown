---
layout: post
title: "Android 系统基本"
date: 2015-12-08 15:20:00 +0800
comments: false
categories:
- 2015
- 2015~12
- android
- android~base
tags:
---
http://tieba.baidu.com/p/2687199243?see_lz=1


### 二、锁定频率和核心

#### 1. 了解热插拔

热插拔驱动（Hotplug Driver）是控制cpu负载控制核心上线下线的驱动

注意：所有热插拔驱动都是根据负载调节cpu上下线，只是策略有不同。这不是“高通异步专利”


##### 高通机器默认热插拔：mpdecision
```
	/system/bin/mpdecision
```

这个热插拔驱动其实工作的蛮不错的。各个厂商之间略会有不同。个人建议使用8064以后机器的不使用第三方的热插拔驱动

##### Exynos机器热插拔：pegasusq
三星的热插拔驱动是集成在了governor（调速器）中的，这个调速器可以看作ondemand＋hotplug，工作方式为多核低频

##### Tegra机器热插拔：hotplug
两个字：渣渣  
建议使用开发者开发的热插拔驱动


#### 2. 如何锁定cpu核心

方法1: 使用kernel tuner

方法2: 使用脚本(只针对高通机器)：

```
	#!/system/bin/sh

	stop mpdecision
	echo 0 > /sys/devices/system/cpu/cpu1/online
	chmod 444 /sys/devices/system/cpu/cpu1/online
	echo 0 > /sys/devices/system/cpu/cpu2/online
	chmod 444 /sys/devices/system/cpu/cpu2/online
	echo 1 > /sys/devices/system/cpu/cpu3/online
	chmod 444 /sys/devices/system/cpu/cpu3/online
```

注意： 这样做将没有热插拔驱动工作，在空载时依然会有两个核心上线


#### 3. 如何锁定频率

##### （1）锁定cpu频率

步骤1: 将governor设置为performance

方法很简单，用fauxclock，trickester mod，kernel tuner都可以搞定，并且不占用资源采样负载

弊端：如果不修改温度配置文件，将会受到降频影响


步骤2: 修改权限让温控进程无法对其降频

```
	#!/system/bin/sh
	echo 你的cpu的最大频率 > /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	echo 你的cpu的最大频率 > /sys/devices/system/cpu/cpu1/cpufreq/scaling_max_freq
	chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	echo 你的cpu的最大频率 > /sys/devices/system/cpu/cpu2/cpufreq/scaling_max_freq
	chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
	echo 你的cpu的最大频率 > /sys/devices/system/cpu/cpu3/cpufreq/scaling_max_freq
	chmod 444 /sys/devices/system/cpu/cpu0/cpufreq/scaling_max_freq
```

注意：cpu频率以khz为单位，比如1728mhz应该在这里写为1728000


##### (2)锁定gpu频率
步骤1: 将governor设置为performance

方法很简单，用fauxclock，trickester mod，kernel tuner都可以搞定，并且不占用资源采样负载

弊端：如果不修改温度配置文件，将会受到降频影响


```
	echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	echo performance > /sys/devices/system/cpu/cpu1/cpufreq/scaling_governor
	echo performance > /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor
	echo performance > /sys/devices/system/cpu/cpu3/cpufreq/scaling_governor
```


步骤2:
```
	echo 你的gpu的最大频率 > /sys/devices/platform/kgsl-3d0.0/kgsl/kgsl-3d0/max_gpuclk
	chmod 444 /sys/devices/platform/kgsl-3d0.0/kgsl/kgsl-3d0/max_gpuclk
```

注意：gpu频率以hz为单位，比如400mhz应该在这里写为400000000

#### 4. 关于锁定频率的看法
锁定频率对游戏性能很重要。根据我目前的结果来看，1.7g的krait 300似乎已经有点拖不动adreno 320了，而且随着频率降低，帧数跟着降低。但是对于日常使用来说，高频率只是一瞬间的事，并不需要多久，长期高频率对电池和发热的影响都会非常大。不推荐锁频，除非你要作性能测试


### 三、在调节linux设置

#### 1. governor

(1) 什么是governor

governor大多数中文翻译为调速器，也叫调速策略。故名思议，根据cpu负载不同而如何决定提升或者降低频率靠的就是governor

(2) 为什么governor很重要

随着linux内核的更新，governor也会带来许多新功能来提升用户体验、响应速度、省电等。另外不同厂商对于不同governor的优化也是不同的。比如高通，对ondemand/msm-dcvs的优化非常好，然而对于小米用的interactive确实基本没怎么优化，在高通内核中的interactive非常之老旧，对于性能和省电都不利。在游戏中，htc的ondemand表现非常捉急，在需要提升频率的时候还按着不动，从而导致掉帧、顿卡等。切换到performance或者msm－dcvs会好不少。代表：riptide gp， asphalt 8，real racing 3

(3) 安卓上常见governor种类
##### cpu：

ondemand 故名思议，按需。ondemand根据cpu的负载来决定提升和降低频率，工作方式比较简单，也是最常见的一个governor

interactive 故名思议，交互。这个governor重点就是注重交互时的体验，它会比ondemand更快地提升到最高频率，而在降频时确实按照设定的时间慢慢地降。这么做会让系统很流畅，电量嘛，你懂的。

conservative 这个governor被开发者戏称为slow ondemand，它为了节电会限制cpu频率的提升，结果就是卡

performance 一直最高频

powersave 一直最低频

userspace 这个governor实质上就是让软件设定频率。比如在运行stability scaling test的时候，软件就会将其设为userspace

intellidemand intellidemand是faux123基于ondemand开发的一个governor，它和ondemand的主要区别就是在浏览网页的时候会限制频率，然后配合faux的热插拔驱动intelli-plug会获得比较好的省电效果

pegasusq 三星基于ondemand开发的热插拔governor

msm-dcvs msm（高通处理器前缀）－dcvs（dynamic clock & voltage scaling 动态频率电压调整）
这个governor是高通给krait架构开发的，具体有什么魔力我也不清楚，只是用它玩游戏的时候感觉比ondemand流畅多了


##### gpu：

ondemand 这个和cpu的是一样的，按需调整，根据负载决定频率

performance 永远最大频率

simple 这个governor是faux123对adreno 3xx开发的一个governor，其中参数有laziness和thresholds。前者数值分布1-10，决定的是忽略多少降频请求，数字越大性能和耗电都越高；后者是提升频率的阀值，即gpu达到多少负载提升频率，数值分布0-100，数字越大性能和耗电都越低


(3) 如何切换

最简单的当然是在fauxclock，trickester mod等软件里面切换

cpu：

```
	echo 你的governor > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
	echo 你的governor > /sys/devices/system/cpu/cpu1/cpufreq/scaling_governor
	echo 你的governor > /sys/devices/system/cpu/cpu2/cpufreq/scaling_governor
	echo 你的governor > /sys/devices/system/cpu/cpu3/cpufreq/scaling_governor
```

gpu：

```
echo 你的governor > /sys/devices/platform/kgsl-3d0.0/kgsl/kgsl-3d0/pwrscale/trustzone/governor
```

#### 2. io scheduler

中文名：输入输出 调度器/io 调度器

(1) 为什么io scheduler很重要

io scheduler完全决定了磁盘的读写性能，而这对于用户体验的影响是极大打


(2) 安卓上常见io scheduler

##### cfq

completely-fair-quening

完全公平队列，是anticipatory模式的替代品，没有过多的做预测性调度，而是根据给定的进程io优先级，直接来分配操作的顺序。这个模式在linux上表现良好，但也许并不是最适合android的io调度模式，太强调均衡，而降低了连续读写数据的性能。

高通默认的就是这个，强烈建议改掉，根本不适合移动设备

##### noop

这个调度模式会把所有的数据请求直接合并到一个简单的队列里。不适合有机械结构的存储器，因为没有优化顺序，会增加额外的寻道时间。属于最简单的一个调度模式，无视io操作优先级和复杂性，执行完一个再执行一个，如果读写操作繁多的话，就会造成效率降低。

nvidia默认，有时候会造成顿卡，但是听说这个scheduler对省电比较有帮助

##### deadline
顾名思义，用过期时间来排序io操作顺序，保证先出现的io请求有最短的延迟时间，相对于写操作，给读操作更优先的级别。是比较好的一个调度模式。

性能不错

##### row
read over write

顾名思义，这个scheduler会优先处理读的请求。在移动设备上读的请求远远多于并且重要于写的请求，并且随机读取速度很重要。这个governor允许单或者双线程的读写，在同时有读写的情况下优先保证读，比较适合移动设备。

##### fiops
fair-iops
这个调度器虽然和cfq一样追求平均的优先级，但是是根据闪存设备重新设计的一个governor，各方面表现良好，是我列出来的五个scheduler里面性能最好的一个

如果有，强烈推荐fiops

##### sio
simple－io
在安卓上其实调度器越简单效果越好。sio就是最简单的一个调度器。不过还是有缺点的，就是随即读写性能不太好。在fiops出来以后，这个scheduler基本就被冷落了


#### 3. read ahead buffer
这个其实奇怪。按理说缓存应该是越大越好，但是在安卓上好像不是这样，是越大越省电，越小系统越流畅，具体原理我也不懂。只列下方法

依旧，fauxclock，trickester mod等可以修改

命令：

emmc内置闪存：
```
	echo 你想要的大小 > /sys/block/mmcblk0/quene/read_ahead_kb
```

sd卡：
```
	echo 你想要的大小 > /sys/block/mmcblk1/quene/read_ahead_kb
```

默认为128k，如果想省电可以设成2048k

#### 4. emmc entropy

entropy是一个叫混乱度的东西，好像是物理化学里面的，根据faux123的解释，闪存设备根本不需要entropy，所以就把它关掉来提高性能

fauxclock里面可以关闭

命令
```
	echo 0 > /sys/block/mmcblk0/quene/add_random
	echo 0 > /sys/block/mmcblk1/quene/add_random
```

#### 5. c-states
高通从krait 200上引进，但是有bug，在krait 300上得到了修复

总共4个状态：

c0, wfi  
c1, rentention  
c2, standalone_power_collapse  
c3, power_collapse  

数字从低到高代表了睡眠程度的高低，数字越高的状态越省电

intel也有这个，haswell就是凭借着强大的c－states调整在tdp更高的情况下获得了更低的耗电和更长的续航。桌面上比如e3可以将c6状态打开，能在0.8v左右稳定在3.3g

高通的c－states和intel不一样，在平时工作的时候高通处理器进入c states的时间很少，主要集中在关屏深睡眠的时候

fauxclock可以打开，krait 300建议打开c0 c2 c3

命令：
```
	echo 1 > /sys/module/pm_8x60/modes/cpu0/wfi/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu1/wfi/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu2/wfi/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu3/wfi/idle_enabled
	echo 0 > /sys/module/pm_8x60/modes/cpu0/retention/idle_enabled
	echo 0 > /sys/module/pm_8x60/modes/cpu1/retention/idle_enabled
	echo 0 > /sys/module/pm_8x60/modes/cpu2/retention/idle_enabled
	echo 0 > /sys/module/pm_8x60/modes/cpu3/retention/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu0/standalone_power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu1/standalone_power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu2/standalone_power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu3/standalone_power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu0/power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu1/power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu2/power_collapse/idle_enabled
	echo 1 > /sys/module/pm_8x60/modes/cpu3/power_collapse/idle_enabled
```

#### 6. 不同的构图方式

从Android 4.0以后大家可以从build.prop里面发现这么几行：
```
	debug.sf.hw=1
	debug.composition.type=gpu
```

在4.2以后还可以看到这一行
```
	persist.hwc.mdpcomp.enable=true
```
这就是构图方式

从谷歌4.2的build.prop的变化来看，谷歌已经开始强制使用mdp。性能更强但是耗电更低，何乐而不为

##### (1) 构图方式种类

cpu: 故名思议，cpu构图

gpu: gpu构图，在开发者选项中选择“关闭hw叠加层”和只设置debug.sf.hw=1都是让gpu构图

c2d: c2d构图，这个在2.x时代就已经被抛弃了，比gpu构图还烂

dyn: 这个似乎不错，但是所有高通机器的rom里面只有one的cm在用这个，而且开发者对这个构图方式的看法褒贬不一，就连这个选项是否生效都有争议。

mdp: 从firefox的开发者那里得知，新一点的机器都是有mdp管线的，比gpu构图性能更强、更省电。谷歌也因此强制使用这个构图方式

##### (2) 构图方式的影响

最常见的影响当然就是fps meter打开变卡了

firefox开发者的解释： https://bugzilla.mozilla.org/show_bug.cgi?id=911391

当叠加层数量低于mdp管线数量的时候，所有的构图都用mdp完成，不仅性能比gpu构图更好，而且还更省电。但是一旦叠加层数量超过mdp管线的数量，系统就会自动使用“部分mdp构图”，实质上就是要mdp和gpu合作构一帧的图。那么这个时候，就会导致性能下降

为什么打开一些overlay软件就变卡了呢？这就说明打开这类软件以后，比如fps meter，整个图层的数量已经超过了mdp的管线数量，系统启用gpu构图，导致系统、游戏流畅度下降。为什么有些人开始还不觉得fps meter对性能有影响呢？原因可能有三个：1. 他们还在4.2以下，还没用过mdp，一直都在用gpu构图；2. 他们一直都关掉了hw叠加层，也是一直用gpu构图，所以无法感知gpu构图对系统流畅度的严重影响；3. 他们打开了一些overlay软件，但是没有超过mdp的管线数量，没有进入gpu构图


构图的影响还不止这些，如果有人有one，可以试试把这一行
```
	persist.hwc.mdpcomp.enable=true
```

从build.prop里面删掉

重启以后，反复按app抽屉的图标，对比与没删之前的流畅度。另外在贴吧等软件中，mdp构图也会增加滑动的流畅度。至于视频：1. 我没有高速摄像机；2. 这是非常容易感知的问题，耍赖不承认我是没办法的

mdp的缺点：

对于一些老的应用，mdp会造成负面影响，对流畅度负加成：比如在使用老版re管理器的时候，转移到多任务界面会有卡顿，而新版则非常流畅。
在叠加层数量超过mdp管线数量的时候，会转为“部分mdp构图”，mdp管线和gpu合作构图

不过谷歌已经强制使用mdp，随着软件更新，更快更省电的mdp构图将会逐渐替代gpu构图


### 四、关于作弊
很多厂商被逮着了“作弊”，其实我觉得根据不同的app调整策略不是坏事，但是你不开放给用户那就有问题了。凭什么只能跑分得到这样的待遇？厂商真的应该好好反思

1.作弊文件位置：

三星： TwDVFSApp.apk

HTC: /system/bin/pnpmgr; /system/etc/pnp.xml

NVIDIA：/system/app/NvCPLSvc.apk/res/raw/tegraprof.txt

2.如何对待？

作弊固然可耻，但是干掉这些东西又不是明智的选择。虽然这些文件有对跑分的专门配置和优化，但是它们还对普通应用程序/游戏有着配置。比如pnpmgr，它管理者省电模式、touch_boost、60fps视频cpu提频等等非常有用的调整；比如tegraprof，这里面更是有不少针对游戏优化的配置文件。关掉它们只会给用户体验减分。我希望所有厂商能够开放配置，让用户自由定制，而不是现在的加密处理。


### 五、关于测试的一些注意事项

1. 注明机型，驱动版本，系统版本，内核类型（是官方还是第三方，编译器是什么。换一个编译器可以让某些性能差别达到20%）构图方式

2. 不要在开启fps meter的同时打开其他悬窗监控软件。fps meter统计的是整个图层的平均帧数，开启其他悬窗监控软解无论刷新率调到多少都是不准的（除非overlay在fps meter上面）

3. 测试的时候最好关掉温度进程，以防止意外降频

4. 对比测试的时候注意变化量，在变化量超过一个的时候对比测试结果不可信

5. 如果想反映整个游戏的帧数情况，用Adreno Profiler。在没有高速摄像机的情况下，这个比视频靠谱得多。https://developer.qualcomm.com/mobile-development/mobile-technologies/gaming-graphics-optimization-adreno/tools-and-resources


### 一、温度控制
很多人抱怨手机降频，其实这不是坏事，降频厉害，也是oem厂商所为，与soc厂商关系不是太大

可能抱怨最多的就是高通机器了，这里讲下高通机器的温度控制进程的基本调试

#### 1. 开启和关闭温控进程

关闭：
```
	stop thermald
```

开启：
```
	start thermald
```

##### 注意事项：
关闭温控以后，除非内核中也有温度保护，机器将不会降频，散热设计不好的机器很有可能因此烧毁。请谨慎考虑关闭温控进程

#### 2. 降频阀值的调整

##### （1）了解自己手机的传感器

方法1：使用last_kmsg
```
	adb pull /proc/last_kmsg
```
在adb目录下，找到last_kmsg文件，用记事本（推荐用notepad++/notepad2）打开，搜索sensor

方法2: 使用cat命令逐个查看
```
	cat /sys/devices/virtual/thermald/thermald_zone*/temp
```
显示出的数值即该传感器的温度

毫无疑问，温度最高的那几个就是cpu温度传感器

#### （2）了解thermald配置文件
配置文件的路径在 /system/etc/thermald.conf，权限为644

##### 注意：
对于大部分高通机器，打开即可编辑。对于HTC机器，这个文件是加密的，只能自己写。

对于三星的机器，这个文件会是一个软链，比如E330S软链到了thermald－8974.conf文件，那么你真正应该修改的文件则是thermald－8974.conf

####（3）获取频率表
获取cpu频率表：
```
	cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_frequencies
```

获取gpu频率表：
```
	cat /sys/devices/platform/kgsl-3d0.0/kgsl/kgsl-3d0/gpu_available_frequencies
```

注意：
部分三星机器，比如E330S无法查看gpu频率

#### （4）自己改写thermald.conf
步骤1: 了解thermald.conf的语言

```
	sampling：采样时间
	[tsen_tz_sensor*]：对于＊号传感器的配置
	thresholds：降频阀值，达到这个温度即降频
	thresholds_clr：恢复阀值，达到这个温度即恢复到上一阶段配置的频率
	actions：降频所采取的行动
	cpu：降频cpu
	gpu：降频gpu
	shutdown：关机
	lcd：改变屏幕亮度，＋255最大
	battery：不懂，但可以知道的是＋1和＋2，能降低温度
	action_info：定义具体降频到多少
```

步骤2: 定义总采样时间
```
	sampling 5000
```
数值越低采样越勤，也越耗费资源。不建议修改


步骤3: 定义传感器
```
	[tsens_tz_sensor7]
	sampling 1500
	thresholds 54 57 64 70 75
	thresholds_clr 51 54 57 64 70
	actions gpu+cpu gpu+cpu cpu cpu cpu
	action_info 400000000+1728000 320000000+1134000 1026000 918000 702000
```

步骤3.1：定义所需要的传感器

在你获得的传感器中，选择所需要的传感器。据我所知，绝大多数高通机器打sensor7, sensor8, sensor9都是cpu温度传感器，若要使用其他温度传感器，直接修改这个数字即可

步骤3.2：定义该传感器的采样时间

sampling 1500

数值越低，采样越勤，不建议修改

步骤3.3: 修改触发行为的温度阀值，即高于这个设定的温度就会采用当前定义的行为，比如降频

thresholds 54 57 64 70 75

步骤3.4: 修改回到上一行为的温度阀值，即低于这个设定温度就会回到上一个温度阀值所定义的行为（shutdown命令除外）

thresholds_clr 51 54 57 64 70

步骤3.5: 定义行为，最常见的就是cpu，gpu，shutdown，若要定义多个行为，则用加号相连

actions gpu+cpu gpu+cpu cpu cpu cpu

步骤3.6: 定义所采取的行为的具体数值，即降频降到多少。

action_info 400000000+1728000 320000000+1134000 1026000 918000 702000

注意： 其数值顺序必须与actions的顺序一模一样，最好与cpu和gpu频率表一致，否则容易出错。千万不要像三星官方一样敷衍了事。


#### 3. 关于降频的看法
个人认为降频并不是一件坏事，在soc发热越来越大的今天，降频是厂商保证用户体验的一种方式之一：降低发热，降低耗电

但是我希望每个厂商都能像小米一样开发不同的模式，在需要降频省电的时候用一套温控配置，在需要性能的时候用另一套温控配置；而大多数国际厂商，比如三星，htc，nvidia，仅仅在跑分的时候使用了更高的温度配置，而且是用户无法选择的。这种行为应该表示抗议！强烈谴责！


