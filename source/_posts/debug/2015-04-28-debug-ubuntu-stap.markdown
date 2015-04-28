---
layout: post
title: "ubuntu安装systemtap"
date: 2015-04-28 14:42:00 +0800
comments: false
categories:
- 2015
- 2015~04
- debug
- debug~systemtap
tags:
---
http://blog.csdn.net/ustc_dylan/article/details/7079876

#### 1. 从源安装systemtap
```
	$ sudo apt-get install systemtap
```

#### 2. 安装kernel-debug-info
由于ubuntu 桌面版默认没有安装kernel-debug-info，所以安装了systemtap后仍然不能够追踪内核信息，因此需要手动安装kernel-debug-info包。

##### （1）查看当前内核版本
```
	$ uname -a
	Linux kk-desktop 2.6.32-73-generic #141-Ubuntu SMP Tue Mar 10 17:15:10 UTC 2015 x86_64 GNU/Linux
```

##### （2）下载对应内核版本的debug-info package

http://ddebs.ubuntu.com/pool/main/l/linux/

http://ddebs.ubuntu.com/pool/main/l/linux/linux-image-2.6.32-73-generic-dbgsym_2.6.32-73.141_amd64.ddeb

#### 3. 安装kernel-debug-info
```
	$ sudo dpkg -i linux-image-2.6.32-73-generic-dbgsym_2.6.32-73.141_amd64.ddeb
```

经过以上安装配置后，就可以跟踪监控内核信息了，但是现在还不能跟踪linux内核模块的信息，因为，systemtap对linux内核模块的跟踪是通过libelf库来查找
/usr/lib/debug目录下以.ko.dedug结尾的模块，但是linux发行版通常将linux模块的扩展名修改为.ko。


#### 4. 安装elfutils并进行相应配置
```
	$ sudo apt-get install elfutils
```
```
	# 这些似乎不用
    for file in `find /usr/lib/debug-name'*.ko' -print`
        do
        buildid=`eu-readelf-n $file| grep Build.ID:| awk '{print $3}'`
        dir=`echo $buildid| cut-c1-2`
        fn=`echo $buildid| cut-c3-`
        rm -fr /usr/lib/debug/.build-id
        mkdir -p/usr/lib/debug/.build-id/$dir
        ln -s $file/usr/lib/debug/.build-id/$dir/$fn
        ln -s $file/usr/lib/debug/.build-id/$dir/${fn}.debug
        done
```

#### 5. 写个例子测试下
```
	$ sudo stap -ve 'probe begin { log("hello world") exit() }'
```
如果能够打印出hello world，说明安装配置成功!

