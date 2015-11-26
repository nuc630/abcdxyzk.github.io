---
layout: post
title: "screen"
date: 2012-02-18 12:53:00 +0800
comments: false
categories:
- 2012
- 2012~02
- tools
- tools~base
tags: 
---

#### 断开控制台而不结束会话-Screen

设想一下，你通过 ssh 连接到了一台服务器，接着你开始编译一个软件。这或许要占用你一个小时甚至更多的时间，突然！你需要离开，或者是断开网络了~  
怎么办？下次再重新编译一次么？还有例外一种办法~（当然，我指的不是一开始放在后台运行。）  
Screen！

#### 一、启动 Screen
下载配置文件[screenrc](/download/tools/screenrc)，放到~/.screenrc，注意要加一个.号。然后启动 Screen 再简单不过了，在 Shell 中运行 screen ，按回车，就进入 Screen 输入环境了。

#### 二、给 Screen 的指令
和VIM类似，当你想给 Screen 发送指令，而不是给 shell 输入指令的时候需要用到特定的组合键：Ctrl-A 。（这类似于 VIM 中的 ESC。）当你执行Ctrl-A 后就可以引起 Screen 的注意了。

#### 三、我在 Screen 中么？
通过 screen -list 调用 screen 可以看到类似如下界面：  
这标明你正处于 Screen 中。并且进程号是8941。

#### 四、还有哪些命令？
通过 Ctrl-A and ? 的方式你可以看到如下列表：  
ok！一切都明了了！

#### 五、离开
这时我需要离开那台正在编译软件的主机了，通过 Ctrl+A and D。我们脱离了 screen。但是 screen 依然在后台运行着。

#### 六、归来
当你回到这台主机，并想重新进入之前的 screen 时，以前看到的 进程号（PID）就要发挥作用了。  
通过命令：  
screen -r pid  
就可以回到之前的Screen了。  
如果你觉得记住 PID 是一件很麻烦的事情，也可以使用 -S 参数：  
scree  -S latteye  
这样就可以打开一个名为 latteye 的会话，下次连接时使用：  
screen -r latteye   
即可。

#### 七、特殊情况
有些时候我们离开 screen 并不是那么正常，不一定会按 Ctrl-a + D 来离开 Screen，比如网络突然断开的时候。  
这个时候，若我们重新回到主机，则通过 -r 参数是无法连接 screen 的，我们还需要 -d 的帮助：  
screen -d -r pid
 
-----
 
命令其实超简单的：  
直接在终端上输入 screen , 这个时候，服务器端会启一个新的终端，但这个终端，与之前的普通终端不一样，它不隶属于 sshd 进程组，这样，当本地终端关闭后，服务器终端不会被 kill。  
当然，优点还不止这么些，在服务器终端里执行任务时，你甚至可以随时地切换到本地终端做些其他事情，然后，要回去时，再恢复到刚才已经打开的服务器终端里，如果刚才的任务没有结束，还可以继续执行任务。  
操作步骤：  
首先，进入 screen -S sessionname终端。(sessionname是为了区分你的session)  
然后按 ctrl + a，再按 d键暂时退出终端。  
当要返回时， 先查看刚才的终端进程ID， screen -list  
或直接  
 screen -r xx(刚才的sessionname)就可以了   
当然，当你开了很多个session后，打算关闭几个session，可以进入到session后，exit一下就可以了.  
```
	Ctrl + a + ?            显示所有键绑定信息
	Ctrl + a + w            显示所有窗口列表
	Ctrl + a + a            切换到之前显示的窗口
	Ctrl + a + c            创建一个新的运行shell的窗口并切换到该窗口
	Ctrl + a + n            切换到下一个窗口
	Ctrl + a + p            切换到前一个窗口(与C-a n相对)
	Ctrl + a + 0..9         切换到窗口0..9
	Ctrl + a + " + 0..99    切换到窗口0..99，用于超过9个窗口的切换
	Ctrl + a + a            发送 C-a到当前窗口
	Ctrl + a + d            暂时断开screen会话
	Ctrl + a + k            杀掉当前窗口
	Ctrl + a + [ OR Esc     进入拷贝/回滚模式，Space 第一次按为标记copy区起点，第二次按为终点
	Ctrl + a + ]            把刚刚在 copy mode 选定的内容贴上
```
