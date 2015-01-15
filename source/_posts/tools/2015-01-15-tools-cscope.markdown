---
layout: post
title: "vim+cscope"
date: 2015-01-15 15:41:00 +0800
comments: false
categories:
- 2015
- 2015~01
- tools
- tools~base
tags:
---

Ctags:  
按下"Ctrl+]", 光标会自动跳转到其定义处  
按下"ctrl+t", 返回上一个查找的地方  

-----------

```
yum install cscope
sudo apt-get install cscope
```

#### 生成Cscope数据
```
cscope –Rbq
```

### Cscope相关命令
所有的cscope命令都是通过向主cscope命令”:cscope”传递参数选项。她最短的缩写是”:cs”。”:scscope”命令也做同样的事情并且同时会横向分隔窗口（简称：”scs”）。

可用的缩写有：
#### add ：增加一个新的cscope数据库/链接库
  使用方法：
```
	:cs add {file|dir} [pre-path] [flags]
```
  其中：  
 [pre-path] 就是以-p选项传递给cscope的文件路径，是以相对路径表示的文件前加上的path，这样你不要切换到你数据库文件所在的目录也可以使用它了。  
 [flags] 你想传递给cscope的额外旗标

  实例：
```
	:cscope add /root/code/vimtest/ftpd
	:cscope add /project/vim/cscope.out /usr/local/vim
	:cscope add cscope.out /usr/local/vim –C
```

#### find ：查询cscope。所有的cscope查询选项都可用除了数字5（“修改这个匹配模式”）。
  使用方法：
```
	:cs find {querytype} {name}
```
  其中：
 {querytype} 即相对应于实际的cscope行接口数字，同时也相对应于nvi命令：
```
	0或者s   —— 查找这个C符号
	1或者g   —— 查找这个定义
	2或者d   —— 查找被这个函数调用的函数（们）
	3或者c   —— 查找调用这个函数的函数（们）
	4或者t   —— 查找这个字符串
	6或者e   —— 查找这个egrep匹配模式
	7或者f   —— 查找这个文件
	8或者i   —— 查找#include这个文件的文件（们）
```
  实例：（#号后为注释）
```
	:cscope find c ftpd_send_resp	# 查找所有调用这个函数的函数（们）
	:cscope find 3 ftpd_send_resp	# 和上面结果一样

	:cscope find 0 FTPD_CHECK_LOGIN	# 查找FTPD_CHECK_LOGIN这个符号
	执行结果如下：
	Cscope tag: FTPD_CHECK_LOGIN                   
	   #   line  filename / context / line
	   1     19  ftpd.h <<GLOBAL>>
		         #define FTPD_CHECK_LOGIN() \
	   2    648  ftpd.c <<ftpd_do_pwd>>
		         FTPD_CHECK_LOGIN();
	   3    661  ftpd.c <<ftpd_do_cwd>>
		         FTPD_CHECK_LOGIN();
	Enter nr of choice (<CR> to abort):

	然后输入最前面的序列号即可。
```

#### help ：显示一个简短的摘要。
使用方法：
```
	:cs help
```

#### kill ：杀掉一个cscope链接（或者杀掉所有的cscope链接）
使用方法：
```
	:cs kill {num|partial_name}
```
为了杀掉一个cscope链接，那么链接数字或者一个部分名称必须被指定。部分名称可以简单的是cscope数据库文件路径的一部分。要特别小心使用部分路径杀死一个cscope链接。假如指定的链接数字为-1，那么所有的cscope链接都会被杀掉。

#### reset：重新初始化所有的cscope链接。
使用方法：
```
	:cs reset
```
 
#### show：显示cscope的链接
使用方法：
```
	:cs show
```

假如你在使用cscope的同时也使用ctags，|:cstag|可以允许你在跳转之前指定从一个或另一个中查找。例如，你可以选择首先从cscope数据库中查找，然后再查找你的tags文件（由ctags生成）。上述执行的顺序取决于|csto|的值。  
|:cstag|当从cscope数据库中查找标识符时等同于“:cs find g”。  
|:cstag|当从你的tags文件中查找标识符时等同于“|:tjump|”。

