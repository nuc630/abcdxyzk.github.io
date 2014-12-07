---
layout: post
title: "AT&T 汇编"
date: 2011-08-31 13:06:00 +0800
comments: false
categories:
- 2011
- 2011~08
- assembly
- assembly~base
tags:
---
AT&T 汇编
#### 1.Register Reference
引用寄存器要在寄存器号前加百分号%,如“movl %eax, %ebx”。  
80386 有如下寄存器:
```
[1] 8 个 32-bit 寄存器 %eax,%ebx,%ecx,%edx,%edi,%esi,%ebp,%esp;
( 8 个 16-bit 寄存器,它们事实上是上面 8 个 32-bit 寄存器的低 16 位:%ax,%bx,
%cx,%dx,%di,%si,%bp,%sp;
8 个 8-bit 寄存器:%ah,%al,%bh,%bl,%ch,%cl,%dh,%dl。它们事实上
是寄存器%ax,%bx,%cx,%dx 的高 8 位和低 8 位;)
[2] 6 个段寄存器:%cs(code),%ds(data),%ss(stack), %es,%fs,%gs;
[3] 3 个控制寄存器:%cr0,%cr2,%cr3;
[4] 6 个 debug 寄存器:%db0,%db1,%db2,%db3,%db6,%db7;
[5] 2 个测试寄存器:%tr6,%tr7;
[6] 8 个浮点寄存器栈:%st(0),%st(1),%st(2),%st(3),%st(4),%st(5),%st(6),%st(7)。
```

#### 2. Operator Sequence
操作数排列是从源(左)到目的(右),如“movl %eax(源), %ebx(目的)”

#### 3. Immediately Operator
使用立即数,要在数前面加符号$, 如“movl $0x04, %ebx”  
或者:
```
para = 0x04
movl $para, %ebx
```
指令执行的结果是将立即数 0x04 装入寄存器 ebx。

#### 4. Symbol Constant
符号常数直接引用 如
```
value: .long 0x12a3f2de
movl value , %ebx
```
指令执行的结果是将常数 0x12a3f2de 装入寄存器 ebx。  
引用符号地址在符号前加符号$, 如“movl $value, % ebx”则是将符号 value 的地址装入寄存器 ebx。

#### 5. Length of Operator
操作数的长度用加在指令后的符号表示 b(byte, 8-bit), w(word, 16-bits), l(long,32-bits) ,如“movb %al, %bl” ,“movw
%ax, %bx”,“movl %eax, %ebx ”。  
如 果没有指定操作数长度的话,编译器将按照目标操作数的长度来设置。比如指令“mov %ax, %bx”,由于目标操作数 bx 的长度为
word , 那 么 编 译 器 将 把 此 指 令 等 同 于 “ movw %ax,%bx” 。 同 样 道 理 , 指 令 “ mov $4, %ebx” 等 同 于 指 令 “ movl $4,
%ebx”,“push %al”等同于“pushb %al”。对于没有指定操作数长度,但编译器又无法猜测的指令,编译器将会报错,比如指令
“push $4”。

#### 6. Sign and Zero Extension
绝大多数面向 80386 的 AT&T 汇编指令与 Intel 格式的汇编指令都是相同的,但符号扩展指令和零扩展指令有不同格式。符号扩展指令
和零扩展指令需要指定源操作数长度和目的操作数长度,即使在某些指令中这些操作数是隐含的。

在 AT&T 语法中,符号扩展和零扩展指令的格式为,基本部分"movs"和"movz"(对应 Intel 语法的 movsx 和 movzx),后面跟
上源操作数长度和目的操作数长度。 movsbl 意味着 movs (from)byte (to)long;movbw 意味着 movs (from)byte
(to)word;movswl 意味着 movs (from)word (to)long。对于 movz 指令也一样。比如指令“movsbl %al,%edx”意味着将
al 寄存器的内容进行符号扩展后放置到 edx 寄存器中。

其它的 Intel 格式的符号扩展指令还有:
```
cbw -- sign-extend byte in %al to word in %ax;
cwde -- sign-extend word in %ax to long in %eax;
cwd -- sign-extend word in %ax to long in %dx:%ax;
cdq -- sign-extend dword in %eax to quad in %edx:%eax;
```
对应的 AT&T 语法的指令为 cbtw,cwtl,cwtd,cltd。

#### 7. Call and Jump
段内调用和跳转指令为 "call" , "ret" 和 "jmp",段间调用和跳转指令为 "lcall" , "lret" 和 "ljmp" 。段间调用和跳转指令的格式为  
“lcall/ljmp $SECTION, $OFFSET”,而段间返回指令则为“lret $STACK-ADJUST”。

#### 8. Prefix
操作码前缀被用在下列的情况:
```
[1]字符串重复操作指令(rep,repne);
[2]指定被操作的段(cs,ds,ss,es,fs,gs);
[3]进行总线加锁(lock);
[4]指定地址和操作的大小(data16,addr16);
```
在 AT&T 汇编语法中,操作码前缀通常被单独放在一行,后面不跟任何操作数。例如,对于重复 scas 指令,其写法为:
```
repne
scas
```

上述操作码前缀的意义和用法如下:
```
[1]指定被操作的段前缀为 cs,ds,ss,es,fs,和 gs。在 AT&T 语法中,只需要按照
section:memory-operand 的格式就指定了相应的段前缀。比如:
lcall %cs:realmode_swtch
[2]操作数/地址大小前缀是“data16”和"addr16",它们被用来在 32-bit 操作数/地址代码中指定 16-bit 的操作数/地址。
[3]总线加锁前缀“lock”,它是为了在多处理器环境中,保证在当前指令执行期间禁止一切中断。这个前缀仅仅对 ADD, ADC, AND,
BTC, BTR, BTS, CMPXCHG,DEC,
INC, NEG, NOT, OR, SBB, SUB, XOR, XADD,XCHG 指令有效,如果将 Lock 前
缀用在其它指令之前,将会引起异常。
[4]字符串重复操作前缀"rep","repe","repne"用来让字符串操作重复“%ecx”次。
```

#### 9. Memory Reference
Intel 语法的间接内存引用的格式为:  
```
section:[base+index*scale+displacement]
```
而在 AT&T 语法中对应的形式为:
```
section:displacement(base,index,scale)
```
其中,base 和 index 是任意的 32-bit base 和 index 寄存器。scale 可以取值 1,2,4,8。如果不指定 scale 值,则默认值为 1。
section 可以指定任意的段寄存器作为段前缀,默认的段寄存器在不同的情况下不一样。如果在指令中指定了默认的段前缀,则编译器在
目标代码中不会产生此段前缀代码。

下面是一些例子:  
-4(%ebp):base=%ebp,displacement=-4,section 没有指定,由于 base=%ebp,所以默认的 section=%ss,index,scale
没有指定,则 index 为 0。  
foo(,%eax,4):index=%eax,scale=4,displacement=foo。其它域没有指定。这里默认的 section=%ds。  
foo(,1):这个表达式引用的是指针 foo 指向的地址所存放的值。注意这个表达式中没有 base 和 index,并且只有一个逗号,这是一种
异常语法,但却合法。  
%gs:foo:这个表达式引用的是放置于%gs 段里变量 foo 的值。  
如果 call 和 jump 操作在操作数前指定前缀“*”,则表示是一个绝对地址调用/跳转,也就是说 jmp/call 指令指定的是一个绝对地址。  
如果没有指定"*",则操作数是一个相对地址。  
任何指令如果其操作数是一个内存操作, 则指令必须指定它的操作尺寸  
(byte,word,long),也就是说必须带有指令后缀(b,w,l)。  
Linux 工作在保护模式下,用的是 32 位线性地址,所以在计算地址时不用考虑段基址和偏移量,而是采用如下的地  
址计算方法:  
disp + base + index * scale  
下面是一些内存操作数的例子:  
```
AT&T 格式
movl -4(%ebp), %eax
movl array(, %eax, 4), %eax
movw array(%ebx, %eax, 4), %cx
movb $4, %fs:(%eax)
```
其中下面这些省略了浮点数及 IA-32 如 SSE FPU 等特殊的指令集部分, 我觉得重要的是学习
linux 汇编的语法及编译原理和程序控制流程, 具体的指令细节就不那么重要了。

