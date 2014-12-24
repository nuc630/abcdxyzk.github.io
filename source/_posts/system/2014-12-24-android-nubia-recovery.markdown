---
layout: post
title: "【官方固件】努比亚Z5Smini官方4.4.2全新UI公测版"
date: 2014-12-24 23:34:00 +0800
comments: false
categories:
- 2014
- 2014~12
- system
- system~android
tags:
---
http://www.onekeyrom.com/rom/zte_130038_10965.html

pan.baidu.com/s/1c0u18Ik

<span style="color:red">nx403a进入bootloader模式直接些boot分区，但是驱动没弄好起不来。这时再进bootloader却进不了（严重怀疑他们的bootloader建在boot上），只能进recovery模式。但是recovery是官方的，只能按官方方法升级整个系统救砖</span>

本次放出的压缩包内含两套固件：从4.2升级到4.4.2和从4.4.2再降级回4.2两套共计4个zip文件包  
所以请大家下载后先不要急于不要一键刷机，仔细阅读下面的使用说明和注意事项
 
####【升级注意事项】
1. 升级前，请取消手机的人脸解锁、图案锁、密码锁等各种屏幕锁。  
2. 升级前，请务必备份好手机内的各项重要数据（联系人、短信、通话记录、程序等），避免异常丢失。  
3. 升级前，请保证手机电池电量至少达到40%。  
4. 在升级过程中，请将手机平放，务必不要触碰手机屏幕（否则可能导致触屏失准），直至确认升级成功。  
5. 为了便于升级发生异常后的手机挽救，nubia UI ROM安装包同时提供升级文件与回退文件，请务必同时保留在手机里。  

####【Z5S mini 机型4.2到4.4版本升级操作说明】
步骤1： 下载Z5S mini机型的nubia UI ROM安装包（内含4个zip文件）  
步骤2： 将手机连接电脑，将安装包的4个zip文件并列拷贝至手机sdcard根目录下  
步骤3： 按开关机键，选择“重启”手机，在重启过程中一直长按音量上键进入recovery模式  
步骤4： 在recovery模式界面，请按音量键选择apply update from sdcard菜单项，并按开关机键确定，接着按音量键选择NX403A_4.2_to_4.4_recovery_xxx.zip文件，并按开关机键确定，开始升级  
步骤5： 步骤4升级完成后如下图所示，此时光标条位于reboot system now菜单项，直接按开关机键重启手机，请观察手机能否顺利进入桌面  
步骤6： 手机顺利进入桌面后，请重复步骤3，即再次重启手机，并在重启过程中一直长按音量上键，再次进入recovery模式  
步骤7： 在recovery模式界面，请按音量键选择wipe date/factory reset 菜单项，按开关机键进入，进行数据擦除  
步骤8： 数据擦除结束后，请按音量键选择apply update fromsdcard菜单项，按开关机键进入，再按音量键选择NX403A_4.4_update_xxx.zip文件，按开关机键  确认，执行升级，此过程要1到2分钟  
步骤9： 步骤8升级完成后如下图所示，此时光标条位于reboot system now菜单项，直接按开关机键重启手机

