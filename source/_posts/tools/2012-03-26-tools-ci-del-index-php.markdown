---
layout: post
title: "CodeIgniter去掉url中的index.php"
date: 2012-03-26 18:04:00 +0800
comments: false
categories:
- 2012
- 2012~03
- tools
- tools~ci
tags:
- oj
---
#### RewriteEngine命令需要rewrite mod的支持
`$>cd /etc/apache2/mods-enabled` 切换到apache下的mods-enabled目录   
`$>sudo ln -s ../mods-available/rewrite.load` rewrite.load 启用rewrite mod  
`$>sudo /etc/init.d/apache2 restart` 重启apache服务器。 或者在apache的配置文件httpd.conf中将#LoadModule rewrite_module modules/mod_rewrite.so前的#去掉，再重启服务器。  
或者  
`sudo a2enmod rewrite`  
 
#### CodeIgniter去掉url中的index.php
CodeIgniter去掉url中的index.php        CI默认中url中带index.php,比如 `http://localhost/index.php/blog/comment/1.html`
去掉这个index.php步骤：  
##### 1.打开apache的配置文件，conf/httpd.conf ：
`LoadModule rewrite_module modules/mod_rewrite.so`，把该行前的#去掉。  
搜索 AllowOverride None（配置文件中有多处），看注释信息，将相关.htaccess的该行信息改为AllowOverride All。
 
##### 2.在CI的根目录下
即在index.php，system的同级目录下，建立.htaccess，直接建立该文件名的不会成功，可以先建立记事本文件，另存为该名的文件即可。内容如下（CI手册上也有介绍）：
```
RewriteEngine on
RewriteCond $1 !^(index.php|images|robots.txt)
RewriteRule ^(.*)$ /index.php/$1 [L]
```
就可以去掉 index.php 了。  
要注意 /index.php/$1 要根据你目录(Web 目录，比如 `http://www.domain.com/index.php`)的实际情况来定，比如网站根目录是 /ci/index.php 则要写成 /ci/index.php/$1

`RewriteCond $1 !^(index.php|images|robots.txt)`
上面的代码意思是排除某些目录或文件，使得这些目录不会 rewrite 到 index.php 上，这一般用在图片、js、css 等外部资源上。也就是说非 PHP 代码都要排除出去。（这里我排除了 images 目录和 robots.txt 文件，当然 index.php 也应该被排除）

##### 3.
将CI中配置文件（system/application/config/config.php）中$config['index_page'] = &index.php&;将$config['index_page'] = &&; 。  
ok，完成。还要记得重启apache。

