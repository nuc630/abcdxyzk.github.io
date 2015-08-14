---
layout: post
title: "搭建FTP服务器"
date: 2013-02-18 18:59:00 +0800
comments: false
categories:
- 2013
- 2013~02
- tools
- tools~base
tags:
---
#### 用VSFTP搭建FTP服务器
FTP服务器是平时应用最为广泛的服务之一。VSFTP是Very Secure FTP的缩写，意指非常安全的FTP服务。VSFTP功能强大，通过结合本地系统的用户认证模块及其多功能的配置项目，可以快速有效的搭建强大的多用户FTP服务。

#### 一、主要配置选项
VSFTP的主配置文件是/etc/vsftpd.conf 。由于可配置的选项实在太多，无法一一详谈，只能截取比较常用的功能配置选项来加以说明。完整说明可参考man vsftpd.conf。

这里需要注意的是，每个配置选项都是由“配置项目名称＝配置值“所定义。在每个配置变量后，要紧跟等号，再紧跟设置的变量值。中间不允许出现空格之类的分隔符，否则导致配置错误，无法生效！ 

另外，如果需要开通上传功能，则应注意用来登录FTP的本地系统用户对要操作的目录需要具备写权限，否则无法上传文件！ 

版本vsftpd: version 2.0.6   
启动VSFTPD：sudo /etc/init.d/vsftpd start   
停止VSFTPD：sudo /etc/init.d/vsftpd stop   
重启VSFTPD：sudo /etc/init.d/vsftpd restart   

以下为常用的配置选项： 
```
	1、listen=YES 
	若设置为YES，开启监听网络。 
	2、anonymous_enable 
	若设置为YES，则允许匿名用户访问；若设置为NO则拒绝匿名用户访问。 
	如果开启的话，则可以通过用户名ftp或者anonymous来访问，密码随便。 
	3、local_enable 
	若设置为YES，则允许通过本地用户帐号访问；若设置为NO，则拒绝本地用户帐号访问。如果你拒绝了陌生人访问，那么这个必须设置为YES吧，否则谁能访问你的FTP呢？ 
	4、write_enable 
	若设置为YES，则开启FTP全局的写权限；若设置为NO，则不开。 
	若为NO则所有FTP用户都无法写入，包括无法新建、修改、删除文件、目录等操作，也就是说用户都没办法上传文件！！ 
	5、anon_upload_enable 
	若设置为YES，开启匿名用户的上传权限。前提是write_enable有开启，并且用户具有对当前目录的可写权限。 若设置为NO，则关闭匿名用户的上传权限。 
	6、anon_mkdir_write_enable 
	若设置为YES，开启匿名用户新建目录的权限。前提是write_enable有开启，并且用户具有对当前目录的可写权限。 若设置为NO，则关闭匿名用户新建目录的权限。 
	7、dirmessage_enable 
	若设置为YES，则可开启目录信息推送，也就是用户登录FTP后可以列出当前目录底下的文件、目录。 这个应该要开启吧！ 
	8、xferlog_enable 
	若设置为YES，则开启登录、上传、下载等事件的日志功能。应开启！ 
	9、xferlog_file=/var/log/vsftpd.log 
	指定默认的日志文件，可指定为其他文件。 
	10、xferlog_std_format 
	若设置为YES，则启用标准的ftpd日志格式。可以不启用。 
	11、connect_from_port_20 
	若设置为YES，则服务器的端口设为20。 
	如果不想用端口20，可以另外通过ftp_data_port来指定端口号。 
	12、chown_uploads 
	若设置为YES，则匿名用户上传文件后系统将自动修改文件的所有者。 
	若要开启，则chown_username=whoever也需指定具体的某个用户，用来作为匿名用户上传文件后的所有者。 
	13、idle_session_timeout=600 
	不活动用户的超时时间，超过这个时间则中断连接。 
	14、data_connection_timeout=120 
	数据连接超时时间 。 
	15、ftpd_banner=Welcome to blah FTP service. 
	FTP用户登入时显示的信息 。 
	16、local_root=/home/ftp 
	指定一个目录，用做在每个本地系统用户登录后的默认目录。 
	17、anon_root=/home/ftp 
	指定一个目录，用做匿名用户登录后的默认目录。 
	18、chroot_local_user、 chroot_list_enable、chroot_list_file 
	这个组合用于指示用户可否切换到默认目录以外的目录。 
	其中，chroot_list_file默认是/etc/vsftpd.chroot_list，该文件定义一个用户列表。 
	若chroot_local_user 设置为NO，chroot_list_enable设置为NO，则所有用户都是可以切换到默认目录以外的。 
	若chroot_local_user 设置为YES，chroot_list_enable设置为NO，则锁定FTP登录用户只能在其默认目录活动，不允许切换到默认目录以外。 
	若chroot_local_user 设置为YES，chroot_list_enable设置为YES，则chroot_list_file所指定的文件里面的用户列表都可以访问默认目录以外的目录，而列表以外的用户则被限定在各自的默认目录活动。 
	若chroot_local_user设置为NO，chroot_list_enable设置为YES，则chroot_list_file所指定的文件里面的用户列表都被限定在各自的默认目录活动，而列表以外的用户则可以访问默认目录以外的目录。 
	建议设置：chroot_local_user与chroot_list_enable都设置为YES。这样就只有chroot_list_file所指定的文件里面的用户列表可以访问默认目录以外的目录，而列表以外的用户则被限定在各自的默认目录活动！ 
	好处：所有人都被限制在特定的目录里面。如果某些特定用户需要访问其他目录的权限，只需将其用户名写入chroot_list_file文件就可以赋予其访问其他目录的权限！ 
	19、userlist_file、userlist_enable、userlist_deny 
	这个组合用于指示用户可否访问FTP服务。 
	其中，userlist_file默认是/etc/vsftpd.user_list，该文件定义一个用户列表。 
	若userlist_enable设置为YES，userlist_deny设置为NO，则只有userlist_file所指定的文件里面的用户列表里面的用户可以访问FTP。 
	若userlist_enable设置为YES，userlist_deny设置为YES，则userlist_file所指定的文件里面的用户列表里面的用户都被拒绝访问FTP。 
	若userlist_enable设置为NO，userlist_deny设置为YES，则这个列表没有实际用处，起不到限制的作用！因为所有用户都可访问FTP。 
	建议设置：userlist_enable与userlist_deny都设置为YES。这样则userlist_file所指定的文件里面的用户列表里面的用户都被拒绝访问FTP。 
	好处：只需将某用户帐号加入到userlist_file所指定文件里面的用户列表，就可以起到暂时冻结该用户的功能！ 
	20、user_config_dir 
	指定一个目录用于存放针对每个用户各自的配置文件，比如用户kkk登录后，会以该用户名建立一个对应的配置文件。 
比 如指定user_config_dir=/etc/vsftpd_user_conf,  则kkk登录后会产生一个/etc/vsftpd_user_conf/kkk的文件，这个文件保存的配置都是针对kkk这个用户的。可以修改这个文件而  不用担心影响到其他用户的配置。 
```

#### 二、一种VSFTP的配置方案

##### 首先要安装VSFTP。

源码编译或软件包安装都可以。 
`sudo apt-get install vsptpd`
以下方案实现以下功能：  
1、锁定用户在/home/ftp默认目录活动，  
  并保留/etc/vsftpd.chroot_list文件里面的用户列表可访问其他目录。  
2、具备暂时冻结FTP用户的功能，将需暂停的用户名加入到/etc/vsftpd.usr_list即可。  
 
##### 设置配置文件：  

复制以下文件并保存为/etc/vsftpd.conf  
新建两文件：  
  `touch /etc/vsftpd.chroot_list`  
  `touch /etc/vsftpd.user_list`  
新建目录：`mkdir /home/ftp`  
新建群组：`addgroup ftp`  
修改/home/ftp属性：`chown ftp:ftp /home/ftp`  
新增FTP用户： `adduser --shell /bin/false --home /home/ftp your_usr_name`  
把需要开通FTP的用户名加入到ftp群组：`usermod -aG ftp your_usr_name`  
注意：  
如果你的/etc/shells里面没有包含/bin/false，则你用上述的方法建立的用户将法访问#FTP，解决方法：编辑/etc/shells，加入/bin/false这行。 

#### 三、前面提到的问题

##### 1、如何添加FTP用户？

设置local_enable为YES可以开放系统用户访问FTP。

在系统里面添加用户，将shell设置为/bin/false，并将其家目录若设置为/home/ftp或者其他目录。这样就可以建立只访问FTP而无法登录shell环境的用户。

注意：可以新建一个ftp组，把/home/ftp的所有者设为ftp，群组也设为ftp。然后所有新添加的FTP用户只需加入到FTP群组就可以具有对/home/ftp的访问权限了。这样也方便管理用户量比较大的FTP系统。如：
```
	sudo addgroup ftp #如果有了就不用添加
	sudo chown ftp:ftp /home/ftp #如果改过了就不用再改
	sudo adduser --shell /bin/false --home /home/ftp user1 #添加用户user1
	sudo usermod  -aG ftp  user1  #把用户user1加入到ftp组, 这样便可以通过用户名user1来访问FTP服务了。
```

##### 2、如何临时冻结某FTP用户？
将 userlist_enable与userlist_deny都设置为YES。这样userlist_file所指定的文件里面的用户列表里面的用户都  被拒绝访问FTP。只需将某用户帐号加入到userlist_file所指定文件里面的用户列表，就可以起到暂时冻结该用户的功能！如需重新开通使用权  限，则只需从该文件中去掉相应的用户名。 

##### 3、FTP用户登入后的默认目录？是否可以改变？ 
可以通过local_root、anon_root来指定相应的默认目录。 

##### 4、如何锁定FTP用户可访问的目录范围？ 
将 chroot_local_user与chroot_list_enable都设置为YES。这样就只有chroot_list_file所指定的文件  里面的用户列表可以访问默认目录以外的目录，而列表以外的用户则被限定在各自的默认目录活动！如果某些特定用户需要访问其他目录的权限，只需将其用户名写  入chroot_list_file文件就可以赋予其访问其他目录的权限！ 

##### 5、FTP用户可以有哪些访问权限？可否上传文件？ 
设置write_enable可以开启全局的写权限。这样FTP用户就可以在本地帐号管理系统允许的范围内进行写操作了

##### 6、root用户无法登录ftp？
编辑/etc/ftpusers，将root注视掉就ok了

#### 四、可能遇到的主要问题

##### 一、
登录失败，解决方法：在/etc/shells中加入下面这句：/bin/false    就可以正常登录了

##### 二、
上传文件时总是出现550 Permission denied错误，  
查看vsftpd的配置文件sudo vim /etc/vsftpd.conf,  
发现write_enable=YES这句配置项默认是被注释掉的即#write_enable=YES,   
把前面的注释去掉，重启vsvfpd，一切正常了。

##### 三、
user_config_dir 指定一个目录用于存放针对每个用户各自的配置文件。   
比 如指定user_config_dir=/etc/vsftpd_user_conf, 新建/etc/vsftpd_user_conf/kkk文件，输入下面内容：
```
	write_enable=YES
	anon_world_readable_only=NO
	anon_upload_enable=YES
	anon_mkdir_write_enable=YES
	anon_other_write_enable=YES
	local_root=/srv/ftp/ftp
```
这个文件保存的配置都是针对kkk这个用户的。可以修改这个文件而  不用担心影响到其他用户的配置。

##### 四、
报下面的错误  
`ftp:500 Illegal PORT command. 425`  
`ftp:Use PORT or PASV first`  
或者是下面的错误  
`ftp:500 Illegal PORT command.`  
`ftp: bind: Address already in use`  
主要是由于Iptables防火墙不支持  
ip_nat_ftp  
ip_conntrack_ftp  
在linux的ftp服务器上执行下列命令即可解决  
modprobe ip_nat_ftp  
modprobe ip_conntrack_ftp

##### 五、
553 Could not create file  
用 chown 或 chmod

##### 六、
限定用户访问目录  
local_root=/srv/ftp  
chroot_local_user=YES  
chroot_list_enable=NO

