---
layout: post
title: "img.ext4格式"
date: 2015-01-03 14:36:00 +0800
comments: false
categories:
- 2015
- 2015~01
- android
- android~base
tags:
---
工具 https://github.com/abcdxyzk/ext4_utils

#### 一、转换源文件为ext4格式
然后，我们可以使用./simg2img src des命令来转换system.img.ext4格式文件了
```
	./simg2img system.img.ext4 system.img
```

#### 二、挂载镜像到指定目录
然后挂载此img到一个目录上
```
	mount -o loop system.img sysmain
```
成功挂载。然后你就可以进入目录了查看里面的文件了！！！！！


#### 三、修改镜像内的文件
这时候可以进入挂载的目录mysys里面查看各个文件，甚至是修改了。不过这时候要注意一点，就是保持文件的原始权限。

#### 四、打包文件
当你所有文件搞定后，下来需要一个命令来打包了。
```
	./mkuserimg.sh -s sysmain systest.img.ext4 ext4 tmp 512M
```
这里需要注意，temp是我在当前目录新建立的一个目录，后面的512M是这个镜像打包后占用空间大小。如果你不知道你的镜像包应该多大，你查看你景象挂载到目录后，这个景象分区的大小。

恩，当你完成以上步骤，新的systest.img.ext4成功生成了，好了，你可以在fastboot模式下刷入了！！！
