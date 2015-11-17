---
layout: post
title: "alias命令"
date: 2015-11-17 09:48:00 +0800
comments: false
categories:
- 2015
- 2015~11
- tools
- tools~command
tags:
---

功能说明: 设置指令的别名。

语   法: alias[别名]=[指令名称]

参   数: 若不加任何参数，则列出目前所有的别名设置。

举   例: 
```
	alias
	alias egrep='egrep --color=auto'
	alias fgrep='fgrep --color=auto'
	alias grep='grep --color=auto'
	alias l='ls -CF'
	alias la='ls -A'
	alias ll='ls -alF'
	alias ls='ls --color=auto'
```

说   明：用户可利用alias，自定指令的别名。若仅输入alias，则可列出目前所有的别名设置。　alias的效力仅及于该次登入的操作。若要每次登入是即自动设好别名，可在/etc/profile或自己的~/.bashrc中设定指令的别名。

  如果你想给每一位用户都生效的别名，请把alias la='ls -al' 一行加在/etc/bashrc最后面，bashrc是环境变量的配置文件 /etc/bashrc和~/.bashrc 区别就在于一个是设置给全系统一个是设置给单用户使用.

