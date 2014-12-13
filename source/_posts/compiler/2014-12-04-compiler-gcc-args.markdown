---
layout: post
title: "部分GCC选项"
date: 2014-12-04 17:23:00 +0800
comments: false
categories:
- 2014
- 2014~12
- compiler
- compiler~base
tags:
---
##### -Werror 和 -I 很有用  

<table>
<tr bgcolor="#c0c0c0">
<th>命令</th><th>描述</th>
</tr>
<tr>
<td>-l&nbsp;<em>library</em>-l<em>library</em></td>
<td>进行链接时搜索名为library的库。例子： $ gcc test.c -lm -o test</td>
</tr>
<tr>
<td>-I<em>dir</em></td>
<td>把<em>dir</em>加入到搜索头文件的路径列表中。例子： $ gcc test.c -I../inc -o test</td>
</tr>
<tr>
<td>-L<em>dir</em></td>
<td>把<em>dir</em>加入到搜索库文件的路径列表中。例子： $ gcc -I/home/foo -L/home/foo -ltest test.c -o test</td>
</tr>
<tr>
<td>-D<em>name</em></td>
<td>预定义一个名为<em>name</em>的宏，值为1。例子： $ gcc -DTEST_CONFIG test.c -o test</td>
</tr>
<tr>
<td>-D<em>name</em>=<em>definition</em></td>
<td>预定义名为<em>name</em>，值为<em>definition</em>的宏。</td>
</tr>
<tr>
<td>-ggdb&nbsp;-ggdb<em>level</em></td>
<td>为调试器 gdb 生成调试信息。<em>level</em>可以为1，2，3，默认值为2。</td>
</tr>
<tr>
<td>-g&nbsp;-g<em>level</em></td>
<td>生成操作系统本地格式的调试信息。-g 和 -ggdb 并不太相同， -g 会生成 gdb 之外的信息。<em>level</em>取值同上。</td>
</tr>
<tr>
<td>-s</td>
<td>去除可执行文件中的符号表和重定位信息。用于减小可执行文件的大小。</td>
</tr>
<tr>
<td>-M</td>
<td>告诉预处理器输出一个适合make的规则，用于描述各目标文件的依赖关系。对于每个 源文件，预处理器输出 一个make规则，该规则的目标项(target)是源文件对应的目标文件名，依赖项(dependency)是源文件中 #include引用的所有文件。生成的规则可 以是单行，但如果太长，就用`/'-换行符续成多行。规则 显示在标准输出，不产生预处理过的C程序。</td>
</tr>
<tr>
<td>-C</td>
<td>告诉预处理器不要丢弃注释。配合`-E'选项使用。</td>
</tr>
<tr>
<td>-P</td>
<td>告诉预处理器不要产生`#line'命令。配合`-E'选项使用。</td>
</tr>
<tr>
<td>-static</td>
<td>在支持动态链接的系统上，阻止连接共享库。该选项在其它系统上 无效。</td>
</tr>
<tr>
<td>-nostdlib</td>
<td>不连接系统标准启动文件和标准库文件，只把指定的文件传递给连接器。</td>
</tr>
<tr bgcolor="#c0c0c0">
<th>Warnings</th><th></th>
</tr>
<tr>
<td>-Wall</td>
<td>会打开一些很有用的警告选项，建议编译时加此选项。</td>
</tr>
<tr>
<td>-W&nbsp;-Wextra</td>
<td>打印一些额外的警告信息。</td>
</tr>
<tr>
<td>-w</td>
<td>禁止显示所有警告信息。</td>
</tr>
<tr>
<td>-Wshadow</td>
<td>当一个局部变量遮盖住了另一个局部变量，或者全局变量时，给出警告。很有用的选项，建议打开。 -Wall 并不会打开此项。</td>
</tr>
<tr>
<td>-Wpointer-arith</td>
<td>对函数指针或者void *类型的指针进行算术操作时给出警告。也很有用。 -Wall 并不会打开此项。</td>
</tr>
<tr>
<td>-Wcast-qual</td>
<td>当强制转化丢掉了类型修饰符时给出警告。 -Wall 并不会打开此项。</td>
</tr>
<tr>
<td>-Waggregate-return</td>
<td>如果定义或调用了返回结构体或联合体的函数，编译器就发出警告。</td>
</tr>
<tr>
<td>-Winline</td>
<td>无论是声明为 inline 或者是指定了-finline-functions 选项，如果某函数不能内联，编译器都将发出警告。如果你的代码含有很多 inline 函数的话，这是很有用的选项。</td>
</tr>
<tr>
<td>-Werror</td>
<td>把警告当作错误。出现任何警告就放弃编译。</td>
</tr>
<tr>
<td>-Wunreachable-code</td>
<td>如果编译器探测到永远不会执行到的代码，就给出警告。也是比较有用的选项。</td>
</tr>
<tr>
<td>-Wcast-align</td>
<td>一旦某个指针类型强制转换导致目标所需的地址对齐增加时，编译器就发出警告。</td>
</tr>
<tr>
<td>-Wundef</td>
<td>当一个没有定义的符号出现在 #if 中时，给出警告。</td>
</tr>
<tr>
<td>-Wredundant-decls</td>
<td>如果在同一个可见域内某定义多次声明，编译器就发出警告，即使这些重复声明有效并且毫无差别。</td>
</tr>
</table>

