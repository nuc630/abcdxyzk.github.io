---
layout: post
title: "修改elf文件标记的源码路径debugedit，find-debuginfo"
date: 2014-11-03 18:10:00 +0800
comments: false
categories:
- 2014
- 2014~11
- debug
- debug~debugedit
tags:
---
```
	yum install rpm-build
	sudo apt-get install rpm
```
/usr/lib/rpm/debugedit 用来改变源码查找路径。
```
	$ /usr/lib/rpm/debugedit
	Usage: debugedit [OPTION...]
	  -b, --base-dir=STRING      base build directory of objects
	  -d, --dest-dir=STRING      directory to rewrite base-dir into
	  -l, --list-file=STRING     file where to put list of source and header file
		                     names
	  -i, --build-id             recompute build ID note and print ID on stdout

	Help options:
	  -?, --help                 Show this help message
	  --usage                    Display brief usage message
```
base-dir 长度要大等于 dest-dir  
-i 输出build-id  
-l 输出源编译文件位置，便于有需要的人打包

--------

.debug_str段保存着所有全局变量的名字，以0x00作为每一个全局变量名的结束。  
在其它段来调用名字时，是以其在.debug_str段的偏移量来实现的  
gcc -g /root/Desktop/a.c -o /root/Desktop/a.out  
用绝对路径编译，在.debug_str段中就会存下源文件路径，.debug_info的DW_TAG_compile_unit中的DW_AT_name对应.debug_str中的偏移。  

```
$ objdump --dwarf=str a.out
....
  0x00000000 474e5520 4320342e 342e3720 32303132 GNU C 4.4.7 2012
  0x00000010 30333133 20285265 64204861 7420342e 0313 (Red Hat 4.
  0x00000020 342e372d 3429006c 6f6e6720 756e7369 4.7-4).long unsi
  0x00000030 676e6564 20696e74 002f726f 6f742f44 gned int.<span style="color:red">/root/D</span>
  0x00000040 65736b74 6f702f61 2e630075 6e736967 esktop/a.c.unsig
  0x00000050 6e656420 63686172 006d6169 6e006c6f ned char.main.lo
  0x00000060 6e672069 6e74002f 726f6f74 2f446573 ng int./root/Des
  0x00000070 6b746f70 0073686f 72742075 6e736967 ktop.short unsig
  0x00000080 6e656420 696e7400 73686f72 7420696e ned int.short in
  0x00000090 7400                                t.


$ objdump --dwarf=info a.out
.....
 <0><b>: Abbrev Number: 1 (DW_TAG_compile_unit)
    < c>   DW_AT_producer    : (indirect string, offset: 0x0): GNU C 4.4.7 20120313 (Red Hat 4.4.7-4)
    <10>   DW_AT_language    : 1        (ANSI C)
    <11>   DW_AT_name        : (indirect string, offset: 0x39): /root/Desktop/a.c
    <15>   DW_AT_comp_dir    : (indirect string, offset: 0x67): /root/Desktop
    <19>   DW_AT_low_pc      : 0x4004c4
    <21>   DW_AT_high_pc     : 0x40051c
    <29>   DW_AT_stmt_list   : 0x0
```
-----------------------------------------

```  
$ /usr/lib/rpm/debugedit -b /root/Desktop -d /usr/src /root/Desktop/a.out
```

----------------------------------------
```
$ objdump --dwarf=str a.out
...
  0x00000000 474e5520 4320342e 342e3720 32303132 GNU C 4.4.7 2012
  0x00000010 30333133 20285265 64204861 7420342e 0313 (Red Hat 4.
  0x00000020 342e372d 3429006c 6f6e6720 756e7369 4.7-4).long unsi
  0x00000030 676e6564 20696e74 002f7573 722f7372 gned int./usr/sr
  0x00000040 632f612e 63002f61 2e630075 6e736967 c/a.c./a.c.unsig
  0x00000050 6e656420 63686172 006d6169 6e006c6f ned char.main.lo
  0x00000060 6e672069 6e74002f 726f6f74 2f446573 ng int./root/Des
  0x00000070 6b746f70 0073686f 72742075 6e736967 ktop.short unsig
  0x00000080 6e656420 696e7400 73686f72 7420696e ned int.short in
  0x00000090 7400                                t.


$ objdump --dwarf=info a.out

...
 <0><b>: Abbrev Number: 1 (DW_TAG_compile_unit)
    < c>   DW_AT_producer    : (indirect string, offset: 0x0): GNU C 4.4.7 20120313 (Red Hat 4.4.7-4)
    <10>   DW_AT_language    : 1        (ANSI C)
    <11>   DW_AT_name        : (indirect string, offset: 0x39): /usr/src/a.c
    <15>   DW_AT_comp_dir    : (indirect string, offset: 0x67): /root/Desktop
    <19>   DW_AT_low_pc      : 0x4004c4
    <21>   DW_AT_high_pc     : 0x40051c
    <29>   DW_AT_stmt_list   : 0x0
```
