---
layout: post
title: "MySQL 最常用命令"
date: 2011-05-23 21:17:00 +0800
comments: false
categories:
- 2011
- 2011~05
- tools
- tools~mysql
tags:
---
登录到mysql中，然后在mysql的提示符下运行命令，每个命令以分号(;)结束。
##### 一：mysql服务的启动和停止
```
	sudo /etc/init.d/mysql stop	 // net stop mysql
	sudo /etc/init.d/mysql start	 // net start mysql
```
##### 二：登陆mysql
  语法如下： mysql -u用户名 -p用户密码	
命令 mysql -uroot -p ， 回车后提示你输入密码，输入12345，然后回车即可进入到mysql中了，mysql的提示符是：  
mysql>  
注意，如果是连接到另外的机器上，则需要加入一个参数-h机器IP

##### 三：增加新用户
  格式：grant 权限 on 数据库.* to 用户名@登录主机 identified by "密码"
如，增加一个用户user1密码为password1，让其可以在本机上登录， 并对所有数据库有所有的权限。首先用以root用户连入mysql，然后键入以下命令：
```
	grant all privileges on *.* to user1@localhost Identified by "password1";
```
  如，增加一个用户user1密码为password1，让其可以在本机上登录， 并对abc数据库有查询、插入、修改、删除的权限。首先用以root用户连入mysql，然后键入以下命令：
```
	grant select,insert,update,delete on abc.* to user1@localhost Identified by "password1";
```
如果希望该用户能够在任何机器上登陆mysql，则将localhost改为"%"。
如果你不想user1有密码，可以再打一个命令将密码去掉。
```
	grant select,insert,update,delete on abc.* to user1@localhost dentified by "";
```

##### 四：显示数据库列表。
```
	show databases;  
```
缺省数据库：mysql。 mysql库存放着mysql的系统和用户权限信息，我们改密码和新增用户，实际上就是对这个库进行操作。

##### 五：建库与删库：
```
	create database 库名;
	drop database 库名;
```
##### 六：显示库中的数据表：
```
	use abc;
	show tables;
```
##### 七：显示数据表的结构：
```
	describe 表名;
```
##### 八：建表与删表：
```
	use abc;
	create table 表名(字段列表);
	drop table 表名;
	如：create table imformation(name varchar(11), age int(5));
```
##### 九：清空表中记录：
```
	delete from 表名;
```
##### 十：显示表中的记录：
```
	select * from 表名;
```
##### 十一：增加一个字段：
```
	alter table table_name add column <字段名><字段选项>
	alter table imformation add phone varchar(5);
	觉得5太小，修改为15
	修改字段：	
	alter table table_name change <旧字段名> <新字段名><选项>
	alter table imformation change phone phone varchar(15);
	增加几个字段:
	alter table imformation add authors varchar(100),add category varchar(20);
```
##### 十二：删除一个字段：
```
	alter table table_name drop column <字段名>
	alter table imformation drop authors;
```
##### 十三：插入记录：
```
	insert into 表名称（字段名1，字段名2…） values （字段1的值，字段2 的值，…）;
	insert into imformation(name,phone) values('a1','123456789');
```
##### 十四：修改记录：
```
	update imformation set column_name1="" where column_name2="";
	update imformation set phone="987654321" where name="a1";
```
##### 十五：删除记录：
```
	delete from 表名称 where 条件表达式;
	delete from imformation where name="a2";
```
##### 十六：查看建表信息：
```
	show create table imformation\G;  大写G
```
##### 十七：某个字段不同值的数目：
```
	SELECT tid,count(tid) as tnum FROM TABLE group by tid order by tnum DESC;   DESC降序，ASC升序。
```
##### 十八：不同id的status=0的数目：
```
	SELECT id,count(*) AS tnum FROM TABLE WHERE id IN (id1, id2, id3, ...) AND status=0 GROUP BY id;
```
##### 十九：替换函数
```
	UPDATE `table_name` SET `field_name` = replace (`field_name`,'from_str','to_str') WHERE `field_name` LIKE '%from_str%'
```

##### 二十：如何清除输入过的mysql命令
清空用户目录下的.mysql_history

