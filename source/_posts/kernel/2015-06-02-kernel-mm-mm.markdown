---
layout: post
title: "kmalloc、vmalloc、malloc的区别"
date: 2015-06-02 16:48:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~mm
tags:
---
blog.csdn.net/macrossdzh/article/details/5958368

简单的说：  
  kmalloc和vmalloc是分配的是内核的内存,malloc分配的是用户的内存  
  kmalloc保证分配的内存在物理上是连续的,vmalloc保证的是在虚拟地址空间上的连续,malloc不保证任何东西(这点是自己猜测的,不一定正确)  
  kmalloc能分配的大小有限,vmalloc和malloc能分配的大小相对较大  
  内存只有在要被DMA访问的时候才需要物理上连续  
  vmalloc比kmalloc要慢  

详细的解释：  
  对于提供了MMU（存储管理器，辅助操作系统进行内存管理，提供虚实地址转换等硬件支持）的处理器而言，Linux提供了复杂的存储管理系统，使得进程所能访问的内存达到4GB。
  进程的4GB内存空间被人为的分为两个部分--用户空间与内核空间。用户空间地址分布从0到3GB(PAGE_OFFSET，在0x86中它等于0xC0000000)，3GB到4GB为内核空间。  
  内核空间中，从3G到vmalloc_start这段地址是物理内存映射区域（该区域中包含了内核镜像、物理页框表mem_map等等），比如我们使用 的 VMware虚拟系统内存是160M，那么3G～3G+160M这片内存就应该映射物理内存。在物理内存映射区之后，就是vmalloc区域。对于 160M的系统而言，vmalloc_start位置应在3G+160M附近（在物理内存映射区与vmalloc_start期间还存在一个8M的gap 来防止跃界），vmalloc_end的位置接近4G(最后位置系统会保留一片128k大小的区域用于专用页面映射)

  kmalloc和get_free_page申请的内存位于物理内存映射区域，而且在物理上也是连续的，它们与真实的物理地址只有一个固定的偏移，因此存在较简单的转换关系，virt_to_phys()可以实现内核虚拟地址转化为物理地址：
```
	#define __pa(x) ((unsigned long)(x)-PAGE_OFFSET)
	extern inline unsigned long virt_to_phys(volatile void * address)
	{
		return __pa(address);
	}
```

上面转换过程是将虚拟地址减去3G（PAGE_OFFSET=0XC000000）。

与之对应的函数为phys_to_virt()，将内核物理地址转化为虚拟地址：
```
	#define __va(x) ((void *)((unsigned long)(x)+PAGE_OFFSET))
	extern inline void * phys_to_virt(unsigned long address)
	{
		return __va(address);
	}
```
virt_to_phys()和phys_to_virt()都定义在include/asm-i386/io.h中。

而vmalloc申请的内存则位于vmalloc_start～vmalloc_end之间，与物理地址没有简单的转换关系，虽然在逻辑上它们也是连续的，但是在物理上它们不要求连续。

---------------

blog.csdn.net/kris_fei/article/details/17243527

平台： msm8x25  
系统： android 4.1  
内核： 3.4.0  

#### 概念

由于系统的连续物理内存有限，这使得非连续物理内存的使用在linux内核中出现，这叫vmalloc机制。和前者一样，vmalloc机制中的虚拟地址也是连续的。

##### Vmallocinfo

Vmalloc机制并不是狭义地指使用vmalloc函数分配，其他还有如ioremap, iotable_init等。可以从/proc/vmallocinfo获取到此信息：

```
	#cat /proc/vmallocinfo
	0xf3600000-0xf36ff0001044480 binder_mmap+0xb0/0x224 ioremap
	………..
	0xf6680000-0xf66c1000 266240 kgsl_page_alloc_map_kernel+0x98/0xe8 ioremap
	0xf6700000-0xf67ff0001044480 binder_mmap+0xb0/0x224 ioremap
	…………….
	0xf6f00000-0xf6f41000 266240 kgsl_page_alloc_map_kernel+0x98/0xe8 ioremap
	0xf7200000-0xf72ff0001044480 binder_mmap+0xb0/0x224 ioremap
	0xfa000000-0xfa001000   4096 iotable_init+0x0/0xb0 phys=c0800000 ioremap
	……………..
	0xfa105000-0xfa106000   4096 iotable_init+0x0/0xb0 phys=a9800000 ioremap
	0xfa200000-0xfa3000001048576 pmd_empty_section_gap+0x0/0x3c ioremap
	0xfa300000-0xfa4000001048576 iotable_init+0x0/0xb0 phys=100000 ioremap
	0xfa400000-0xfa5000001048576 iotable_init+0x0/0xb0 phys=aa500000 ioremap
	0xfa500000-0xfa6000001048576 pmd_empty_section_gap+0x0/0x3c ioremap
	0xfa701000-0xfa702000   4096 iotable_init+0x0/0xb0 phys=c0400000 ioremap
	…………..
	0xfa800000-0xfa9000001048576 pmd_empty_section_gap+0x0/0x3c ioremap
	0xfa900000-0xfb60000013631488 iotable_init+0x0/0xb0 phys=ac000000 ioremap
	0xfefdc000-0xff000000 147456 pcpu_get_vm_areas+0x0/0x56c vmalloc
```

上面的列数意思依次是：虚拟地址，分配大小，哪个函数分配的，物理地址，分配类型。

后面会提到vmalloc size的划分是按照此info来修改的。

#### 分配标志

是否划分到vamlloc区域主要是以下重要的标志来决定的：

File: kernel/include/linux/vmalloc.h
```
	/* bits in flags ofvmalloc's vm_struct below */
	#defineVM_IOREMAP    0x00000001     /* ioremap()and friends */
	#define VM_ALLOC     0x00000002     /* vmalloc() */
	#defineVM_MAP        0x00000004     /* vmap()ed pages */
	#defineVM_USERMAP    0x00000008     /* suitable forremap_vmalloc_range */
	#defineVM_VPAGES     0x00000010     /* buffer for pages was vmalloc'ed */
	#defineVM_UNLIST     0x00000020     /* vm_struct is not listed in vmlist */
	/* bits [20..32]reserved for arch specific ioremap internals */
```

Vmallocinfo中的函数，你可以对照源码看一下，在设置flag的时候就会有VM_IOREMAP, VM_ALLOC这些标志。

##### Vmalloc区域

Vmalloc的区域是由两个宏变量来表示： VMALLOC_START,VMALLOC_END.

File: kernel/arch/arm/include/asm/pgtable.h
```
	#defineVMALLOC_OFFSET       (8*1024*1024)
	#defineVMALLOC_START        (((unsigned long)high_memory + VMALLOC_OFFSET) & ~(VMALLOC_OFFSET-1))
	#defineVMALLOC_END          0xff000000UL
```

VMALLOC_START：看上去会随着high_memory的值变化。

VMALLOC_OFFSET：系统会在low memory和VMALLOC区域留8M，防止访问越界。因此假如理论上vmalloc size有300M，实际可用的也是只有292M。

File: kernel/Documentation/arm/memory.txt有给出更好的解释：
```
VMALLOC_START   VMALLOC_END-1    vmalloc() / ioremap() space. Memory returned byvmalloc/ioremap will be dynamically placed in this region. Machine specificstatic mappings are also located here through iotable_init(). VMALLOC_START isbased upon the value of the high_memoryvariable, and VMALLOC_END is equal to 0xff000000.
```

下图摘自网络，看下VMALLOC_START和VMALLOC_END的位置。0xc0000000到VMALLOC_START为low memory虚拟地址区域。

#### Vmallocsize 计算

有了以上知识后我们看下vmalloc size是如何分配的，目前有两种方法，kernel默认分配一个, 以及开机从cmdline分配。

##### 1. 从cmdline分配

File: device/qcom/msm7627a/BoardConfig.mk

BOARD_KERNEL_CMDLINE := androidboot.hardware=qcom loglevel=7vmalloc=200M

上面的值在build的时候会被赋值给kernel 的cmdline。

开机的时候early_vmalloc()会去读取vmalloc这个值。

File: kernel/arch/arm/mm/mmu.c
```
	static int__init early_vmalloc(char *arg)
	{
		/*cmdline中的vmalloc会被解析到vmlloc_reserve中。*/
		unsigned long vmalloc_reserve = memparse(arg, NULL);

		/*小于16M则用16M。*/
		if (vmalloc_reserve < SZ_16M) {
			vmalloc_reserve = SZ_16M;
			printk(KERN_WARNING
					"vmalloc area too small, limiting to %luMB\n",
					vmalloc_reserve >> 20);
		}

		/*大于可用虚拟地址内存则使用可用地址部分再减去32M。*/
		if (vmalloc_reserve > VMALLOC_END - (PAGE_OFFSET + SZ_32M)) {
			vmalloc_reserve = VMALLOC_END - (PAGE_OFFSET + SZ_32M);
			printk(KERN_WARNING
					"vmalloc area is too big, limiting to %luMB\n",
					vmalloc_reserve >> 20);
		}

		/*计算偏移起始地址。*/
		vmalloc_min = (void *)(VMALLOC_END - vmalloc_reserve);
		return 0;
	}
	early_param("vmalloc",early_vmalloc);
```

vmalloc_min会影响arm_lowmem_limit,arm_lowmem_limit其实就是high_memory。因为此过程不是我们要分析的重点，如果有兴趣可分析kernel/arch/arm/mm/mmu.c中的sanity_check_meminfo()函数。

所以，VMALLOC_START受到了hight_memory的影响而发生了变化，最终使得vmalloc size也变化了！

##### 2. 开机默认分配：

File: kernel/arch/arm/mm/mmu.c
```
	static void * __initdata vmalloc_min =
		(void *)(VMALLOC_END - (240 << 20) - VMALLOC_OFFSET);
```

当cmdline无vmalloc参数传进来的时候，early_vmalloc()函数也不会调用到，vmalloc_min的值就会被默认传进来了，默认是240M。

后面的步骤和方法1一样了！

开机log有memory layout 信息：
```
	[    0.000000] [cpuid: 0] Virtual kernelmemory layout:
	[    0.000000] [cpuid:0]     vector  : 0xffff0000 - 0xffff1000  (   4 kB)
	[    0.000000] [cpuid:0]     fixmap  : 0xfff00000 - 0xfffe0000   (896 kB)
	[    0.000000] [cpuid:0]     vmalloc : 0xf3000000 - 0xff000000   ( 192MB)
	[    0.000000] [cpuid:0]     lowmem  : 0xc0000000 - 0xf2800000   (808 MB)
	[    0.000000] [cpuid:0]     pkmap   : 0xbfe00000 -0xc0000000   (   2 MB)
	[    0.000000] [cpuid:0]     modules : 0xbf000000 - 0xbfe00000  (  14 MB)
	[    0.000000] [cpuid:0]       .text : 0xc0008000 -0xc0893034   (8749 kB)
	[    0.000000] [cpuid:0]       .init : 0xc0894000 -0xc08cdc00   ( 231 kB)
	[    0.000000] [cpuid:0]       .data : 0xc08ce000 -0xc09f8eb8   (1196 kB)
	[    0.000000] [cpuid:0]        .bss : 0xc0a78eec -0xc0f427a8   (4903 kB)
```

其中看到vmalloc为192MB , cmdline中使用vmllaoc就是200M。

Lowmem为地段内存部分，可见lowmem和vmalloc中间有8M空隙。

##### Vmalloc该分配多大?

Linux内核版本从3.2到3.3 默认的vmalloc size由128M 增大到了240M，3.4.0上的

修改Commit信息如下：

To accommodate all static mappings on machines withpossible highmem usage, the default vmalloc area size is changed to 240 MB sothat VMALLOC_START is no higher than 0xf0000000 by default.

看其意思是因为开机的静态映射增加了，所以要扩大。

另外3.2到3.3版本的一个重大变化是将android引入到主线内核中。我想增大vmalloc size到240M是基于此考虑吧。当然，各家厂商都也可以基于自己平台来动态修改size的。 

那么如何判断当前vmalloc size不足呢？

/proc/meminfo中有vmalloc信息:  
VmallocTotal:     540672 kB  
VmallocUsed:      165268 kB  
VmallocChunk:     118788kB  

事实上这里的VmallocUsed只是表示已经被真正使用掉的vmalloc区域，但是区域之前的空隙也就是碎片没有被计算进去。

所以，回到前面说的/proc/vmallocinfo，假设我们的vmalloc size就是200M。那么区域为0xf3000000- 0xff000000，从vmallocinfo中可以看到，前面大部分虚拟地址空间都用掉了，剩下0xfb600000到0xfefdc000这57M空间，假如申请了64M，那么就会失败了。

开机分配使用掉vmalloc之后到底该剩余多少目前没有具体依据，一般来说1GB RAM可以设置为400~600M。

