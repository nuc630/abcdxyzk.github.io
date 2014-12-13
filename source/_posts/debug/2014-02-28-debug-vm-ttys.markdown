---
layout: post
title: "vmware 串口调试"
date: 2014-02-28 17:48:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~base
tags:
---
  在系统内核开发中，经常会用到串口调试，利用VMware的Virtual Machine更是为调试系统内核如虎添翼。那么怎么搭建串口调试环境呢？

Virtual Machine 主要有三种串口调试技术，可以在serial port的配置界面找到：  

1. Use physical serial port      即使用物理机串口，当用串口线盒另一台电脑连接时，就用这种方式
2. Use output file                   即把串口数据输出到宿主机某文件中，当只需要看输出结果的时候可以用这种方式，简单方便
3. Use named pipe                把串口输出到命名管道，命名管道可读可写，也就可以交互，进行一些debug工作，而不是简单的看结果

  因为前两种相对简单易用就不具体介绍了，这里主要说第三种用命名管道调试方法。命名管道，在Linux中是进程间通信(IPC)的一种方式，两个进 程可以通过读写管道来交换数据。这里就是运用了这种技术，通过把串口绑定一个有名管道，对有名管道的读写交换串口数据。也有两种方式：1. 宿主机与虚拟机之间， 2. 在同一宿主机上，两虚拟机间通过绑定同一个宿主机上的有名管道。问题的关键在于如何把虚拟机串口绑定到宿主机的某一有名管道，而第一种方式则需要找到一种 方式使得主机如何读写有名管道来交互，经过一阵Google终于找到分别在Linux和Windows分别试验成功的工具。

  在Windows中有名管道式通过路径//./pipe/namedpipe来创建的，当然你可以指定到其他机子如//192.168.1.10 /pipe/namedpipe，而在Linux中，/tmp/mypipe就可以了。创建好有名管道后，就是如何和管道交互了。目前，无论是 Windows还是Linux，似乎都没有一款工具可以直接读写有名管道的，而我找到的两个工具都是通过把有名管道和Socket绑定，通过读写 Socket来间接读写管道。

#### 下面我就简要介绍一下在Windows和Linux下如何配置：

##### Linux Host:

###### Host  ~  Virtual Machine
```
1. configure VM
a. add hardware -> Serial port
b. using named pipe
c. /tmp/isocket
d. this end is server & far end is application
e. check Yield CPU on poll
f. start Virtual Machine

2. socat /tmp/isocket tcp4-listen:9001 &
/tmp/socket: VMware call it 'named piped', actually it is Unix Daemon Socket, so you shouldn't use pipe:/tmp/socket
3. telnet 127.0.0.1 9001
```
Trouble Shoot: 有时候会遇到错误Connection closed by foreign host，或者telnet一开，socat就能退出，很可能是你没power on虚拟机，有名管道还没创建，你就socat，这样也会创建一个名为isocket的文件但只是普通文件。具体的细节请看socat help  
start Virtual Machine first, than run the socat, and telnet  
(Note you must have permission to all resource, /tmp/socket, VM and so on)

###### Vritual Machine ~ Virtual Machine
```
1. configure VM
a. add hardware -->　serial port
b. Using named pipe, configure /tmp/isocket 
c.  this end is server & far end is Virtual Machine
d. check Yield CPU on poll
e. start VM

2. Another VM
a. add hardware  -->  Serial Port
b. Using named pipe, configure /tmp/isocket 
c.  this end is client & far end is Virtual Machine 
d. check Yield CPU on poll
e. start VMs
```

##### Windows Host:

###### Host ~ Virtual Machine
```
1. configure VM
a. add hardware --> serial port
b. using named pipe
c. //./pipe/vmwaredebug
d. this end is client & far end is application
e. check Yield CPU on poll

2. using 3rd-party tool to communicate with named pipe
a. down the tool 
b. install service
cmd>vmwaregateway.exe /r
c. start service
c:/> net start vmwaregateway
d. telnet 127.0.0.1 567
3. start Virtual Machine
```
如果你使用的是vmwaregateway.exe这个小工具，这里的管道名就必须是vmwaredebug，除非你把它的源代码download下来自己改改。

###### Vritual Machine ~ Virtual Machine
```
1. configure VM
a. add hardware -->　serial port
b. Using named pipe, //./pipe/vmwaredebug
c.  this end is server & far end is Virtual Machine
d. check Yield CPU on poll
e. start VM

2. Another VM
a. add hardware  -->  Serial Port
b. Using named pipe, //./pipe/vmwaredebug
c.  this end is client & far end is Virtual Machine 
d. check Yield CPU on poll
e. start VMs
```



