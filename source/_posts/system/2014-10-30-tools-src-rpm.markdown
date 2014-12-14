---
layout: post
title: "修改、重新生成和安装src.rpm源码包"
date: 2014-10-30 09:50:00 +0800
comments: false
categories:
- 2014
- 2014~10
- system
- system~centos
tags:
---
RHEL/CentOS/Fedora/Suse等Linux发行版都使用rpm包作为软件包格式。另外还有一个相关的格式srpm包（后缀是.src.rpm），它包含了源代码，可以用它重新生成rpm包。  
当前最新发行的RHEL/CentOS是6.X版本。目前最新版是RHEL6.5/CentOS6.5。（CentOS是RHEL的免费版本，与RHEL对应版本完全等价，除了去掉了Redhat的LOGO。）  
在如下地址，可以找到RHEL6的所有rpm包的源码包：*.src.rpm。  
	http://ftp.redhat.com/redhat/linux/enterprise/6Server/en/os/SRPMS/  
CentOS就是使用这些*src.rpm源码包构建出所有RPM包，生成CentOS操作系统的。  
*src.rpm源码包解压出来后，可以看到有该软件的源代码压缩包和一些patch文件。  
如果rpm包有问题，我们可以去`http://ftp.redhat.com/redhat/linux/enterprise/6Server/en/os/SRPMS/`下载对应的src.rpm包，然后把它解开后修改源代码，重新编译和生成rpm包，进行分发和安装。

#### 直接安装*src.rpm源码包
有时，我们没有找到可用的rpm包，但找到了其对应的*src.rpm源码包，此时我们可以安装这个*src.rpm源码包。步骤与直接安装rpm包很不相同。
```
rpm -i /tmp/mypackage-1.0.0-1.src.rpm
```
此时还没有安装完成。只是在~/rpmbuild/ 目录下准备了该src.rpm源码包的资源，可用于进一步生成rpm包。
```
[user@host ~]$ cd ~/rpmbuild/SPECS
[user@host SPECS]$ rpmbuild -ba mypackage.spec
```
#### 你也可以直接使用如下命令：
```
rpmbuild --rebuild /tmp/mypackage-1.0.0-1.src.rpm
```
这个命令一步即可在～/rpmbuild/RPMS/目录下重新生成rpm包。  
基于*src.rpm源码包修改代码后生成rpm包并安装  
rpmbuild命令基于.spec文件和源码tar.gz及patch文件生成src.rpm和rpm包。  
因此，我们只需要修改.spec文件，或者对应的源码和patch文件，然后再执行  
```
rpmbuild -ba mypackage.spec
```
命令，就可以生成更新后的src.rpm包和rpm包。rpm包在~/rpmbuild/RPMS目录下，  
src.rpm包在~/rpmbuild/SRPMS目录下。注意,要修改~/rpmbuild/SOURCES/目录下的文件:  
1. 你可以重新打包~/rpmbuild/SOURCES/目录下的tar.gz源文件。  
2. 你可以修改.spec文件，增加或者减少对patch的应用。
  
