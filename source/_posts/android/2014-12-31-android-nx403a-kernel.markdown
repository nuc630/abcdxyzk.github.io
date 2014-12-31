---
layout: post
title: "编译努比亚内核"
date: 2014-12-31 11:00:00 +0800
comments: false
categories:
- 2014
- 2014~12
- android
- android~nx403a
tags:
---
源码下载 http://support.zte.com.cn/support/news/NewsMain.aspx?type=service

nx403a在 http://support.zte.com.cn/support/news/NewsDetail.aspx?newsId=1004862

先解压zip在合并再解压7z，tar

修改arch/arm/configs/apq8064-nubiamini2_defconfig，加入
CONFIG_LOCALVERSION="-g3720aca-00082-g0ea2092"
CONFIG_PRIMA_WLAN=m # 这样子wlan还是起不来

make apq8064-nubiamini2_defconfig
make

make会有些头文件的include错误，看着改改

