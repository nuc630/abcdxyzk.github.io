---
layout: post
title: "同时运行多个squid"
date: 2015-07-23 15:32:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~base
tags:
---

http://wenku.baidu.com/link?url=UXFXZVxSsQMyXVzoTA5y3Oal6s5zknpozLhfodYZ7d43R_XpziB08h28ynXZy3Sq8r-XH1tdXGvxD_X2Pa_aI4f6pFTBgGXMm0QRaRbEYmq

#### 多代理（SQUID）同时运行的配置方法 
作成日期：2012/8/24 

##### 多代理用途： 
1、HTTP反向加速；  
2、权限控制部分客户端，而权限控制选项是全局设置时；  

总之，一般的代理服务器运行一个即可，当有特殊要求的时候，才有此需要，HTTP反向代理本文没有涉及，仅是为了权限控制，一台机器同一网卡运行了2个Squid，对于HTTP反向代理，有兴趣者可自行研究配置。  

##### 环境： 
1、 Cent OS 5  
2、 Squid （Version 2.6.STABLE21）   
3、 DELL R710   

##### 配置： 
在配置多Squid同时运行时，我的服务器已经安装配置好的Squid，并正常运行，如果你的服务器还不具备此条件，请先配置好Squid，并确保可以正确运行。 

1、 复制一份Squid .conf配置文件   
2、 编辑新文件，配置如下的选项与第一个Squid区分开   

<table>
	<tr>
		<th>项目</th>
		<th>参数</th>
		<th>备注</th>
	</tr>
	<tr>
		<td>端口</td>
		<td>8080</td>
		<td>端口可自定，但要注意两个问题，与原有的Squid 默认的3128区分开，并且与系统已经存在的服务占用端口区分开，避免冲突发生。</td>
	</tr>
	<tr>
		<td>缓存目录</td>
		<td>指定一个新目录与第一个Squid区分开</td>
		<td>TAG: cache_dir， 注意，新的目录必须将权限设定为777。</td>
	</tr>
	<tr>
		<td>系统日志</td>
		<td>指定一个新目录与第一个Squid区分开</td>
		<td>TAG: access_log TAG: cache_log TAG: cache_store_log 以上日志存放地点可自定与第一个Squid区分开即可，注意，新的目录必须将权限设定为777。</td>
	</tr>
	<tr>
		<td>PID文件</td>
		<td>指定一个新目录与第一个Squid区分开</td>
		<td>TAG: pid_filename 第1个Suqid的PID文件默认存放地点是/VAR/RUN 重新指定新的目录，避免与第1个Squid文件冲突。</td>
	</tr>
</table>

3、初始化缓存目录   
命令如下：`squid -z -f 新的配置文件`  
注意，"-f"参数后面一定要写上新配置文件，一般设定2个Squid同时运行时，都是这一步没有处理或者处理错误，比如没有加"-f"参数的话，就会初始化原有的Squid缓存目录 而不是新squid缓存目录。 

4、运行第2个代理服务器   
命令如下：`squid -D -f 新的配置文件`  

 var script = document.createElement('script'); script.src = 'http://static.pay.baidu.com/resource/baichuan/ns.js'; document.body.appendChild(script);    


#### 维护： 
至此，服务器上已经运行两个代理服务器，使用不同的端口，就会通过不同代理服务器进行网络连接，设定配置文件，可为客户端设定不同的网络权限。   

1、关于配置文件的更新后Reload 
如更新第1个代理，使用默认系统命令：squid -k reconfigure      如更新第2个代理，squid -k reconfigure -f 新的配置文件   

2、第2个代理的自动启动   
当系统重新时，想第2个代理随机启动，请参照以下脚本（第1个代理启动，可以在系统中设定）： 

```
	#! /bin/sh 
	echo "Start special squid”             #输出一些提示信息 
	squid -D -f /etc/squid/squidnew.conf   #我的新配置文件在/etc/squid下面 
	echo "Please wait ...."                #输出一些提示信息 
	sleep 5                             #等待5秒，给Squid启动时间，实际可能不需要怎么久 
	cd /var/cache/squidnew/             #进入缓存目录，我的PID文件放在这里 
	if [ -s squid.pid ];                #判断PID文件是否存在，存在squid启动成功，否则失败      
	then                                              
		echo "Squid start success"      
	else 
		echo "Squid start failed" 
	fi
	exit 0 
```

将该脚本放置到启动目录，自行启动即可，另外我不是自行启动，因有时候不运行，如自行启动，可将判断的部分删除，因为系统启动，可能看不到脚本提示信息。 

关于关闭Squid，请使用多次的 squid -k shutdown 命令关闭服务， 同时使用ps -ef |grep squid 判断代理服务是否全部关闭完成。 

调试过程如有问题，使用tail -f /var/log/messages 排错也是个不错的办法。  

备注： 

另外，系统究竟可以运行多少个Squid？没有测试，猜测如CPU足够快、内存足够大，应该可以运行很多副本。


