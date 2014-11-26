---
layout: post
title: "GCC制作Library--shared部分相当不错"
date: 2014-11-06 14:49:00 +0800
comments: false
categories:
- 2014
- 2014~11
- compiler
- compiler~lib
tags:
---
[贴自http://blog.csdn.net/alex_ww/article/details/4544207](http://blog.csdn.net/alex_ww/article/details/4544207)
### Library可分成三种，static、shared与dynamically loaded。
#### 1. Static libraries
Static 链接库用于静态链接，简单讲是把一堆object檔用ar(archiver)包装集合起来，文件名以 `.a' 结尾。优点是执行效能通常会比后两者快，而且因为是静态链接，所以不易发生执行时找不到library或版本错置而无法执行的问题。缺点则是档案较大，维护度较低；例如library如果发现bug需要更新，那么就必须重新连结执行档。  
##### 1.1 编译
编译方式很简单，先例用 `-c' 编出 object 檔，再用 ar 包起来即可。
```
	____ hello.c ____
	#include
	void hello(){ printf("Hello "); }
	____ world.c ____
	#include
	void world(){ printf("world."); }
	____ mylib.h ____
	void hello();
	void world();
```
$ gcc -c hello.c world.c /\* 编出 hello.o 与 world.o \*/   
$ ar rcs libmylib.a hello.o world.o /\* 包成 limylib.a \*/   
这样就可以建出一个档名为 libmylib.a 的檔。输出的档名其实没有硬性规定，但如果想要配合 gcc 的 '-l' 参数来连结，一定要以 'lib' 开头，中间是你要的library名称，然后紧接着 '.a' 结尾。
##### 1.2 使用
```
	____ main.c ____
	#include "mylib.h"
	int main() {
	hello();
	world();
	}
```
使用上就像与一般的 object 档连结没有差别。  
$ gcc main.c libmylib.a  
也可以配合 gcc 的 `-l' 参数使用  
$ gcc main.c -L. -lmylib  
'-Ldir' 参数用来指定要搜寻链接库的目录，'.' 表示搜寻现在所在的目录。通常默认会搜 /usr/lib 或 /lib 等目录。  
'-llibrary' 参数用来指定要连结的链接库，'mylib' 表示要与mylib进行连结，他会搜寻library名称前加'lib'后接'.a'的档案来连结。  
$ ./a.out  
Hello world.  

### 2. Shared libraries
Shared library 会在程序执行起始时才被自动加载。因为链接库与执行档是分离的，所以维护弹性较好。有两点要注意，shared library是在程序起始时就要被加载，而不是执行中用到才加载，而且在连结阶段需要有该链接库才能进行连结。  
首先有一些名词要弄懂，soname、real name与linker name。  
soname 用来表示是一个特定 library 的名称，像是 libmylib.so.1 。前面以 'lib' 开头，接着是该 library 的名称，然后是 '.so' ，接着是版号，用来表名他的界面；如果接口改变时，就会增加版号来维护兼容度。  
real name 是实际放有library程序的文件名，后面会再加上 minor 版号与release 版号，像是 libmylib.so.1.0.0 。  
一般来说，版号的改变规则是(印象中在 APress-Difinitive Guide to GCC中有提到，但目前手边没这本书)，最后缀的release版号用于程序内容的修正，接口完全没有改变。中间的minor用于有新增加接口，但相旧接口没改变，所以与旧版本兼容。最前面的version版号用于原接口有移除或改变，与旧版不兼容时。  
linker name是用于连结时的名称，是不含版号的 soname ，如: libmylib.so。  
通常 linker name与 real name是用 ln 指到对应的 real name ，用来提供弹性与维护性。  
##### 2.1 编译
shared library的制作过程较复杂。  
$ gcc -c -fPIC hello.c world.c  
编译时要加上 -fPIC 用来产生 position-independent code。也可以用 -fpic参数。 (不太清楚差异，只知道 -fPIC 较通用于不同平台，但产生的code较大，而且编译速度较慢)。  
$ gcc -shared -Wl,-soname,libmylib.so.1 -o libmylib.so.1.0.0 /  
hello.o world.o  
-shared 表示要编译成 shared library  
-Wl 用于参递参数给linker，因此-soname与libmylib.so.1会被传给linker处理。  
-soname用来指名 soname 为 limylib.so.1  
library会被输出成libmylib.so.1.0.0 (也就是real name)  
若不指定 soname 的话，在编译结连后的执行档会以连时的library档名为soname，并载入他。否则是载入soname指定的library档案。  
可以利用 objdump 来看 library 的 soname。  
$ objdump -p libmylib.so | grep SONAME  
SONAME libmylib.so.1  
若不指名-soname参数的话，则library不会有这个字段数据。  
在编译后再用 ln 来建立 soname 与 linker name 两个档案。  
$ ln -s libmylib.so.1.0.0 libmylib.so  
$ ln -s libmylib.so.1.0.0 libmylib.so.1  

##### 2.2 使用  
与使用 static library 同。  
$ gcc main.c libmylib.so  
以上直接指定与 libmylib.so 连结。  
或用  
$ gcc main.c -L. -lmylib  
linker会搜寻 libmylib.so 来进行连结。  
如果目录下同时有static与shared library的话，会以shared为主。  
使用 -static 参数可以避免使用shared连结。  
$ gcc main.c -static -L. -lmylib  
此时可以用 ldd 看编译出的执行档与shared链接库的相依性  
$ldd a.out  
linux-gate.so.1 => (0xffffe000)  
libmylib.so.1 => not found  
libc.so.6 => /lib/libc.so.6 (0xb7dd6000)  
/lib/ld-linux.so.2 (0xb7f07000)  
输出结果显示出该执行文件需要 libmylib.so.1 这个shared library。  
会显示 not found 因为没指定该library所在的目录，所找不到该library。  
因为编译时有指定-soname参数为 libmylib.so.1 的关系，所以该执行档会加载libmylib.so.1。否则以libmylib.so连结，执行档则会变成要求加载libmylib.so
$ ./a.out  
./a.out: error while loading shared libraries: libmylib.so.1:  
cannot open shared object file: No such file or directory  
因为找不到 libmylib.so.1 所以无法执行程序。  
有几个方式可以处理。  
a. 把 libmylib.so.1 安装到系统的library目录，如/usr/lib下  
b. 设定 /etc/ld.so.conf ，加入一个新的library搜寻目录，并执行ldconfig  
更新快取  
c. 设定 LD_LIBRARY_PATH 环境变量来搜寻library  
这个例子是加入当前目录来搜寻要载作的library  
$ LD_LIBRARY_PATH=. ./a.out  
Hello world.  
#### 3. Dynamically loaded libraries
Dynamicaaly loaded libraries 才是像 windows 所用的 DLL ，在使用到  
时才加载，编译连结时不需要相关的library。动态载入库常被用于像plug-ins的应用。  
##### 3.1 使用方式
动态加载是透过一套 dl function来处理。  
	#include <dlfcn.h>  
	void \*dlopen(const char \*filename, int flag);  
开启加载 filename 指定的 library。  
	void \*dlsym(void \*handle, const char \*symbol);  
取得 symbol 指定的symbol name在library被加载的内存地址。  
	int dlclose(void \*handle);  
关闭dlopen开启的handle。  
	char \*dlerror(void);  
传回最近所发生的错误讯息。
```
	____ dltest.c ____
	#include <stdio.h>
	#include <stdlib.h>
	#include <stddef.h>
	#include <dlfcn.h>
	int main() {
	void *handle;
	void (*f)();
	char *error;
	/* 开启之前所撰写的 libmylib.so 链接库 */
	handle = dlopen("./libmylib.so", RTLD_LAZY);
	if( !handle ) {
	fputs( dlerror(), stderr);
	exit(1);
	}
	/* 取得 hello function 的 address */
	f = dlsym(handle, "hello");
	if(( error=dlerror())!=NULL) {
	fputs(error, stderr);
	exit(1);
	}
	/* 呼叫该 function */
	f();
	dlclose(handle);
	}
```
编译时要加上 -ldl 参数来与 dl library 连结  
$ gcc dltest.c -ldl  
结果会印出 Hello 字符串  
$ ./a.out  
Hello  
关于dl的详细内容请参阅 man dlopen
