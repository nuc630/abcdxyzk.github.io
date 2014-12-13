---
layout: post
title: "git建库，配置颜色分支名"
date: 2012-05-01 17:00:00 +0800
comments: false
categories:
- 2012
- 2012~05
- system
- system~tools
tags:
- git
---
#### 建一个库
##### 服务器
```
mkdir allgit
cd allgit
git --bare init
```
##### 客户端
```
git clone username@192.168.1.2:/home/abc/allgit allgit
cd allgit
...
git push origin master // 第一次的时候用， 以后直接用 git push
```

#### 配置颜色分支名
##### git 配色
/home/username/.gitconfig
```
[color]
    branch = auto
    status = auto
    diff = auto
    log = auto
    grep = auto
```

##### bash 显示分支名
/home/username/.bash_profile  或 /home/username/.bashrc ？
```
	function parse_git_branch {
	  git branch --no-color 2> /dev/null | sed -e '/^[^*]/d' -e 's/* \(.*\)/(\1)/'
	}

	function proml {
	  local YELLOW="\[\033[01;32m\]"
	  local WHITE="\[\033[01;00m\]"
	#  local YELLOW="\[\033[0;33m\]"
	#  local WHITE="\[\033[1;37m\]"
	#  local cyan="\[\033[1;36m\]"
	  case $TERM in
	    xterm*)
	    TITLEBAR='\[\033]0;\u@\h:\w\007\]'
	    ;;
	    *)
	    TITLEBAR=""
	    ;;
	  esac
	PS1="${TITLEBAR}\
	$WHITE\u@\h:\w$YELLOW\$(parse_git_branch)\
	$WHITE\$ "
	PS2='> '
	PS4='+ '
	}
	proml
```

