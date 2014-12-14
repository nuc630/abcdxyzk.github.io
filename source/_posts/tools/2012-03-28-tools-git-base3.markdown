---
layout: post
title: "git remote管理远程库"
date: 2012-03-28 21:13:00 +0800
comments: false
categories:
- 2012
- 2012~03
- tools
- tools~git
tags:
---
#### 查看当前的远程库
要查看当前配置有哪些远程仓库,可以用 git remote 命令,它会列出每个远程库的简短名字.在克隆完某个项目后,至少可以看到一个名为 origin 的远程库,Git 默认使用这个名字来标识你所克隆的原始仓库:
```
	$ git clone git://github.com/schacon/ticgit.git
	$ cd ticgit
	$ git remote
		remote也可以加上 -v 选项(译注:此为 –verbose 的简写,取首字母),显示对应的克隆地址:
	$ git remote -v
		origin git://github.com/schacon/ticgit.git
		如果有多个远程仓库,此命令将全部列出.
```
这样一来,我就可以非常轻松地从这些用户的仓库中,拉取他们的提交到本地.
#### 添加远程仓库
要添加一个新的远程仓库,可以指定一个简单的名字,以便将来引用,运行`git remote add [shortname] [url]`
```
	$ git remote
		origin
	$ git remote add pb git://github.com/paulboone/ticgit.git
	$ git remote -v
		origin git://github.com/schacon/ticgit.git
		pb git://github.com/paulboone/ticgit.git
		现在可以用字串 pb 指代对应的仓库地址了.
		比如说,要抓取所有 Paul 有的,但本地仓库没有的信息,可以运行 git fetch pb
	$ git fetch pb
		现在,Paul 的主干分支(master)已经完全可以在本地访问了,
		对应的名字是 pb/master,你可以将它合并到自己的某个分支,
		或者切换到这个分支,看看有些什么有趣的更新.
```

#### 从远程仓库抓取数据
正如之前所看到的,可以用下面的命令从远程仓库抓取数据到本地:
`$ git fetch [remote-name]`此命令会到远程仓库中拉取所有你本地仓库中还没有的数据.运行完成后,你就可以在本地访问该远程仓库中的所有分支,将其中某个分支合并到本地,或者只是取出某个分支,一探究竟.

如果是克隆了一个仓库,此命令会自动将远程仓库归于 origin 名下.所以git fetch origin 会抓取从你上次克隆以来别人上传到此远程仓库中的所有更新(或是上次 fetch 以来别人提交的更新).有一点很重要,需要记住,fetch 命令只是将远端的数据拉到本地仓库,并不自动合并到当前工作分支,只有当你确实准备好了,才能手工合并.
说明:  
	事先需要创建好远程的仓库,然后执行  
```
	git remote add [仓库名] [仓库url]  
	git fetch [远程仓库名]  
	即可抓取到远程仓库数据到本地,再用  
	git merge remotes/[仓库名]/master 
	就可以将远程仓库merge到本地当前branch.
```
这种分支方式比较适合独立-整合开发,即各自开发测试好后 再整合在一起.

#### 远程仓库的删除和重命名
在Git中可以用`git remote rename`命令修改某个远程仓库的简短名称,比如想把 pb 改成 paul,可以这么运行:
```
	$ git remote rename pb paul
	$ git remote
		origin
```
paul注意,对远程仓库的重命名,也会使对应的分支名称发生变化,原来的 pb/master 分支现在成了paul/master.
碰到远端仓库服务器迁移,或者原来的克隆镜像不再使用,又或者某个参与者不再贡献代码,那么需要移除对应的远端仓库,可以运行 git remote rm 命令:
```
	$ git remote rm paul
	$ git remote
		origin
```

