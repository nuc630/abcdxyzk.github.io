---
layout: post
title: "octopress+github建立个人博客"
date: 2014-11-13 22:59:03 +0800
comments: true
categories: 
- 2014
- 2014~11
- blog
- blog~octopress
tags:
- blog
- octopress
---

<h2>Step 1 安装git ruby nodejs</h2>
```
	sudo apt-get install git zlib1g-dev libyaml-dev openssl libssl-dev tcl-dev tk-dev node/nodejs
	sudo apt-get install ruby ruby-dev 安装的版本偏低不行，要1.9.3以上https://www.ruby-lang.org/en/downloads/
```
<h2>Step 2 准备octopress</h2>
```
	git clone git://github.com/imathis/octopress.git octopress
	cd octopress    # 如果你使用RVM, 你会被询问你是否信任 .rvmrc 文件 (选择 yes).
	ruby --version  # 这条命令应该输出 Ruby 1.9.3
	然后安装依赖
	sudo gem install bundler
	rbenv rehash    # 如果你使用 rbenv, 执行 rehash 以运行 bundle 命令 (好像不需要这条)
	bundle install    # 在octopress目录运行
	最后安装默认主题
	rake install
```
</br>

<h2>Step 3 部署到github上</h2>
(1)以 用户名/用户名.github.io 的格式建立一个新项目。</br>
(2)部署</br>
首先运行</br>
rake setup_github_pages</br>
这条命令会询问你刚才建立的项目的地址，按提示输入，然后就会生成一些用于部署的文件和_deploy目录，_deploy目录就是对应master分支。 接着执行</br>
```
	rake generate
	rake deploy  # 会cd到_deploy目录运行 commit 和 push
```
这两条命令会生成博客内容，然后添加到git中，自动执行git commit然后推送到主分支(master branch)。几分钟后，你会收到github通知你你的提交已经被接受并发布了你的网站的email。</br>

rake generate可能报错：</br>
```
	Error reading file /var/lib/gems/1.9.1/gems/jekyll-sitemap-0.6.1/lib/sitemap.xml: No such file or directory - /home/kk/kk/github/octopress/source/var/lib/gems/1.9.1/gems/jekyll-sitemap-0.6.1/lib/sitemap.xml
```
是jekyll-sitemap-0.6.1的bug，修改Gemfile.lock, jekyll-sitemap (0.6.1) 改成 jekyll-sitemap (0.6.3), 再</br>
```
	bundle install
```


不要忘记把为你的博客提交source（Don’t forget to commit the source for your blog）</br>
```
	git add .
	git commit -m 'your message'
	git push origin source
```
<h2>Step 4 发布博客</h2>
你发布的文章被放在source/_posts目录下，并按照Jekyll的命名规则命名：YYYY-MM-DD-post- title.markdown。这个名字会被用于生成url且日期会被用于为文章按时间排序。 但这样比较麻烦，于是Octopress提供了一个rake task来自动按照正确的命名规则建立博文，并生成基本内容。</br>
格式是：rake new_post["title"]</br>
样例：</br>
    rake new_post["tt"]</br>
    # 这条命令会创建 source/_posts/2011-07-03-tt.markdown文件</br>
会生成如下内容的文件：</br>
```
	---
	layout: post
	title: "tt"
	date: 2011-07-03 5:59
	comments: true
	external-url:
	categories:
	---
```
你可以在这里设置评论功能开关，设置分类。如果你的博客有多个作者共用，你可以在文件中添加【author:Your Name】。如果你在编辑一个草稿，你可以添加【published： false】以使其在生成博客内容时被自动忽略。</br>

<h2>Step 5 生成 & 预览</h2>
rake generate # 在公开目录中生成博文和页面
rake watch # 查看 source/ and sass/ 的改动
rake preview # 在浏览器中输入 http://localhost:4000 即可预览。

<h2>Step 6 推送到github</h2>
rake deploy
然后过几分钟，github就会自动更新你的博客了。</br>
注意：执行rake deploy前一定要先rake generate一下</br>
不要忘记把为你的博客提交source（Don’t forget to commit the source for your blog）</br>
```
	git add .
	git commit -m 'your message'
	git push origin source 
```
-----------------------------------

<h2>另一台机子的时候</h2>
安装需要软件，然后clone自己的代码库</br>

```
	git checkout -b source origin/source
	sudo gem install bundler
	bundle install
	rake install
	rake setup_github_pages
```
输入项目的地址。</br>
然后到_deploy目录git pull才能运行rake deploy。</br>
_deploy目录就是对应master分支</br>
不然先运行rake deploy会在_deploy目录先commit，再push，这就会导致其他和另外机子上提交的冲突。</br>
如果先rake deploy的话，可以在_deploy目录reset回去，然后pull。</br>

记住多台机子操作的时候一开始先
```
	git pull
	cd _deploy
	git pull
```

