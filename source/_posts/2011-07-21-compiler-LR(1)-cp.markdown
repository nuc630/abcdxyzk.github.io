---
layout: post
title: "构造LR(1)项目集，生成LR(1)分析表、进行相应的语法分析 "
date: 2011-07-21 16:43:00 +0800
comments: false
categories:
- 2011
- 2011~07
- compiler
- compiler~base
tags:
---
[贴自这里](blog.csdn.net/freeagle5/article/details/1675965)

```
引言...........................................................  2
第一章	概述...................................................  3
	1.1设计内容............................................  3
	1.2设计要求............................................  3
第二章	设计的基本原理.........................................  3
	2.1 CLOSURE(I)的构造...................................  3
	2.2 GO(I,X)的构造......................................  3
	2.3 FIRST集合的构造....................................  3
	2.4 LR（1）分析表的构造........................ .......  3
第三章	程序设计..............................................  4
	3.1总体方案设计........................................  4
	3.2各模块设计...........................................  5
		3.2.1读入模块：Read_G().........................  5
		3.2.2 计算FIRST模块：get_first() ..............  5
		3.2.3 判断项目数否在项目集里：is_in(proj temp,int T)...  5
		3.2.4 获得计算closure(I)时需要的First(βa)：gete_expc(proj temp)...  5
		3.2.5 项目集的CLOSURE计算：e_closure(int T) .... 5
		3.2.6 检查项目集是否已经在项目集族里：is_contained()... 6
		3.2.7 GO()函数的实现：go(). ..................  6
		3.2.8 LR(1)分析表的构造：get_action().........  6
		3.2.9　对输入串的语法分析：在main()中实现 ..... 6
第四章	程序测试............................................... 6
	4.1 课本115页文法的LR(1) 分析器的构造和语法分析.......... 6
	4.2 表达式文法的LR(1)分析器的构造和语法分析.............. 7
第五章	结论.................................................... 9
参考文献........................................................ 9
附录	程序清单................................................ 10
```


### 引言
《编译原理》是计算机专业的一门重要的专业课程，其中包含大量软件设计思想。通过课程设计，实现一些重要的算法，或设计一个完整的编译程序模型，能够进一步加深理解和掌握所学知识，对提高自己的软件设计水平具有十分重要的意义。

  我选择的是老师给的第31题，并予以扩充。即对任意给定的文法G构造LR(1)项目集规范族，其中要实现CLOSURE(I)、GO(I,X)、FIRST集合等。在此基础上，构造了LR（1）分析表。然后对输入的句子进行语法分析，给出接受或出错报告。程序采用文件输入输出方式。其中包括两个输入文件：文法grammar.txt，以及输入串input.txt；两个输出文件：项目集items.txt和文法的LR(1)分析表action_table.txt。由于语法分析的结果只给出接受或错误报告，比较简单。所以直接在屏幕上输出，也便于用户查看。

  在具体编写程序过程中，对文法操作的各个功能模块独立成为一个子程序，而对具体输入串的分析则放在main()函数中进行。各个变量及函数的意义和用法我将在叙述程序设计的总体方案中详细给出。

  程序的总体算法思想来自《编译原理》课程。具体实现由我独立完成。程序用C/C++语言编写。在Microsoft Visual C++ 2005环境下调试通过。

### 第一章	概述

##### 1.1 设计内容
对任意给定的上下文无关文法G，构造其LR（1）项目集族，并且在此基础上进一步构造其LR（1）分析表。然后分析输入的“句子”。
##### 1.2 设计要求
对输入的文法G（要求是上下文无关文法）,在程序中实现CLOSURE(I)、GO(I,X)、FIRST等的构造，并利用这些功能函数构造出LR(1)项目集族。并且输出结果。在此基础上构造出G的LR(1)分析表（这个表也输出给用户），并对输入的“句子”进行语法分析，给出分析结果。


### 第二章	设计的基本原理

##### 2.1 CLOSURE(I)的构造
  CLOSURE(I)表示和I中项目可以识别同样活前缀的所有项目的集合。它可以由以下方法得到：  
⑴ I中的所有项目都属于CLOSURE(I)；  
⑵ 若项目[A→α·Bβ,a]属于CLOSURE(I)，B→ξ是一个产生式，那么，对于FIRST（βa）中的每一个终结符b，如果[B→·ξ，b]原来不在CLOSURE(I)中，则把它加进去；  
⑶ 重复执行步骤⑵，直到CLOSURE(I)不再增大为止。  

##### 2.2 GO(I,X)的构造
  GO(I,X) = CLOSURE(J)  
其中 J={任何形如[A→αX·β,a]的项目|[A→α·Xβ,a]属于I}

##### 2.3 FIRST集合的构造
  在这个程序中使用的是FIRST（βa），这基于每一个非终结符的FIRST集合（终结符的FIRST就是它本身）。所以需要对每一个非终结符构造其FIRST集合。方法如下：  
  连续使用下面的规则，直到每个集合FIRST不再增大为止。  
⑴ 若X属于VT，则FIRST（X）= {X}。  
⑵ 若X属于VN，且有产生式X→a…，则把a加入到FIRST（X）中；若X→ε也是一条产生式，则把ε也加入到FIRST（X）中。  
⑶　若X→Y…是一个产生式且Y属于VN，则把FIRST（Y）中的所有非ε元素都加入到FIRST（X）中；若X→Y1Y2…Yk是一个产生式，Y1，…,Yｉ－１都是非终结符，而且，对于任何j,１<= j <= i-1，FIRST(YJ)都含有ε（即Y1…Yｉ－１=­­­>ε）,则把FIRST(Yi)中的所有非ε元素都加入到FIRST(X)中；特别的，若所有的FIRST(YJ)都含有ε,j=1,2,3...k,则把ε加入到FIRST(X)中。  

##### 2.4 LR（1）分析表的构造
  在实现GO(I,X)时，记录下状态的转化。得到分析表中的移进部分。然后，再扫描所有的项目集，找到其中包含归约项目的那些项目集，根据其中的项目，得到分析表中那些归约的部分。


### 第三章	程序设计
#### 3.1总体方案设计
  在main()函数中读入文法。并对文法进行扩展，同时记录下文法的所有终结符和非终结符。对每一个非终结符计算它的FIRST集合。以备在计算CLOSURE(I)时使用。然后，调用GO（）函数。完成LR（1）项目集族的计算。计算的结果记录到items.txt中。并且记录下状态之间的转换关系。接下来，调用get_action()根据上面的项目集族和记录的状态转换数组获得LR（1）分析表。然后就可以对输入的句子进行语法检查。程序中主要变量以及函数的说明如下：
```
char G[20][20];					存放输入的文法；为简单起见，设文法的产生式条数不  多于20条，每个产生式不多与20个字符，用@表示ε，且产生式输入的时候要以$结束
int  length[20];				每条产生式的长度
int  number = 0;				产生式的条数
bool tempofinput[150];			记录哪些ASCII字符在文法中，以求得所有的VN和VT
char str_vn[20];				记录所有的非终结符
int  size_vn = 0;				记录非终结符的个数
char str_vt[150];				记录所有的终结符
int  size_vt = 0;				记录终结符的个数
bool first_vn[30][150];			记录每个非终结符的first集合
char buffer[50];				用来存放CLOSURE(I)时需要的first_set 也用来读入用户的输入串
int  bsize = 0;					buffer的有效长度
struct thri{
	int  beg;
	int  nex;
	char ch;
};								定义状态转换数组中的元素格式
thri trans[200];				用来在GO（）函数中记录状态间的转换
int  size_trans = 0;			trans数组的大小
struct proj{
	int formula_numb;
	int part;
	char expc;
};								定义项目集的格式
proj items[100][100];			项目集数组，假设项目集的个数不超过100个，且每个项目集中的项目个数不超过100个
int  Ccount = 0;				项目集的个数
int  size_item[100];			每个项目集中项目的个数
struct action{
	char  ch;
	int   nxt_sta;
};								定义状态转换表的格式
action	action_table[100][100];	状态转换表
int	size_act_table[100];		状态转换表的大小
ifstream G_ifile;				输入文法的文件指针
ifstream input_ifile;			输入句子的文件指针
ofstream items_ofile;			输出项目集族的文件指针
ofstream act_ofile;				输出转换表的文件指针
void Read_G()					读入文法的子程序模块
void get_first()				计算每一个非终结符的first集合
bool is_in(proj temp,int T)		判断项目temp是否已经在项目集族items[T]中
void gete_expc(proj temp)		计算在生成CLOSURE(I)时用到的FIRST（βa）
void e_closure(int T)			计算items[T]的closure闭包
int is_contained()				判断新生成的项目集是否已经在项目集族中
void go()						实现GO（I，X）的功能
void get_action()				生成LR(1)表
int main()						调用各个字模块，并在其中对输入串进行语法分析
```
#### 3.2各模块设计
##### 3.2.1 读入模块：Read_G()
  文法要为上下文无关文法。输入文件的格式为：首先输入产生式的条数；每条产生式的第一个字符为非终结符。以$结尾。输入的同时用tempofinput[temp] = true来记录字符temp。为统计有哪些非终结符和终结符作准备。这些都通过ASCLL码对应位是否为true来判断。

##### 3.2.2 计算FIRST模块：get_first()
  先设置flag1表示本轮扫描first_vn中有没有新增加的内容。要是有，还要进行下一次扫描。每一轮扫描所有的产生式，在扫描每一个产生式的时候，设置一个下标指针t用来保证不会扫过本产生式，还设置flag2表示t的位置是否是一个可以推导出ε的非终结符。是的话，还要进行下一个t位置的检查。如果t走到产生式的最后位置的下一个位置，则表明ε属于此产生式左边非终结符的FIRST集合；
##### 3.2.3 判断项目数否在项目集里：is_in(proj temp,int T)
  Scan项目集原有的每一个项目，和新生成的项目作比较。若有相同的就返回true,否则返回false

##### 3.2.4 获得计算closure(I)时需要的First(βa)：gete_expc(proj temp)
  设置flag表示是否还要进行下一轮计算（即此次处理的为非终结符且它的FIRST中有ε），若处理的位置已经超过了产生式的长度，则直接把项目中的那个搜索字符添加进去。这个模块的返回结果放在buffer数组中。

##### 3.2.5 项目集的CLOSURE计算：e_closure(int T)
  在Go()函数中会生成items[T]的一些基本项目。对items[T]中已经有的每一个项目检查在”·”之后的是否为非终结符；若是，则计算FIRST（βa），把每一个buffer中的元素和相应的产生式构成一个项目，加入到项目集中。（注意，此时的项目集的大小是随着项目的不断加入而变大的，所以可以用for循环保证项目集中不会有遗漏。）

##### 3.2.6 检查项目集是否已经在项目集族里：is_contained()
  把已经有的项目集和新生成的项目集进行比较，要是有相等的话则表示已经存在相同的项目集合，此时返回相同的那个项目集的编号。否则，返回0。

##### 3.2.7 GO()函数的实现：go()
  第一步制作一个初始项目（即拓展文法的第一条产生式），然后用e_closure构造项目集0。在程序中Ccount 作为项目集的计数从0开始到n(包括n)，所以在for循环中是<= Ccount。即扫描每一个项目集，对每一个项目在”·”之后的终结符，向后移动一位“·”的位置生成新的项目，暂存在buf数组中。然后，预生成项目集，并且求其CLOSURE，再判断新的项目集是否已经存在，若存在了，就撤销这个项目集，并设置相应的trans。否则就生成新的项目集，也设置相应的trans。在以上过程中，每次确定生成一个项目集的时候都把它输出到items.txt中。

##### 3.2.8 LR(1)分析表的构造：get_action()
  Scan每一个项目集，若其中有规约项目，则转换表增加一个归约项（用负值表示）。然后，根据trans数组中的元素，构造转换表中的移进项（用正值表示）。
接受项目也是一个归约项，用0表示。生成的转换表输出到action_table.txt中。

##### 3.2.9　对输入串的语法分析：在main()中实现
  用stack模拟语法分析的过程，先在stack中放入（０，＃），然后，用当前栈顶状态和当前输入字符查找action_table。根据action_table中的值的情况做相应处理（即执行移进和归约动作）。若遇到接受项目则给出接受提示，程序结束。若遇到出错的情况给出出错提示，也结束程序。

### 第四章	程序测试
本程序在Dev-C++和Microsoft Visual C++ 2005中调试通过。下面给出两个调试实例：

#### 4.1 课本115页文法的LR(1) 分析器的构造和语法分析
输入文法：
```
3	EBB$	BaB$	Bb$
```
生成的项目集族：
```
I0:
0 , 1 , #
1 , 1 , #
2 , 1 , a
2 , 1 , b
3 , 1 , a
3 , 1 , b
I5:
2 , 3 , a
2 , 3 , b
I2:
3 , 2 , a
3 , 2 , b
I7:
3 , 2 , #
I4:
0 , 2 , #
I9:
2 , 3 , #
I3:
1 , 2 , #
2 , 1 , #
3 , 1 , #
I8:
1 , 3 , #
I1:
2 , 2 , a
2 , 2 , b
2 , 1 , a
3 , 1 , a
2 , 1 , b
3 , 1 , b
I6:
2 , 2 , #
2 , 1 , #
3 , 1 , #
```
生成的转换表：
```
(0,a,1) (0,b,2)　(0,B,3)　(0,E,4)　(1,a,1)　(1,b,2)　(1,B,5)
(2,a,-3)　(2,b,-3)　(3,a,6)　(3,b,7)　(3,B,8)　(4,#,0)　(5,a,-2)
(5,b,-2)　(6,a,6)　(6,b,7)　(6,B,9)　(7,#,-3)　(8,#,-1)
```
输入句子测试：  
输入句子：aaaabab#  
输出截图：  
输入句子：abbab#  
输出截图：  

#### 4.2 表达式文法的LR(1)分析器的构造和语法分析
输入文法：
```
6	EE+T$	ET$	TT*F$	TF$	F(E)$	Fi$
```
生成的项目集族：
```
I0:
0 , 1 , #
1 , 1 , #
2 , 1 , #
1 , 1 , +
2 , 1 , +
3 , 1 , #
4 , 1 , #
3 , 1 , +
4 , 1 , +
3 , 1 , *
4 , 1 , *
5 , 1 , #
6 , 1 , #
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I1:
5 , 2 , #
5 , 2 , +
5 , 2 , *
1 , 1 , )
2 , 1 , )
1 , 1 , +
2 , 1 , +
3 , 1 , )
4 , 1 , )
3 , 1 , +
4 , 1 , +
3 , 1 , *
4 , 1 , *
5 , 1 , )
6 , 1 , )
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I2:
6 , 2 , #
6 , 2 , +
6 , 2 , *
I3:
0 , 2 , #
1 , 2 , #
1 , 2 , +
I4:
4 , 2 , #
4 , 2 , +
4 , 2 , *
I7:
6 , 2 , )
6 , 2 , +
6 , 2 , *
I6:
5 , 2 , )
5 , 2 , +
5 , 2 , *
1 , 1 , )
2 , 1 , )
1 , 1 , +
2 , 1 , +
3 , 1 , )
4 , 1 , )
3 , 1 , +
4 , 1 , +
3 , 1 , *
4 , 1 , *
5 , 1 , )
6 , 1 , )
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I5:
2 , 2 , #
2 , 2 , +
3 , 2 , #
3 , 2 , +
3 , 2 , *
I10:
2 , 2 , )
2 , 2 , +
3 , 2 , )
3 , 2 , +
3 , 2 , *
I8:
5 , 3 , #
5 , 3 , +
5 , 3 , *
1 , 2 , )
1 , 2 , +
I9:
4 , 2 , )
4 , 2 , +
4 , 2 , *
I11:
1 , 3 , #
1 , 3 , +
3 , 1 , #
4 , 1 , #
3 , 1 , +
4 , 1 , +
3 , 1 , *
4 , 1 , *
5 , 1 , #
6 , 1 , #
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I12:
3 , 3 , #
3 , 3 , +
3 , 3 , *
5 , 1 , #
6 , 1 , #
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I14:
5 , 4 , #
5 , 4 , +
5 , 4 , *
I13:
5 , 3 , )
5 , 3 , +
5 , 3 , *
1 , 2 , )
1 , 2 , +
I15:
1 , 3 , )
1 , 3 , +
3 , 1 , )
4 , 1 , )
3 , 1 , +
4 , 1 , +
3 , 1 , *
4 , 1 , *
5 , 1 , )
6 , 1 , )
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I16:
3 , 3 , )
3 , 3 , +
3 , 3 , *
5 , 1 , )
6 , 1 , )
5 , 1 , +
6 , 1 , +
5 , 1 , *
6 , 1 , *
I17:
1 , 4 , #
1 , 4 , +
3 , 2 , #
3 , 2 , +
3 , 2 , *
I18:
3 , 4 , #
3 , 4 , +
3 , 4 , *
I19:
5 , 4 , )
5 , 4 , +
5 , 4 , *
I20:
1 , 4 , )
1 , 4 , +
3 , 2 , )
3 , 2 , +
3 , 2 , *
I21:
3 , 4 , )
3 , 4 , +
3 , 4 , *
```
生成的转换表：
```
(0,(,1)　(0,i,2)　(0,E,3)　(0,F,4)　(0,T,5)　(1,(,6)　(1,i,7)　(1,E,8)
(1,F,9)　(1,T,10) (2,#,-6)　(2,+,-6)　(2,*,-6)　(3,#,0)　(3,+,11)
(4,#,-4)　(4,+,-4)　(4,*,-4)　(5,#,-2)　(5,+,-2)　(5,*,12)　(6,(,6)
(6,i,7)　(6,E,13)　(6,F,9)　(6,T,10)　(7,),-6)　(7,+,-6)　(7,*,-6)
(8,),14)　(8,+,15)　(9,),-4)　(9,+,-4)　(9,*,-4)　(10,),-2)　(10,+,-2)
(10,*,16)　(11,(,1)　(11,i,2)　(11,F,4)　(11,T,17)　(12,(,1)　(12,i,2)
(12,F,18)　(13,),19)　(13,+,15)　(14,#,-5)　(14,+,-5)　(14,*,-5)
(15,(,6)　(15,i,7)　(15,F,9)　(15,T,20)　(16,(,6)　(16,i,7)　(16,F,21)
(17,#,-1)　(17,+,-1)　(17,*,12)　(18,#,-3)　(18,+,-3)　(18,*,-3)
(19,),-5)　(19,+,-5)　(19,*,-5)　(20,),-1)　(20,+,-1)　(20,*,16)
```
输入句子测试：  
输入句子：i+i+*#  
输出截图  
输入句子：(i)+i*i#  
输出截图  

### 第五章	结论
  通过以上章节的分析与说明，可以看到，本程序在功能上完全实现了课程设计的要求。并且扩展了一些功能。即对任意给定的上下文无关文法都可以构造出相应的LR(1) 项目集族和LR(1)分析表。并且允许用户使用生成的LR(1)分析表对具体的句子进行分析。

  到这里，这次的编译原理课程设计基本上已经完成了，我选择的这道题目较其他的选题有一定的难度。但是，我在克服这些难关的过程中获得了更多的是快乐和信心。同时，通过亲手构造一个简单的LR(1)分析器，我对LR(1)分析方法也有了更深一步的认识和掌握。


### 参考文献：
1.	陈火旺　刘春林等	《程序设计语言编译原理》（第三版）国防工业出版社，2000  
2.	陈意云　张昱		《编译原理》　高等教育出版社 2003  
3.	陈意云　张昱		《编译原理习题精选与解析》高等教育出版社 2003





### 附录	程序清单：
```
/*
	Name: LR(1)分析器的构造
	Author: wangrui
	Date: 07-06-07
　Description:对任意给定的文法G构造LR(1)项目集规范族和分析表,并对输入的　　　句子进行语法分析
*/
#include"iostream"
#include"fstream"
#include"stack"
#include"utility"
using namespace std;

char G[20][20];		//use a matrix to store grammar G
int	length[20];	//length use to store each formula's length
int	number = 0;
bool tempofinput[150];	//buffer of input
char str_vn[20];	//put all vn into it
int	size_vn = 0;
char str_vt[150];	//put all vt into it
int	size_vt = 0;
bool first_vn[30][150];
char buffer[50];	//用来存放生成CLOSURE(I)时需要的first_set 也用来读入用户的输入串^_^
int	bsize = 0;
struct thri{
	int beg;
	int nex;
	char ch;
};
thri trans[200];
int	size_trans = 0;

//定义项目集的形式
struct proj{
	int formula_numb;
	int part;
	char expc;
};
/*项目集*/
proj	items[100][100];
int	Ccount = 0;
int	size_item[100];

/*状态转换表*/
struct action{
	char	ch;
	int	nxt_sta;
};
action	action_table[100][100];
int		size_act_table[100];

ifstream	G_ifile;
ifstream	input_ifile;
ofstream	items_ofile;
ofstream	act_ofile;

void Read_G()
{
	G_ifile >> number;	//user should give the number of formula first
	for(int i = 1; i <= number; i++){
		char temp;
		int j = 0;
		G_ifile >> temp;
		while(temp != '$'){
			tempofinput[temp] = true;
			G[i][j++] = temp;
			G_ifile >> temp;
		}
		length[i] = j;
	}

	G[0][0] = 'S';
	G[0][1] = G[1][0];
	length[0] = 2;

	for(int i = 0; i < 64; i++)
		if(tempofinput[i])
			str_vt[size_vt++] = i;
	for(int i = 91; i < 128; i++)
		if(tempofinput[i])
			str_vt[size_vt++] = i;
	for(int i = 65; i < 91; i++)
		if(tempofinput[i])
			str_vn[size_vn++] = i;
}

void get_first(){
	bool flag1;
	do{
		flag1 = false;
		for(int i = 1; i <= number; i++){
			int t = 1;
			bool flag2;
			do{
				flag2 = false;
				if (G[i][t] >= 'A' && G[i][t] <= 'Z'){
					for(int k = 0; k < 64; k++)
						if(first_vn[G[i][t]-'A'][k]==true&& !first_vn[G[i][0]-'A'][k]){
							first_vn[G[i][0]-'A'][k] = true;
							flag1 = true;
						}
						for(int k = 91; k < 128; k++)
						if(first_vn[G[i][t]-'A'][k]==true&& !first_vn[G[i][0]-'A'][k]){
							first_vn[G[i][0]-'A'][k] = true;
							flag1 = true;
						}
						if(first_vn[G[i][t]-'A'][64] == true){
							t++;
							flag2 = true;
						}
				}
				else if(!first_vn[G[i][0]-'A'][ G[i][t] ]){
						first_vn[G[i][0]-'A'][ G[i][t] ] = true;
						flag1 = true;
				}
			}while(flag2 && t < length[i]);
			if(t == length[i])
				first_vn[G[i][0]-'A'][26] = true;
		}
	}while(flag1);
}
/*判断项目数否在项目集里*/
bool is_in(proj temp,int T){
	for(int i = 0; i < size_item[T]; i++)
		if(temp.formula_numb == items[T][i].formula_numb && temp.part == items[T][i].part && temp.expc == items[T][i].expc)
				return true;
	return false;
}

void	gete_expc(proj temp){
	bsize = 0;
	bool flag;
	int tt = temp.part;
	do{
		flag = false;
		if(tt+1 >= length[temp.formula_numb]){
			buffer[bsize++] = temp.expc;
			return;
		}
		else if(G[temp.formula_numb][tt+1] < 'A' || G[temp.formula_numb][tt+1] > 'Z'){
			buffer[bsize++] = G[temp.formula_numb][tt+1];
			return;
		}
		else if(G[temp.formula_numb][tt+1] >= 'A' && G[temp.formula_numb][tt+1] <= 'Z'){
			for(int i = 0; i < 64; i++){
				if(first_vn[ G[temp.formula_numb][tt+1]-'A' ][i])
					buffer[bsize++] = i;
			}
			for(int i = 91; i < 128; i++){
				if(first_vn[ G[temp.formula_numb][tt+1]-'A' ][i])
					buffer[bsize++] = i;
			}
			if(first_vn[ G[temp.formula_numb][tt+1]-'A' ][64]){
				tt++;
				flag = true;
			}
		}
	}while(flag);
}

void e_closure(int T){
	for(int i = 0; i < size_item[T]; i++){
		proj temp;
		if(G[items[T][i].formula_numb][items[T][i].part] >= 'A' && G[items[T][i].formula_numb][items[T][i].part] <= 'Z'){
			for(int j = 0; j < 20; j++)
				if(G[j][0] == G[items[T][i].formula_numb][items[T][i].part]){
					gete_expc(items[T][i]);
					for(int k = 0; k < bsize; k++){
						temp.formula_numb = j;
						temp.part = 1;
						temp.expc = buffer[k];
						if(!is_in(temp,T))
							items[T][size_item[T]++] = temp;
					}
					bsize = 0;
				}
		}
	}
	return ;
}

int is_contained()
{
	for(int i = 0; i < Ccount; i++){
		int s = 0;		//记录有多少是匹配的
		if(size_item[i] == size_item[Ccount])
			for(int j = 0; j < size_item[Ccount]; j++){
				for(int k = 0; k < size_item[i]; k++)
					if((items[Ccount][j].formula_numb==items[i][k].formula_numb)&&(items[Ccount][j].part == items[i][k].part) && (items[Ccount][j].expc == items[i][k].expc)){
						s++;
						break;
					}
			}
		if(s == size_item[Ccount])
			return i;
	}
	return 0;
}

void go(){
	proj init;
	init.expc = '#';
	init.formula_numb = 0;
	init.part = 1;
	items[0][0] = init;
	size_item[0]++;

	e_closure(0);
	items_ofile << "I0:" << endl;
	for(int i = 0; i < size_item[0]; i++)
			items_ofile << items[0][i].formula_numb << " , " << items[0][i].part << " , " << items[0][i].expc << endl;
	items_ofile << "***************************************" << endl;

	for(int index = 0; index <= Ccount ; index++){
		for(int j = 0; j < size_vt; j++){
			proj	buf[50];
			int	buf_size = 0;
			proj	tp;
			for(int p = 0; p < size_item[index]; p++){
				if((items[index][p].part<length[items[index][p].formula_numb])&&( G[ items[index][p].formula_numb ][ items[index][p].part ] == str_vt[j]) ){
					tp.formula_numb = items[index][p].formula_numb;
					tp.expc = items[index][p].expc;
					tp.part = items[index][p].part+1;
					buf[buf_size++] = tp;
				}
			}
			if(buf_size	!= 0){
				Ccount++;
				for(int t = 0; t < buf_size; t++){
					items[Ccount][ size_item[Ccount]++ ] = buf[t];
				}
				e_closure(Ccount);
				int	next_state = is_contained();		//看生成的项目集是否已经在项目集族中了
				if(next_state != 0){
					size_item[Ccount] = 0;
					Ccount--;
					trans[size_trans].beg = index;
					trans[size_trans].nex = next_state;
					trans[size_trans].ch = str_vt[j];
					size_trans++;
				}
				else{
					items_ofile << "I" << Ccount << ":" << endl;
					for(int i = 0; i < size_item[Ccount]; i++)
						items_ofile << items[Ccount][i].formula_numb << " , " << items[Ccount][i].part << " , " << items[Ccount][i].expc << endl;
					items_ofile << "***************************************" << endl;
					trans[size_trans].beg = index;
					trans[size_trans].nex = Ccount;
					trans[size_trans].ch = str_vt[j];
					size_trans++;
				}
			}
		}	//对文法的每一个终结符

		for(int j = 0; j < size_vn; j++){
			proj	buf[50];
			int	buf_size = 0;
			proj	tp;
			for(int p = 0; p < size_item[index]; p++){
				if((items[index][p].part<length[items[index][p].formula_numb])&&( G[ items[index][p].formula_numb ][ items[index][p].part ] == str_vn[j]) ){
					tp.formula_numb = items[index][p].formula_numb;
					tp.expc = items[index][p].expc;
					tp.part = items[index][p].part+1;
					buf[buf_size++] = tp;
				}
			}
			if(buf_size	!= 0){
				Ccount++;
				for(int t = 0; t < buf_size; t++){
					items[Ccount][ size_item[Ccount]++ ] = buf[t];
				}
				e_closure(Ccount);
				int	next_state = is_contained();	//看生成的项目集是否已经在项目集族中了

				if(next_state != 0){
					size_item[Ccount] = 0;
					Ccount--;
					trans[size_trans].beg = index;
					trans[size_trans].nex = next_state;
					trans[size_trans].ch = str_vn[j];
					size_trans++;
				}
				else{
					items_ofile << "I" << Ccount << ":" << endl;
					for(int i = 0; i < size_item[Ccount]; i++)
						items_ofile << items[Ccount][i].formula_numb << " , " << items[Ccount][i].part << " , " << items[Ccount][i].expc << endl;
					items_ofile << "***************************************" << endl;
					trans[size_trans].beg = index;
					trans[size_trans].nex = Ccount;
					trans[size_trans].ch = str_vn[j];
					size_trans++;
				}
			}
		}	//对文法的每一个非终结符
	}
}
//get action table based on item set and trans array
void get_action(){
	for(int i = 0; i < 100; i++)
		size_act_table[i] = 0;

	for(int i = 0; i <= Ccount; i++)		//*************	i must <= Ccount !!!!!!!!!!!!!! ***********
		for(int j = 0; j < size_item[i]; j++)
			if(items[i][j].part == length[ items[i][j].formula_numb ] ){
				action_table[i][ size_act_table[i] ].ch = items[i][j].expc;
				action_table[i][ size_act_table[i]++ ].nxt_sta = items[i][j].formula_numb*(-1);
			}
	for(int i = 0; i < size_trans; i++){
		int	t1 = trans[i].beg;
		int	t2 = trans[i].nex;
		char	tp = trans[i].ch;
		action_table[t1][ size_act_table[t1] ].ch = tp;
		action_table[t1][ size_act_table[t1]++ ].nxt_sta = t2;
	}
}

int main(){
	for(int i = 0; i< 150; i++)
		tempofinput[i] = false;
	for(int i= 0; i < 100; i++)
		size_item[i] = 0;
	for(int i = 0; i < 30; i++)
		for(int j = 0; j < 150; j++)
				first_vn[i][j] = false;

	G_ifile.open("d://grammar.txt");
	input_ifile.open("d://input.txt");
	items_ofile.open("d://items.txt");
	act_ofile.open("d://action_table.txt");

	Read_G();		//read G and put the number of formula into count
	get_first();	//each vn's first_set
	go();
	get_action();
	for(int i = 0; i < Ccount; i++)
		for(int j = 0; j < size_act_table[i]; j++){
			char	tp = action_table[i][j].ch;
			int	t	= action_table[i][j].nxt_sta;
			act_ofile << "(" << i << "," << tp << "," << t << ")" << endl;
		}

	bsize = 0;
	do{
		input_ifile >> buffer[bsize];
	}while(buffer[ bsize++ ] != '#');
	stack<pair<int,char> > s;	//语法检查栈
	int	work_sta = 0;
	int	index_buf = 0;
	bool	err;
	bool	done = false;
	s.push(make_pair(0,'#'));
	do{
		work_sta = s.top().first;
		err =	true;
		for(int i= 0; i < size_act_table[work_sta]; i++)
			if(action_table[work_sta][i].ch == buffer[index_buf]){
				err = false;
				if(action_table[work_sta][i].nxt_sta == 0){
					cout << "Accept!!!" << endl;
					done = true;
					break;
				}
				else if(action_table[work_sta][i].nxt_sta > 0){
					s.push(make_pair(action_table[work_sta][i].nxt_sta,action_table[work_sta][i].ch));
					index_buf++;
					break;
				}
				else{
					int tp = action_table[work_sta][i].nxt_sta*(-1);	//用来归约的产生式编号
					for(int k = 0; k < length[tp]-1; k++)
						s.pop();
					--index_buf;
					buffer[index_buf] = G[tp][0];
					break;
				}
			}
	} while(done == false && err == false);
	if(!done)
		cout << "请检查输入串!!!" << endl;
	G_ifile.close();
	input_ifile.close();
	items_ofile.close();
	act_ofile.close();
	return 0;
}
```
