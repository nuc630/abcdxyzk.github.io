---
layout: post
title: "SELinux引起的SSH公钥认证失败"
date: 2014-10-15 10:39:00 +0800
comments: false
categories:
- 2014
- 2014~10
- tools
- tools~ssh
tags:
---
* restorecon -r -vv /root/.ssh  

  新装一台机器按照正常配置以后居然使用publickey方式认证不成功，但是使用密码认证是可以的。 

  具体现象表现为使用SecureCRT登陆时，出现如下出错提示：
Public-key authentication with the server for user sw failed. Please verify username and public/private key pair.
查看服务器日志，找不到有用的相关记录。 
之后直接在另一台机器上使用ssh连接，打开verbose模式（ssh -vvv），如下：
```
...
debug1: Next authentication method: password
sw@xxx.xxx.xxx.xxx's password:
```
可以看到，ssh先尝试了使用publickey进行认证，但是失败了，日志也没有显示相关原因，然后降级到使用密码认证。 

求助万能的Google，发现serverfault上有一个案例的现象和出错信息与我遇到几乎一样，提问者怀疑是SELinux导致的。
案例 见 http://www.linuxidc.com/Linux/2013-07/87267p2.htm  
下面的回复证实了确实是SELinux的问题，并且给出了解决方案：  
Yes, SELinux is likely the cause. The .ssh dir is probably mislabeled. Look at /var/log/audit/audit.log. It should be labeled ssh_home_t. Check with ls -laZ. Run restorecon -r -vv /root/.ssh if need be.

Yep, SELinux was the cause: type=AVC msg=audit(1318597097.413:5447): avc:denied { read } for pid=19849 comm="sshd" name="authorized_keys" dev=dm-0 ino=262398 scontext=unconfined_u:system_r:sshd_t:s0-s0:c0.c1023 tcontext=unconfined_u:object_r:admin_home_t:s0 tclass=file

It works after running "restorecon -r -vv /root/.ssh". Thanks a lot.

我如获救命稻草，马上用ls -laZ检查了一下我的.ssh目录，果然不是ssh_home_t，心中窃喜，立刻使用restorecon对.ssh目录的context进行了恢复。 

重新连接SSH，认证成功，问题解决

把SELinux暂时关了试试，使用setenforce 0把SELinux关闭，重新尝试连接，publickey认证正常了。   
确认了是SELinux引发的问题  
然后setenforce 1打开SELinux。

