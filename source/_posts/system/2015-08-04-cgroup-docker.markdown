---
layout: post
title: "CentOS 6 使用 docker"
date: 2015-08-04 10:02:00 +0800
comments: false
categories:
- 2015
- 2015~08
- system
- system~cgroup
tags:
---
http://www.linuxidc.com/Linux/2014-01/95513.htm

#### 一、禁用selinux
由于Selinux和LXC有冲突，所以需要禁用selinux。编辑/etc/selinux/config，设置两个关键变量。   
```
	SELINUX=disabled
	SELINUXTYPE=targeted
```

#### 二、配置Fedora EPEL源
```
	sudo yum install http://ftp.riken.jp/Linux/fedora/epel/6/x86_64/epel-release-6-8.noarch.rpm
```

#### 三、添加hop5.repo源
```
	cd /etc/yum.repos.d
	sudo wget http://www.hop5.in/yum/el6/hop5.repo
```

#### 四、安装Docker
```
	sudo yum install docker-io
```

-------------

http://www.server110.com/docker/201411/11105.html

#### 启动docker服务
```
	[root@localhost /]# service docker start
	Starting cgconfig service:                                 [  OK  ]
	Starting docker:                                           [  OK  ]
```

#### 基本信息查看

docker version：查看docker的版本号，包括客户端、服务端、依赖的Go等
```
	[root@localhost /]# docker version
	Client version: 1.0.0
	Client API version: 1.12
	Go version (client): go1.2.2
	Git commit (client): 63fe64c/1.0.0
	Server version: 1.0.0
	Server API version: 1.12
	Go version (server): go1.2.2
	Git commit (server): 63fe64c/1.0.0
```

docker info ：查看系统(docker)层面信息，包括管理的images, containers数等

```
	[root@localhost /]# docker info
	Containers: 16
	Images: 40
	Storage Driver: devicemapper
	 Pool Name: docker-253:0-1183580-pool
	 Data file: /var/lib/docker/devicemapper/devicemapper/data
	 Metadata file: /var/lib/docker/devicemapper/devicemapper/metadata
	 Data Space Used: 2180.4 Mb
	 Data Space Total: 102400.0 Mb
	 Metadata Space Used: 3.4 Mb
	 Metadata Space Total: 2048.0 Mb
	Execution Driver: lxc-0.9.0
	Kernel Version: 2.6.32-431.el6.x86_64
```

#### 5 镜像的获取与容器的使用

镜像可以看作是包含有某些软件的容器系统，比如ubuntu就是一个官方的基础镜像，很多镜像都是基于这个镜像“衍生”，该镜像包含基本的ubuntu系统。再比如，hipache是一个官方的镜像容器，运行后可以支持http和websocket的代理服务，而这个镜像本身又基于ubuntu。

搜索镜像
```
	docker search <image>：在docker index中搜索image
```

```
	[root@localhost /]# docker search ubuntu12.10
	NAME                        DESCRIPTION                                     STARS     OFFICIAL   AUTOMATED
	mirolin/ubuntu12.10                                                         0
	marcgibbons/ubuntu12.10                                                     0
	mirolin/ubuntu12.10_redis                                                   0
	chug/ubuntu12.10x32         Ubuntu Quantal Quetzal 12.10 32bit  base i...   0
	chug/ubuntu12.10x64         Ubuntu Quantal Quetzal 12.10 64bit  base i...   0
```

下载镜像
```
	docker pull <image> ：从docker registry server 中下拉image
```

```
	[root@localhost /]# docker pull chug/ubuntu12.10x64
```

查看镜像 
```
	docker images： 列出images
	docker images -a ：列出所有的images（包含历史）
	docker images --tree ：显示镜像的所有层(layer)
	docker rmi  <image ID>： 删除一个或多个image
```

使用镜像创建容器

```
	[root@localhost /]# docker run chug/ubuntu12.10x64  /bin/echo hello world
	hello world
```

交互式运行
```
	[root@localhost /]# docker run -i -t chug/ubuntu12.10x64  /bin/bash
	root@2161509ff65e:/#
```

运行Container
```
	$ docker run --name shell -i -t chug/ubuntu12.10x64 /bin/bash 
     
	$ docker run -t -i efd1e7457182 /bin/bash 
```
两个参数，-t表示给容器tty终端，-i表示可以interactive，可以交互。

查看容器
```
	docker ps ：列出当前所有正在运行的container
	docker ps -l ：列出最近一次启动的container
	docker ps -a ：列出所有的container（包含历史，即运行过的container）
	docker ps -q ：列出最近一次运行的container ID
```

再次启动容器

```
	docker start/stop/restart <container> ：开启/停止/重启container
	docker start [container_id] ：再次运行某个container （包括历史container）
	docker attach [container_id] ：连接一个正在运行的container实例（即实例必须为start状态，可以多个窗口同时attach 一个container实例）
	docker start -i <container> ：启动一个container并进入交互模式（相当于先start，在attach）

	docker run -i -t <image> /bin/bash ：使用image创建container并进入交互模式, login shell是/bin/bash
	docker run -i -t -p <host_port:contain_port> ：映射 HOST 端口到容器，方便外部访问容器内服务，host_port 可以省略，省略表示把 container_port 映射到一个动态端口。
	注：使用start是启动已经创建过得container，使用run则通过image开启一个新的container。
```

删除容器

```
	docker rm <container...> ：删除一个或多个container
	docker rm `docker ps -a -q` ：删除所有的container
	docker ps -a -q | xargs docker rm ：同上, 删除所有的container
```

#### 6 持久化容器与镜像

##### 6.1 通过容器生成新的镜像

运行中的镜像称为容器。你可以修改容器（比如删除一个文件），但这些修改不会影响到镜像。不过，你使用docker commit <container-id> <image-name>命令可以把一个正在运行的容器变成一个新的镜像。
```
	docker commit <container> [repo:tag] 将一个container固化为一个新的image，后面的repo:tag可选。
```

```
	[root@localhost /]# docker images
	REPOSITORY            TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
	chug/ubuntu12.10x64   latest              0b96c14dafcd        4 months ago        270.3 MB
	[root@localhost /]# docker commit d0fd23b8d3ac chug/ubuntu12.10x64_2
	daa11948e23d970c18ad89c9e5d8972157fb6f0733f4742db04219b9bb6d063b
	[root@localhost /]# docker images
	REPOSITORY              TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
	chug/ubuntu12.10x64_2   latest              daa11948e23d        6 seconds ago       270.3 MB
	chug/ubuntu12.10x64     latest              0b96c14dafcd        4 months ago        270.3 MB
```

##### 6.2 持久化容器

export命令用于持久化容器
```
	docker export <CONTAINER ID> > /tmp/export.tar
```

##### 6.3 持久化镜像

Save命令用于持久化镜像

```
    docker save 镜像ID > /tmp/save.tar
```

##### 6.4 导入持久化container

删除container 2161509ff65e

导入export.tar文件

```
	[root@localhost /]# cat /tmp/export.tar | docker import - export:latest
	af19a55ff0745fb0a68655392d6d7653c29460d22d916814208bbb9626183aaa
	[root@localhost /]# docker images
	REPOSITORY              TAG                 IMAGE ID            CREATED             VIRTUAL SIZE
	export                  latest              af19a55ff074        34 seconds ago      270.3 MB
	chug/ubuntu12.10x64_2   latest              daa11948e23d        20 minutes ago      270.3 MB
	chug/ubuntu12.10x64     latest              0b96c14dafcd        4 months ago        270.3 MB
```

##### 6.5 导入持久化image

删除image daa11948e23d

导入save.tar文件

```
	[root@localhost /]# docker load < /tmp/save.tar
```

对image打tag
```
	[root@localhost /]# docker tag daa11948e23d load:tag
```

##### 6.6 export-import与save-load的区别

导出后再导入(export-import)的镜像会丢失所有的历史，而保存后再加载（save-load）的镜像没有丢失历史和层(layer)。这意味着使用导出后再导入的方式，你将无法回滚到之前的层(layer)，同时，使用保存后再加载的方式持久化整个镜像，就可以做到层回滚。（可以执行docker tag <LAYER ID> <IMAGE NAME>来回滚之前的层）。

##### 6.7 一些其它命令
```
	docker logs $CONTAINER_ID #查看docker实例运行日志，确保正常运行
	docker inspect $CONTAINER_ID #docker inspect <image|container> 查看image或container的底层信息

	docker build <path> 寻找path路径下名为的Dockerfile的配置文件，使用此配置生成新的image
	docker build -t repo[:tag] 同上，可以指定repo和可选的tag
	docker build - < <dockerfile> 使用指定的dockerfile配置文件，docker以stdin方式获取内容，使用此配置生成新的image
	docker port <container> <container port> 查看本地哪个端口映射到container的指定端口，其实用docker ps 也可以看到
```

#### 7 一些使用技巧

##### 7.1 docker文件存放目录

Docker实际上把所有东西都放到/var/lib/docker路径下了。
```
	[root@localhost docker]# ls -F
	containers/  devicemapper/  execdriver/  graph/  init/  linkgraph.db  repositories-devicemapper  volumes/
```

containers目录当然就是存放容器（container）了，graph目录存放镜像，文件层（file system layer）存放在graph/imageid/layer路径下，这样我们就可以看看文件层里到底有哪些东西，利用这种层级结构可以清楚的看到文件层是如何一层一层叠加起来的。

##### 7.2  查看root密码

docker容器启动时的root用户的密码是随机分配的。所以，通过这种方式就可以得到容器的root用户的密码了。
```
	docker logs 5817938c3f6e 2>&1 | grep 'User: ' | tail -n1
```

-------------------

http://www.tuicool.com/articles/7V7vYn

### Docker常用命令


#### 1. 查看docker信息（version、info）
```
	# 查看docker版本
	$docker version

	# 显示docker系统的信息
	$docker info
```

#### 2. 对image的操作（search、pull、images、rmi、history）
```
	# 检索image
	$docker search image_name

	# 下载image
	$docker pull image_name

	# 列出镜像列表; -a, --all=false Show all images; --no-trunc=false Don't truncate output; -q, --quiet=false Only show numeric IDs
	$docker images

	# 删除一个或者多个镜像; -f, --force=false Force; --no-prune=false Do not delete untagged parents
	$docker rmi image_name

	# 显示一个镜像的历史; --no-trunc=false Don't truncate output; -q, --quiet=false Only show numeric IDs
	$docker history image_name
```

#### 3. 启动容器（run）

docker容器可以理解为在沙盒中运行的进程。这个沙盒包含了该进程运行所必须的资源，包括文件系统、系统类库、shell 环境等等。但这个沙盒默认是不会运行任何程序的。你需要在沙盒中运行一个进程来启动某一个容器。这个进程是该容器的唯一进程，所以当该进程结束的时候，容器也会完全的停止。

```
	# 在容器中运行"echo"命令，输出"hello word"
	$docker run image_name echo "hello word"

	# 交互式进入容器中
	$docker run -i -t image_name /bin/bash


	# 在容器中安装新的程序
	$docker run image_name apt-get install -y app_name
```

Note：  在执行apt-get 命令的时候，要带上-y参数。如果不指定-y参数的话，apt-get命令会进入交互模式，需要用户输入命令来进行确认，但在docker环境中是无法响应这种交互的。apt-get 命令执行完毕之后，容器就会停止，但对容器的改动不会丢失。

#### 4. 查看容器（ps）
```
	# 列出当前所有正在运行的container
	$docker ps
	# 列出所有的container
	$docker ps -a
	# 列出最近一次启动的container
	$docker ps -l
```

#### 5. 保存对容器的修改（commit）

当你对某一个容器做了修改之后（通过在容器中运行某一个命令），可以把对容器的修改保存下来，这样下次可以从保存后的最新状态运行该容器。

```
	# 保存对容器的修改; -a, --author="" Author; -m, --message="" Commit message
	$docker commit ID new_image_name
```

Note：  image相当于类，container相当于实例，不过可以动态给实例安装新软件，然后把这个container用commit命令固化成一个image。

#### 6. 对容器的操作（rm、stop、start、kill、logs、diff、top、cp、restart、attach）
```
	# 删除所有容器
	$docker rm `docker ps -a -q`

	# 删除单个容器; -f, --force=false; -l, --link=false Remove the specified link and not the underlying container; -v, --volumes=false Remove the volumes associated to the container
	$docker rm Name/ID

	# 停止、启动、杀死一个容器
	$docker stop Name/ID
	$docker start Name/ID
	$docker kill Name/ID

	# 从一个容器中取日志; -f, --follow=false Follow log output; -t, --timestamps=false Show timestamps
	$docker logs Name/ID

	# 列出一个容器里面被改变的文件或者目录，list列表会显示出三种事件，A 增加的，D 删除的，C 被改变的
	$docker diff Name/ID

	# 显示一个运行的容器里面的进程信息
	$docker top Name/ID

	# 从容器里面拷贝文件/目录到本地一个路径
	$docker cp Name:/container_path to_path
	$docker cp ID:/container_path to_path

	# 重启一个正在运行的容器; -t, --time=10 Number of seconds to try to stop for before killing the container, Default=10
	$docker restart Name/ID

	# 附加到一个运行的容器上面; --no-stdin=false Do not attach stdin; --sig-proxy=true Proxify all received signal to the process
	$docker attach ID
```

Note： attach命令允许你查看或者影响一个运行的容器。你可以在同一时间attach同一个容器。你也可以从一个容器中脱离出来，是从CTRL-C。

#### 7. 保存和加载镜像（save、load）

当需要把一台机器上的镜像迁移到另一台机器的时候，需要保存镜像与加载镜像。

```
	# 保存镜像到一个tar包; -o, --output="" Write to an file
	$docker save image_name -o file_path
	# 加载一个tar包格式的镜像; -i, --input="" Read from a tar archive file
	$docker load -i file_path

	# 机器a
	$docker save image_name > /home/save.tar
	# 使用scp将save.tar拷到机器b上，然后：
	$docker load < /home/save.tar
```

#### 8、 登录registry server（login）

```
	# 登陆registry server; -e, --email="" Email; -p, --password="" Password; -u, --username="" Username
	$docker login
```

#### 9. 发布image（push）

```
	# 发布docker镜像
	$docker push new_image_name
```

#### 10.  根据Dockerfile 构建出一个容器

```
	#build
		  --no-cache=false Do not use cache when building the image
		  -q, --quiet=false Suppress the verbose output generated by the containers
		  --rm=true Remove intermediate containers after a successful build
		  -t, --tag="" Repository name (and optionally a tag) to be applied to the resulting image in case of success
	$docker build -t image_name Dockerfile_path
```


