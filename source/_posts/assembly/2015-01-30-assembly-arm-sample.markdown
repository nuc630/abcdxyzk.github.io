---
layout: post
title: "ARM汇编简单样例"
date: 2015-01-30 15:43:00 +0800
comments: false
categories:
- 2015
- 2015~01
- assembly
- assembly~arm
tags:
---
#### 例一
```
	.section .data
		.align 2
		.LC0: .string "gggghhhii"

	.section .text
		.align 2
		.global main
		.type   main, %function
	main:
		stmfd   sp!, {fp, lr} 
		ldr     r0, .L0 
		bl      puts
		ldmfd   sp!, {fp, pc} 

	.L0: .word .LC0
```
```
android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-as b.s -o b.o

/home/kk/android/android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-ld -dynamic-linker /system/bin/linker -X -m armelf_linux_eabi -z noexecstack -z relro -z now crtbegin_dynamic.o -L/home/kk/android/android-ndk-r9d/platforms/android-19/arch-arm/usr/lib/ -L/home/kk/android/android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/../lib/gcc/arm-linux-androideabi/4.6 -L/home/kk/android/android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/../lib/gcc -L/home/kk/android/android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/../lib/gcc/arm-linux-androideabi/4.6/../../../../arm-linux-androideabi/lib b.o -lgcc -lc -ldl -lgcc crtend_android.o -o b.out
```

#### 例二

a.c
```
	#include <stdio.h>

	int i=12;
	int j;

	int main()
	{
		i = 34; 
		j = 56; 
		printf("Hello World\n");
		return 0;
	}
```

```
/home/kk/android/android-ndk-r9d/toolchains/arm-linux-androideabi-4.6/prebuilt/linux-x86_64/bin/arm-linux-androideabi-gcc -I/home/kk/android/android-ndk-r9d/platforms/android-19/arch-arm/usr/include -L/home/kk/android/android-ndk-r9d/platforms/android-19/arch-arm/usr/lib/ -S a.c
```

```
        .arch armv5te
        .fpu softvfp
        .eabi_attribute 20, 1
        .eabi_attribute 21, 1
        .eabi_attribute 23, 3
        .eabi_attribute 24, 1
        .eabi_attribute 25, 1
        .eabi_attribute 26, 2
        .eabi_attribute 30, 6
        .eabi_attribute 18, 4
        .file   "a.c"
        .global i
        .data
        .align  2
        .type   i, %object
        .size   i, 4
i:
        .word   12  
        .comm   j,4,4
        .section        .rodata
        .align  2
.LC0:
        .ascii  "Hello World\000"
        .text
        .align  2
        .global main
        .type   main, %function
main:
        @ args = 0, pretend = 0, frame = 0 
        @ frame_needed = 1, uses_anonymous_args = 0 
        stmfd   sp!, {fp, lr} 
        add     fp, sp, #4
        ldr     r3, .L2 
.LPIC0:
        add     r3, pc, r3
        ldr     r2, .L2+4
        ldr     r2, [r3, r2] 
        mov     r1, #34 
        str     r1, [r2, #0] 
        ldr     r2, .L2+8
        ldr     r3, [r3, r2] 
        mov     r2, #56 
        str     r2, [r3, #0] 
        ldr     r3, .L2+12
.LPIC1:
        add     r3, pc, r3
        mov     r0, r3
        bl      puts(PLT)
        mov     r3, #0
        mov     r0, r3
        ldmfd   sp!, {fp, pc}
.L3:
        .align  2
.L2:
        .word   _GLOBAL_OFFSET_TABLE_-(.LPIC0+8)
        .word   i(GOT)
        .word   j(GOT)
        .word   .LC0-(.LPIC1+8)
        .size   main, .-main
        .ident  "GCC: (GNU) 4.6 20120106 (prerelease)"
        .section        .note.GNU-stack,"",%progbits
```

