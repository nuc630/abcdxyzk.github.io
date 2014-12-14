---
layout: post
title: "FTP命令"
date: 2013-02-16 15:02:00 +0800
comments: false
categories:
- 2013
- 2013~02
- tools
- tools~base
tags:
- ftp
---
* ftp 很快就会自动断开，lftp命令一样，更好用

#### Linux 终端连接FTP
```
$ ftp 10.85.7.97

Name (10.85.7.97:oracle): super

Password:   -- Linux 的密码是不回显的

ftp>
```
如果FTP 允许匿名用户，那么用户名要输入anonymous,密码任意。 不能直接敲回车。
 
#### 查看FTP 命令
```
ftp> ?
Commands may be abbreviated.  Commands are:
!               cr              mdir            proxy           send
$               delete          mget            sendport        site
account         debug           mkdir           put             size
append          dir             mls             pwd             status
ascii           disconnect      mode            quit            struct
bell            form            modtime         quote           system
binary          get             mput            recv            sunique
bye             glob            newer           reget           tenex
case            hash            nmap            rstatus         trace
ccc             help            nlist           rhelp           type
cd              idle            ntrans          rename          user
cdup            image           open            reset           umask
chmod           lcd             passive         restart         verbose
clear           ls              private         rmdir           ?
close           macdef          prompt          runique
cprotect        mdelete         protect         safe
```
可以通过help command 查看每个命令的说明
```
ftp> help put
put             send one file
ftp> help mput
mput            send multiple files
```

#### 上传文件
Put命令：格式：put local-file [remote-file] 将一个文件上传到ftp  
Mput命令：格式：mput local-files 将本地主机中一批文件传送至远端主机.  
注意：mput命令只能将当前本地目录下的文件上传到FTP上的当前目录。比如，在/root/dave下运行的ftp命令，则只有在/root/dave下的文件linux才会上传到服务器上的当前目录下。
 
##### Put 代码示例：
```
ftp> pwd    -- 显示FTP上当前路径
257 "/" is current directory.
ftp> ls   -- 显示当前目录下的文件

ftp> mkdir Dave    -- 创建文件夹Dave

ftp> cd Dave      -- 进入文件夹Dave

ftp> pwd        -- 显示当前目录

ftp> lcd     -- 显示当前本地的路径，我们可以将这个路径下的这个文件上传到FTP服务器的相关位置

ftp> !      -- 退出当前的窗口，返回Linux 终端，当我们退出终端的时候，又会返回到FTP上。
$ ls  -- 显示当前目录下的文件

$ vi Dave  -- 创建文件Dave
$ vi DBA   -- 创建文件DBA
$ ls       -- 显示文件夹里的内容，等会我们将这些文件copy到FTP上

$ exit  -- 退出终端，返回FTP命令行
exit
ftp> lcd

ftp> put DBA DBA    -- 将刚才创建的文件DBA 上传到ftp的当前目录上并命名为DBA。

ftp> put DBA /Dave/SFDBA -- 将刚才创建的文件DBA 上传到ftp的当前目录上并重命名为SFDBA。

ftp> put /home/oracle/DBA /test/SFDBA  

ftp> cd test

ftp> ls

```
##### Mput 示例代码：
```
ftp>cd Dave

ftp>mput *
mput alert_log.txt?    -- 这里每个文件都要确认，按回车键就可以了

ftp> ls       -- 显示目录下的文件

ftp> delete SFDBA   --删除SFDBA 文件

ftp> mdelete a*   -- 批量删除文件
mdelete alert_log.txt?  -- 每个文件都要确认

```
 
#### 下载文件
同样也有2个命令：get 和mget。Mget 用户批量下载。  
格式：get [remote-file] [local-file]  
mget [remote-files]  
同样，mget 是将文件下载到本地的当前目录下。
 
##### Get 示例：
```
ftp> get /test/SFDBA /home/SFDBA

local: /home/SFDBA: Permission denied  --Linux对权限控制的很严格，下载的时候是否有对应文件夹的写权限
ftp>  get /test/SFDBA /home/oracle/SFDBA

ftp> !
$ cd /home/oracle/
$ls
Dave  DBA  dead.letter  scripts  SFDBA  sqlnet.log
```
##### Mget 示例：
```
ftp> ls

ftp> mget *
mget DBA?  -- 每个文件都要确认， 按回车即可

ftp> !
$ ls

```
说明的地方：FTP 当前目录下的文件下载到本地的当前目录。

#### 断开FTP 连接
Bye命令或者quit命令：中断与服务器的连接。
```
ftp> bye
221 Goodbye!
```

