---
layout: post
title: "debuginfo 编译速度"
date: 2015-11-26 11:30:00 +0800
comments: false
categories:
- 2015
- 2015~11
- debug
- debug~base
tags:
---

Have a look into /usr/lib/rpm/macros:
```
	#       Compression type and level for source/binary package payloads.
	#               "w9.gzdio"      gzip level 9 (default).
	#               "w9.bzdio"      bzip2 level 9.
	#               "w7.xzdio"      xz level 7, xz's default.
	#               "w7.lzdio"      lzma-alone level 7, lzma's default
	#
	#%_source_payload       w9.gzdio
	#%_binary_payload       w9.gzdio
```

binkernel.spec中加入
```
	%_source_payload       w5.gzdio
	%_binary_payload       w5.gzdio
```
略微降低压缩率，大大提高打包速度。kernel增加600K，debuginfo增加3M，时间从14分钟降至2分钟内


