---
layout: post
title: "Ubuntu下安装MySQL获得 mysql.h"
date: 2012-04-08 13:33:00 +0800
comments: false
categories:
- 2012
- 2012~04
- system
- system~mysql
tags:
---
#### 先安装MySQL
```
sudo apt-get install mysql-server mysql-client
```
#### 再装开发包
```
sudo apt-get install libmysqlclient15-dev
```
#### 安装完以后，C代码里添加头文件
```
#include <mysql.h>   还是 #include<mysql/mysql.h>
```
#### 编译方法：
```
gcc $(mysql_config --cflags) xxx.c -o xxx $(mysql_config --libs)
```

