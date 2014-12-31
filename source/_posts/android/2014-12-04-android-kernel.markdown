---
layout: post
title: "编译Android的kernel"
date: 2014-12-04 17:34:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~base
tags:
---
#### 一 下载
0.  下载arm编译器  
https://launchpad.net/gcc-arm-embedded/+download

1.  进入到你的android源代码目录，敲入下面命令：  
git clone http://android.googlesource.com/kernel/goldfish.git kernel

2.  cd kernel  进入我们刚才创建的kernel文件夹

3.  git branch -avv 查看远程的git 库  
我们选择remotes/origin/android-goldfish-2.6.29分支来下载

4.  git checkout -b android-goldfish-2.6.29 remotes/origin/android-goldfish-2.6.29


#### 二  编译kernel代码

1.  设置环境变量  
export PATH=$PATH:~/andr-perf/gcc-arm-none-eabi-4_8-2014q3/bin

2.  修改kernel下面的makefile文件，修改  
ARCH        ?= $(SUBARCH)  
CROSS_COMPILE    ?=  
这两个字段成如下内容：  
ARCH        ?= arm  
CROSS_COMPILE    ?= arm-none-eabi-  
// 但是对于make goldfish_armv7_defconfig这样编译的内核模拟器好像启动不了，应该是默认编译成v5的，需要改成v7。或者可以改成ndk的编译器  
// CROSS_COMPILE   ?= /home/kk/andr-perf/android-ndk-r10c/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-

3.  开始编译,敲入如下命令  
make goldfish_defconfig  
或者看arch/arm/configs/目录下有什么，就挑一个make XXX

4.  正式编译,敲入如下命令  
make


正式编译成功之后，我们会看到如下文字：  
OBJCOPY arch/arm/boot/zImage  
Kernel: arch/arm/boot/zImage is ready


#### 三  利用新编译的kernel来启动模拟器

1. 在启动模拟器之前，先设置模拟器的目录到环境变量$PATH中去：  
     USER-NAME@MACHINE-NAME:~/Android$ export PATH=$PATH:~/android_prj/out/host/linux-x86/bin

2. 设置ANDROID_PRODUCT_OUT环境变量：  
  USER-NAME@MACHINE-NAME:~/Android$ export ANDROID_PRODUCT_OUT=~/android_prj/out/target/product/generic  
  同样，如果你的源代码目录不是android_prj，请注意修改下。另外，如果你已经配置了环境变量。则不必如此。建议最好写到配置文件 ~/.bash_rc配置文件里面去。 免得每次都要配置

3. 启动模拟器  
一、
cd ~/android_prj  回到源代码目录  
sandy@ubuntu:~/android_prj$ emulator -kernel ./kernel/arch/arm/boot/zImage 利用刚才我们编译的kernel内核启动模拟器  
二、
emulator -avd myavd -kernel ~/goldfish/arch/arm/boot/zImage  
-avd后面的参数 myavd即为模拟器的名字，-kernel后面的参数就找到刚才编译出的内核的路径。  
若启动模拟器失败，可尝试关闭后再启动。第一次启动模拟器时可能需要等待比较长的时间，3分钟到15分钟不等。  

4. 验证结果  
待模拟器启动完毕之后，我们敲入adb shell  
第一次会说device offline，不管它，再敲入一遍，就会进入adb 调试  
然后cd proc 进入proc目录，cat version 

