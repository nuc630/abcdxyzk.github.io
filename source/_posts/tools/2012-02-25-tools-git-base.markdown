---
layout: post
title: "git分布式版本控制系统"
date: 2012-02-25 14:44:00 +0800
comments: false
categories:
- 2012
- 2012~02
- tools
- tools~git
tags:
- git
---
####【GIT 基础】
GIT 使用 SHA-1哈希码（40个字符）来标识提交，同时保证本次提交后整体（一个快照）的完整性。  
##### 文件状态：
文件状态分为：未跟踪(untracked) 和已跟踪 (tracked)，已跟踪又分为三种状态：已暂存（staged），已修改（modified），已提交（committed）

一般过程如下：
```
0） 用 git pull 下载远程代码库代码
1） 新建文件，该文件状态为“未跟踪”，位于工作区；
2） 用 git add a.txt 加入该文件，状态变为已跟踪的“已暂存”，位于暂存区；
3） 用 git commit a.txt -m "ha" 提交该文件，状态变为“已提交”，位于代码库（repository ）
4） 用 git push 提交到远程代码库
```
注意：用 git status 查看目前所有文件的状态。
 
##### GIT 配置：
三种配置范围类型：
```
1）所有用户 --system，  存在 /etc/gitconfig 文件中。(对windows来说，是msysgit 的安装目录)
2）本用户 --global，   存在 ~/.gitconfig 文件中。（对windows 来说，是 C:\Documents andSettings\$USER）
3）本项目            存在 .git/config 文件中。
```
注意：后面的重载前面的。例如：用--global设置，可以在所有项目中使用这个设置；如果有一个项目你想使用一个特别的设置，就可以使用不带参数的git config 重新设置，则它只作用于这个项目。如果用 git config --list 查看这些设置，可能会列出多个，但最后那个起作用。

###### 用户信息
$ git config --global user.name "John Doe"  
$ git config --global user.email  
文本编辑器  
$ git config --global core.editor vim  
查看配置信息  
$ git config --list  
或者只看一个信息：  
$ git config <key>

####【常用操作】 
##### 基本
```
$ git grep XXX						查看某个关键字
$ git init						初始化仓库，如果该目录有文件，则都会处于“未跟踪”状态的。
$ git clone git://github.com/schacon/grit.git mygrit	克隆仓库，并换个名字
说明： 
	通过git clone获取的远端git库，只包含了远端git库的当前工作分支。
	如果想获取其它分支信息，需要使用 “git branch –r” 来查看， 
	如果需要将远程的其它分支代码也获取过来，可以使用命令 “ git checkout -b 本地分支名 远程分支名”，
	其中，远程分支名为 “git branch –r” 所列出的分支名， 一般是诸如“origin/分支名”的样子。
	如果本地分支名已经存在， 则不需要“-b”参数。
$ git add readme.txt					跟踪一个新文件：                                                 
说明： 
	1) 跟踪之后，该文件状态是“已暂存”的。 （Changes to be committed:）
	2) 修改一个已暂存的文件，该文件会出现在两个记录区中。
	3) 如果跟踪错了，想把他删除（不删除工作区的），则用 git rm --cachedreadme.txt。
	   状态变成“未跟踪”，如果该文件已经修改了，则加  -f参数强行删除暂存区的文件（已修改的文件不被覆盖）。
$ git commit -m "fix bug1"				提交更新

$ git diff						查看尚未暂存的更新，比较“已修改”和“已暂存（或已提交）”。
$ git diff --cached 或 $ git diff --staged		查看尚未提交的更新，比较“已暂存”和已提交。
$ git rm -f a.a						强行移除修改后文件(从暂存区和工作区中删除)
$ git mv file1 file2					改名（只改工作区和暂存区）
$ git stash						将你当前未提交到本地（和服务器）的代码推入到Git的栈中 
$ git stash apply					将Git的栈中代码恢复
$ git commit --file notefile				从文件中取注释
$ git checkout A.java					抛弃已修改，用已提交覆盖，此命令对已暂存文件没作用。 
$ git rm --cached A.java				移除已跟踪文件，恢复到“未跟踪”，如果文件已修改，则需-f，并且不覆盖修改过的内容。 
```
##### 后悔药
```
$ git reset HEAD readme.txt				取消已暂存的文件（已暂存到已修改）
$ git reset --hard HEAD					重置所有修改，就像没有修改过一样。
$ git reset --hard HEAD~3				最新的3次提交全部重置，就像没有提交过一样。
说明：
	--hard reset后再执行 git push origin HEAD --force 也将删除远程的提交。
```
##### 历史查看：
```
$ git show 356f6def9d3fb7f3b9032ff5aa4b9110d4cca87e	显示具体的某次的改动的修改
$ git log						查看提交历史(全部）
$ git log --stat					查看提交历史，并显示统计信息
$ git log -p -2						查看最近2次提交历史并查看差异
$ git log --since=2.weeks				查看最近2周内提交历史
$ git log --since="2008-09-14"				查看某个时刻之后的提交历史
$ git log --until="2008-09-14"				查看某个时刻以前的提交历史
$ git log --author="stupid"				查看某个作者的提交历史
$ git log --pretty=oneline				列出所有改动历史
$ git log --pretty=format:"%h - %an, %ar : %s"		查看提交历史，并格式化显示
例如：
	$ git log --pretty=format:"%h - %an, %ar : %s"
	ca82a6d - Scott Chacon, 11 months ago : changed the versionnumber
	085bb3b - Scott Chacon, 11 months ago : removed unnecessary testcode
	a11bef0 - Scott Chacon, 11 months ago : first commit
 
%H 提交对象（commit）的完整哈希字串
%h 提交对象的简短哈希字串
%T 树对象（tree）的完整哈希字串
%t 树对象的简短哈希字串
%P 父对象（parent）的完整哈希字串
%p 父对象的简短哈希字串
%an 作者（author）的名字
%ar 作者修订日期，按多久以前的方式显示
%cn 提交者(committer)的名字
%cr 提交日期，按多久以前的方式显示
%s 提交说明
 
$ git log --pretty=format:"%h %s" --graph查看提交历史，并图形化显示
例如：
$ git log --pretty=format:"%h %s" --graph
* 2d3acf9 ignore errors from SIGCHLD on trap
*  5e3ee11 Merge branch 'master' ofgit://github.com/dustin/grit
|\
| * 420eac9 Added a method for getting the current branch.
* | 30e367c timeout code and tests
* | 5a09431 add timeout protection to grit
* | e1193f8 support for heads with slashes in them
|/
* d6016bc require time for xmlschema
*  11d191e Merge branch 'defunkt' into local
 
其它：
--shortstat 只显示 --stat 中最后的行数修改添加移除统计。
--name-only 仅在提交信息后显示已修改的文件清单。
--name-status 显示新增、修改、删除的文件清单。
--abbrev-commit 仅显示 SHA-1 的前几个字符，而非所有的 40 个字符。
--relative-date 使用较短的相对时间显示（比如，“2 weeks ago”）。
--graph 显示 ASCII 图形表示的分支合并历史。
--pretty 使用其他格式显示历史提交信息。可用的选项包括 oneline，short，full，fuller 和format（后跟指定格式）。
```
##### 忽略某些文件——很有用
在.gitignore 文件中加入需要忽略的内容
```
*.a			# 忽略所有 .a 结尾的文件
!lib.a			# 但lib.a 除外
/TODO			# 仅仅忽略项目根目录下的 TODO 文件，不包括 subdir/TODO
build/			# 忽略build/ 目录下的所有文件
doc/*.txt		# 会忽略 doc/notes.txt 但不包括 doc/server/arch.txt
```
注意：.gitignore 文件放在工程的根目录即可，但是要把它用 git add 加入跟踪或者提交。


