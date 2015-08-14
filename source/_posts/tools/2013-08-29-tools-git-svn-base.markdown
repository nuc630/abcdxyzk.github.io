---
layout: post
title: "git-svn"
date: 2013-08-29 14:37:00 +0800
comments: false
categories:
- 2013
- 2013~08
- tools
- tools~git
tags:
---
#### 常用
```
1、git-svn clone your_svn_repository
2、git add/commit
3、git-svn rebase	获取中心svn repository的更新；
4、git-svn dcommit	将本地git库的修改同步到中心svn库。
```
------

git-svn默认包含在Git的安装包中，不过在Ubuntu中，git-svn是作为一个独立的Package需要额外安装的(sudo apt-get install git-svn)。安装后你就可以使用git svn xxx命令来操作中心SVN代码库了。当然如果你要使用与git svn等价的git-svn命令的话，你还需要将/usr/lib/git-core配置到你的PATH环境变量中，否则Shell会提示你无法找到 git-svn这个命令。

* 检出一个已存在svn repository(类似于svn checkout)  
我们可以通过git-svn clone命令完成这个操作： git-svn clone your_svn_repository_url

* 从中心服务器的svn repository获取最新更新  
这个操作可以通过"git-svn rebase"完成。注意这里用的是rebase，而不是update。update命令对于通过git-svn检出的svn repostory的git版本库是不可用的。

* 查看提交历史日志  
这个简单，使用"git-svn log"，加上-v选项，还可以提供每次commit操作涉及的相关文件的详细信息。

* 将本地代码同步到Svn服务器  
完成这一操作需要通过"git-svn dcommit"命令。这个命令会将你在本地使用git commit提交到本地代码库的所有更改逐一提交到svn库中。加上-n选项，则该命令不会真正执行commit到svn的操作，而是会显示会有哪些本地 变动将被commit到svn服务器。git-svn dcommit似乎不能单独提交某个本地版本的修改，而是一次批量提交所有与svn中心版本库的差异。

##### 下面是一个git-svn的一般使用流程：  
1、git-svn clone your_svn_repository；  
2、修改本地代码，使用git add/commit将修改提交到本地git库；  
3、定期使用git-svn rebase获取中心svn repository的更新；  
4、使用git-svn dcommit命令将本地git库的修改同步到中心svn库。

##### 冲突
使用git-svn处理代码冲突的步骤有些繁琐，不过瑕不掩瑜吧。这里用一个小例子来说明一下。

假设某svn中心库上的某个项目foo中只有一个源码文件foo.c：  
* 我在使用git-svn clone检出版本时，foo.c当时只有一个commit版本信息："svn v1"；  
* clone出来后，我在本地git库中修改foo.c，并通过git commit提交到本地git库中，版本为"git v1"；  
* 不过与此同时另外一个同事也在修改foo.c这个文件，并已经将他的修改提交到了svn库中，版本为"svn v2"；  
* 此时我使用git-svn dcommit尝试提交我的改动，git-svn提示我：  
  Committing to svn://10.10.1.1:80/foo ...  
  M foo.c  
  事务过时: 过期: ”foo/foo.c“在事务“260-1” at /usr/lib/git-core/git-svn line 570  
* 使用git-svn rebase获取svn服务器上的最新foo.c，导致与foo.c冲突，不过此时svn版本信息已经添加到本地git库中(通过git log可以查看)，git-svn rebase提示你在解决foo.c的冲突后，运行git rebase --continue完成rebase操作；  
* 打开foo.c，修改代码，解决冲突；  
* 执行git rebase --continue，git提示我：  
You must edit all merge conflicts and then  
mark them as resolved using git add  
* 执行git add foo.c，告知git已完成冲突解决；  
* 再次执行git rebase --continue，提示"Applying: git v1"，此时"git v1"版本又一次成功加入本地版本库，你可通过git log查看；  
* 执行git-svn dcommit将foo.c的改动同步到svn中心库，到此算是完成一次冲突解决。  

* 设置忽略文件  
要忽略某些文件, 需要首先执行如下命令:  
git config --global core.excludesfile ~/.gitignore  
然后编辑 vi ~/.gitignore.  
例如: 需要忽略vim的临时文件，就写:  
.*.swp


