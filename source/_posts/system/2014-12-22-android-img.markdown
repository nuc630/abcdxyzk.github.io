---
layout: post
title: "img格式"
date: 2014-12-22 22:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---
备份系统中img：dd if=/dev/block/mmcblk0p2 of=/sdcard/boot.img，回车，可得boot.img。

#### 工具
```
git clone https://github.com/AndroidRoot/BootTools.git BootTools
cd BootTools
make
```

#### 过程
```
	# 解压得到 kernel 和 ramdisk，解出来的boot.img-kernel.gz就是zImage
	./unpack-bootimg.sh boot.img

	# 可以编辑boot.img-ramdisk，编辑好后打包：
	cd boot.img-ramdisk
	find . | cpio -o -H newc | gzip > ../ramdisk-repack.cpio.gz 

	# 查看应加载地址
	./hdrboot boot.img

	# 重新打包img
	./mkbootimg --kernel zImage --ramdisk boot.img-ramdisk.cpio.gz --base 13600000 --ramdisk_offset FF8000 --pagesize 4096 -o new_boot.img

	# 查看新加载地址
	./hdrboot new_boot.img
```

#### 注意
打包后的文件用hdrboot看到的一些addr值要和原来一样，一些size的则无所谓

