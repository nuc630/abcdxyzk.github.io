---
layout: post
title: "完整版刷android内核及定制内核模块攻略"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android～Moto
tags:
---
blog.sina.com.cn/s/blog_706845a5010129da.html

终于很恶心的把流程走通了

首先列出需要的东西，从网上搜一下就能搜到了：  
---------源码类-----------  
1. kernel source  
2. .config文件  

---------工具类-----------  
1. 交叉编译器arm-eabi-  
2. fastboot,adb等android工具  
3. mkbootimg用于解包boot.img使用  

---------脚本类-----------  
1. repack-bootimg.pl //不一定需要  
2. unpack-bootimg.pl  

##### 下面是完整版刷内核及内核模块攻略（基于恶心的Galaxy Nexus）  
##### 1. 配置交叉编译器等各种环境  
  1)下载交叉编译器：  
  $ git clone https://android.googlesource.com/platform/prebuilt  

  2)写入环境变量中：  
  export PATH="/home/xxx/android-toolchain/prebuilt/linux-x86/toolchain/arm-eabi-4.4.3/bin:$PATH"  

##### 2. 编译内核  
  1)修改内核根目录下的Makefile(一劳永逸的方法...)：  
```
        #ARCH           ?= $(SUBARCH)
        #CROSS_COMPILE  ?= $(CONFIG_CROSS_COMPILE:"%"=%)
        ARCH            ?= arm
        CROSS_COMPILE   ?= arm-eabi-
```
  2)从手机目录： /proc/下找到config.gz压缩文件，拿出来解压成.config，复制到内核源码根目录下  
        很多情况下手机中没有config.gz，我们刷了N多的rom加内核才找到一个能正常跑并且里面有这个文件的内核...  
        但是找到了可以一直使用，即使换了别的rom或者内核也没关系  
        实在没有的话，看第三步。  
  3)如果2)成功了，执行make menuconfig，看看该配置是否支持netfilter，如果不支持安下面的选上  
```
        To use netfilter
        Networking support  -> Networking options ->  Network packet filtering framework (Netfilter)
        Choose related choices
```
  如果找到config.gz，执行make tuna_defconfig（这个是默认的德州仪器CPU的配置文件，理论上可用，但是我没有成功），然后同样看netfilter配置  
  4)执行make -j 2  
  5)完成编译，得到arch/arm/boot/zImage文件  

##### 3. 将zImage扔到手机中
  1)从手机中拿出boot.img，或者从刷入手机的rom或kernel中拿也可，总之拿到一个手机在用的boot.img  
  2)执行前确保各个脚本permission正确，将boot.img,zImage,脚本unpack-bootimg.pl,可执行文件mkbootimg,放于同一个目录下。  
  3)执行脚本com.sh：（com.sh内容如下），用于将zImage打包进boot.img形成我们自己的kernel：newtestboot.img  
```
        ./unpack-bootimg.pl boot.img
        cd boot.img-ramdisk/
        find . | cpio -o -H newc | gzip > ../ramdisk-repack.cpio.gz
        cd ..       
        ./mkbootimg --kernel zImage --ramdisk boot.img-ramdisk/ramdisk-repack.cpio.gz --base 0x30000000 -o newtestboot.img
```

##### 4. 手机进入bootloader模式,利用fastboot刷入newtestboot.img
  1)$ adb reboot bootloader  
  2)$ fastboot boot newtestboot.img  
        若出现permission denied，waiting for devices之类的问题，执行  
        $ sudo vim /etc/udev/rules.d/51-android.rules  
        在规则中添加  
        若出现permission denied之类的错误，执行  
        $ sudo vim /etc/udev/rules.d/51-android.rules  
        在规则中添加：
```
            SUBSYSTEM=="usb", ATTRS{idVendor}=="0bb4", MODE="0666"
            SUBSYSTEM=="usb", SYSFS{idVendor}=="18d1", MODE="0666"
```
        这个的作用是将usb权限以及配置与adb或者fastboot配对，特别是fastboot由于是通过usb线刷的，必须保证usb口是匹配的。

##### 5. 此时不出意外就是完成了内核刷入，下面将内核模块加载进去就简单了

##### 6. 编译内核模块 
  1)利用我们的内核源码作为头文件，交叉编译器作为编译器来编译内核模块，Makefile文件写法如下：
```
        KERNELDIR := /home/carelife/android_icecream/android_kernel/CyanogenMod
        PWD :=$(shell pwd)
        ARCH=arm
        CROSS_COMPILE=arm-eabi-
        CC=$(CROSS_COMPILE)gcc
        LD=$(CROSS_COMPILE)ld
        obj-m := netCatch.o
        modules:
                $(MAKE) -C $(KERNELDIR) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) M=$(PWD) modules  
        clean:
                $(MAKE) -C $(KERNELDIR) M=$(PWD) clean
```

##### 7. 加载KM
```
  1)$ adb push /your_kernel_module_position /sdcard/
  2)$ adb shell
        #cd sdcard
        #insmod your_kernel_module_name
```

##### 8. 查看debug信息
  1)$ adb shell dmesg  
        这个方法的实质是从手机IO缓存中读取print信息，输出到电脑屏幕上，所以是一个固定时间更新的静态查看信息的方法，十分不利于调试  
  2)等待寻找其他debug方法...

