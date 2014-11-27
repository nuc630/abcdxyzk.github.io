---
layout: post
title: "导入数据库、导出表"
date: 2012-04-17 18:40:00 +0800
comments: false
categories:
- 2012
- 2012~05
- system
- system~mysql
tags:
---
#### 导入数据库
##### 常用source 号令
步入mysql数据库节制台，  
如mysql -u root -p  
mysql>use 数据库  
然后施用source号令，后面参数为脚本文件（如这里用到的.sql）
```
mysql>source /home/abcdxyzk/chai.sql
```
#### MySQL 导出表
```
mysqldump -uroot -p123456 test > /home/my.sql
```
说下上面参数  
数据库用户名：root  
密码 ：123456  
数据库名：test  
/home/my.sql 为导出文件地址，

这里 是linux系统 所以为/home/my.sql如果是windows替换 它为：e:/my.sql 注意空格奥。。


##### 导出单个数据表结构和数据
```
导出整个数据库结构（不包含数据）
mysqldump -h localhost -uroot -p123456 database table > dump.sql

导出单个数据表结构（不包含数据）
mysqldump -h localhost -uroot -p123456 -d database > dump.sql

mysqldump -h localhost -uroot -p123456 -d database table > dump.sql
```
