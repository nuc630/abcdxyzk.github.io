---
layout: post
title: "error, forbidden warning"
date: 2015-08-10 14:18:00 +0800
comments: false
categories:
- 2015
- 2015~08
- android
- android~base
tags:
---
编译时出现类似的情况：把Warning当做Error，当没有加-Werror选项
```
	  CC [M]  /home/kk/udp_probe/udp_probe.o
	/home/kk/udp_probe/udp_probe.c: In function 'kp_init':
	/home/kk/udp_probe/udp_probe.c:36:18: warning: assignment makes pointer from integer without a cast [enabled by default]
	error, forbidden warning: udp_probe.c:36
	make[2]: *** [/home/kk/udp_probe/udp_probe.o] 错误 1
	make[1]: *** [_module_/home/kk/udp_probe] 错误 2
	make[1]:正在离开目录 `/media/000617990000DB90/403a/source/kernel'
	make: *** [all] 错误 2
```


修改 scripts/gcc-wrapper.py 去掉 interpret_warning 函数中的如下部分
```
		# If there is a warning, remove any object if it exists.
		if ofile:
			try:
				os.remove(ofile)
			except OSError:
				pass
		sys.exit(1)
```

---------------

若直接加 -w gcc选项，则会直接不显示Warning

