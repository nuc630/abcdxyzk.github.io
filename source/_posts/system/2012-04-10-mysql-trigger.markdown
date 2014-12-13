---
layout: post
title: "MySQL 触发器"
date: 2012-04-10 17:07:00 +0800
comments: false
categories:
- 2012
- 2012~04
- system
- system~mysql
tags:
---
#### 一.语法：
Create trigger 触发器名 before|after 触发事件
     On 表名 for each row 执行语句
```
mysql> create trigger books_trig1 beforeinsert
   -> on users for each row
   -> insert into trigger_time values(now());
Query OK, 0 rows affected (0.05 sec)

mysql> desc users;
+-----------+-------------+------+-----+---------+----------------+
|Field    |Type       | Null | Key | Default |Extra         |
+-----------+-------------+------+-----+---------+----------------+
| user_id   |int(10)    | NO   | PRI |NULL    |auto_increment |
| user_name | varchar(50) | NO  |    |        |               |
| user_pwd  | varchar(20) |NO  |    |        |               |
|email    | varchar(50) | NO  |    |        |               |
+-----------+-------------+------+-----+---------+----------------+
4 rows in set (0.02 sec)
 

mysql> insert into usersvalues(null,'helloc','hello','hello@qq.com');
Query OK, 1 row affected (0.05 sec)
mysql> select * from users;
+---------+-----------+----------+--------------+
| user_id | user_name | user_pwd |email       |
+---------+-----------+----------+--------------+
|     10 | helloc    |hello    | |
+---------+-----------+----------+--------------+
1 row in set (0.00 sec)

mysql> select * from trigger_time;
+---------------------+
|datetimes          |
+---------------------+
| 2011-10-29 16:27:33 |
+---------------------+
1 row in set (0.00 sec)
```

#### 二.创建有多个执行语句的触发器:

语法：Create trigger 触发器名 before|after 触发事件  
     On 表名 for each row  
     Begin  
         执行语句列表  
     End  
```
mysql> delimiter&&
mysql> create trigger books_trig2 after delete
   -> on users for each row
   -> begin
   ->  insert into trigger_timevalues(now());
   ->  insert into trigger_timevalues(now());
   -> end&&
Query OK, 0 rows affected (0.01 sec)
mysql> delimiter ;


mysql> delete from users
   -> where user_id = 10;
Query OK, 1 row affected (0.06 sec)

mysql> select * from users;
Empty set (0.00 sec)

mysql> select * from trigger_time;
+---------------------+
|datetimes          |
+---------------------+
| 2011-10-29 16:27:33 |
| 2011-10-29 16:41:16 |
| 2011-10-29 16:41:16 |
+---------------------+
3 rows in set (0.00 sec)
```

#### 三.查看触发器：

语法：Show Triggers;

```
mysql> show triggers\G
*************************** 1. row***************************
  Trigger: books_trig1
    Event:INSERT
    Table:users
Statement: insert into trigger_time values(now())
   Timing: BEFORE
  Created: NULL
 sql_mode:NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
  Definer:
*************************** 2. row***************************
  Trigger: books_trig2
    Event:DELETE
    Table:users
Statement: begin
       insert into trigger_time values(now());
       insert into trigger_time values(now());
end
   Timing: AFTER
  Created: NULL
 sql_mode:NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
  Definer:
2 rows in set (0.00 sec)
```

也可在triggers表中查看触发器信息：
```
mysql> select * frominformation_schema.triggers\G

      --where trigger_name=‘触发器名';
*************************** 1. row***************************
          TRIGGER_CATALOG: NULL
           TRIGGER_SCHEMA: books
             TRIGGER_NAME: books_trig1
       EVENT_MANIPULATION: INSERT
     EVENT_OBJECT_CATALOG: NULL
      EVENT_OBJECT_SCHEMA: books
       EVENT_OBJECT_TABLE: users
             ACTION_ORDER: 0
         ACTION_CONDITION: NULL
         ACTION_STATEMENT: insert into trigger_time values(now())
       ACTION_ORIENTATION: ROW
            ACTION_TIMING: BEFORE
ACTION_REFERENCE_OLD_TABLE: NULL
ACTION_REFERENCE_NEW_TABLE: NULL
  ACTION_REFERENCE_OLD_ROW: OLD
  ACTION_REFERENCE_NEW_ROW: NEW
                  CREATED: NULL
                 SQL_MODE: NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
                  DEFINER:
*************************** 2. row***************************
          TRIGGER_CATALOG: NULL
           TRIGGER_SCHEMA: books
             TRIGGER_NAME: books_trig2
       EVENT_MANIPULATION: DELETE
     EVENT_OBJECT_CATALOG: NULL
      EVENT_OBJECT_SCHEMA: books
       EVENT_OBJECT_TABLE: users
             ACTION_ORDER: 0
         ACTION_CONDITION: NULL
         ACTION_STATEMENT: begin
       insert into trigger_time values(now());
       insert into trigger_time values(now());
end
       ACTION_ORIENTATION: ROW
            ACTION_TIMING: AFTER
ACTION_REFERENCE_OLD_TABLE: NULL
ACTION_REFERENCE_NEW_TABLE: NULL
  ACTION_REFERENCE_OLD_ROW: OLD
  ACTION_REFERENCE_NEW_ROW: NEW
                  CREATED: NULL
                 SQL_MODE: NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION
                  DEFINER:
2 rows in set (1.61 sec)
```

四.触发器的作用：
  在MySQL中，触发器执行的顺序是Before触发器、表操作（insert、update和delete）和After触发器。

五.删除触发器：
  DROP TRIGGER触发器名;

例如
```
delimiter |
create trigger submit_update
after update
on submit
for each row
begin
if OLD.status<>40 AND NEW.status=40 then
    update contestinfo set accept = accept+1 where contestinfo.contestid=NEW.contestid and contestinfo.pid=NEW.pid;
elseif OLD.status=40 AND NEW.status<>40 then
    update contestinfo set accept = accept-1 where contestinfo.contestid=NEW.contestid and contestinfo.pid=NEW.pid;
end if;
end
|
delimiter ;
```

