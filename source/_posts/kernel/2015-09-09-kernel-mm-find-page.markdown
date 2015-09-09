---
layout: post
title: "查看某进程内存"
date: 2015-09-09 17:54:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~mm
tags:
---

test.c
```
	#include<sys/mman.h>
	#include<sys/types.h>
	#include<fcntl.h>
	#include<stdio.h>
	#include<unistd.h>

	#include <time.h>
	#include <string.h>

	int main()
	{   
		int i,j,k,l;
		char *mp;
		mp = (char*)mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0); 
		strcpy(mp, "ABCDEFGHIJKL1234567890!@#$%^&*()KKKKKKKKKKKKKKKKKKK");
		strcpy(mp+4096, "AAAAAAAAAAAAAAAAAAABBBBBBBBBBBBCCCCCCCCCCC");
		sleep(10000000);
		munmap(mp, 8192);
		return 0;
	}
```


```
	# strace ./test
	execve("./test", ["./test"], [/* 23 vars */]) = 0
	brk(0)                                  = 0x1bdf000
	mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f133f166000
	mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f133f165000
	access("/etc/ld.so.preload", R_OK)      = -1 ENOENT (No such file or directory)
	open("/etc/ld.so.cache", O_RDONLY)      = 3
	fstat(3, {st_mode=S_IFREG|0644, st_size=72203, ...}) = 0
	mmap(NULL, 72203, PROT_READ, MAP_PRIVATE, 3, 0) = 0x7f133f153000
	close(3)                                = 0
	open("/lib64/libc.so.6", O_RDONLY)      = 3
	read(3, "\177ELF\2\1\1\0\0\0\0\0\0\0\0\0\3\0>\0\1\0\0\0\360\332a\2217\0\0\0"..., 832) = 832
	fstat(3, {st_mode=S_IFREG|0755, st_size=1726296, ...}) = 0
	mmap(0x3791600000, 3506520, PROT_READ|PROT_EXEC, MAP_PRIVATE|MAP_DENYWRITE, 3, 0) = 0x3791600000
	mprotect(0x379174f000, 2097152, PROT_NONE) = 0
	mmap(0x379194f000, 20480, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_DENYWRITE, 3, 0x14f000) = 0x379194f000
	mmap(0x3791954000, 16728, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_FIXED|MAP_ANONYMOUS, -1, 0) = 0x3791954000
	close(3)                                = 0
	mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f133f152000
	mmap(NULL, 4096, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f133f151000
	arch_prctl(ARCH_SET_FS, 0x7f133f1516e0) = 0
	mprotect(0x379194f000, 16384, PROT_READ) = 0
	mprotect(0x379141c000, 4096, PROT_READ) = 0
	munmap(0x7f133f153000, 72203)           = 0
	mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f133f163000
	rt_sigprocmask(SIG_BLOCK, [CHLD], [], 8) = 0
	rt_sigaction(SIGCHLD, NULL, {SIG_DFL, [], 0}, 8) = 0
	rt_sigprocmask(SIG_SETMASK, [], NULL, 8) = 0
	nanosleep({10000000, 0},
```

基本确定最后一个mmap就是我们申请的，它的起始虚拟地址是0x7f133f163000，所以要在对应tast的mm中找到相应的vma。


```
	crash> ps
	...
	  58674  58673   0  ffff88003d388ae0  IN   0.0    3672    316  test
	...
```


```
	crash_7.0.8> task_struct ffff88003d388ae0
	struct task_struct {
	...
	mm = 0xffff88003d80ba00,
	...
```

```
	crash_7.0.8> mm_struct 0xffff88003d80ba00
	struct mm_struct {
	  mmap = 0xffff88002a4d5ed0,
	  mm_rb = {
		rb_node = 0xffff88003c2fad38
	  },
	  mmap_cache = 0xffff880029332788,
	  get_unmapped_area = 0xffffffff81010410 <arch_get_unmapped_area_topdown>,
	  get_unmapped_exec_area = 0x0,
	  unmap_area = 0xffffffff8113aed0 <arch_unmap_area_topdown>,
	  mmap_base = 139720639541248,
	  task_size = 140737488351232,
	  cached_hole_size = 0,   
	  free_area_cache = 139720639524864,
	  pgd = 0xffff88000c952000,
	  ...
```

先看mmap，mmap_cache是不是，不是的话从mm_rb.rb_node开始找，这个是平衡二叉树的根。

```
	#define rb_entry(ptr, type, member) container_of(ptr, type, member)

	vma_tmp = rb_entry(rb_node, struct vm_area_struct, vm_rb);
```

所以rb_node的地址减去vm_rb在struct vm_area_struct的偏移就是对应struct vm_area_struct的地址（2.6.32-358是0x38）

所以rb_node = 0xffff88003c2fad38 => struct vm_area_struct = 0xffff88003c2fad00

根据find_vma函数方法，直到找到
```
	/* Look up the first VMA which satisfies  addr < vm_end,  NULL if none. */
	struct vm_area_struct *find_vma(struct mm_struct *mm, unsigned long addr)
	{
		struct vm_area_struct *vma = NULL;

		if (mm) {
			/* Check the cache first. */
			/* (Cache hit rate is typically around 35%.) */
			vma = mm->mmap_cache;
			if (!(vma && vma->vm_end > addr && vma->vm_start <= addr)) {
				struct rb_node * rb_node;

				rb_node = mm->mm_rb.rb_node;
				vma = NULL;

				while (rb_node) {
					struct vm_area_struct * vma_tmp;

					vma_tmp = rb_entry(rb_node,
							struct vm_area_struct, vm_rb);

					if (vma_tmp->vm_end > addr) {
						vma = vma_tmp;
						if (vma_tmp->vm_start <= addr)
							break;
						rb_node = rb_node->rb_left;
					} else 
						rb_node = rb_node->rb_right;
				}
				if (vma)
					mm->mmap_cache = vma; 
			}
		}
		return vma; 
	}
```

```
	crash_7.0.8> vm_area_struct 0xffff88002d29c5f8
	struct vm_area_struct {
	  vm_mm = 0xffff88003d80ba00,
	  vm_start = 139720639524864,
	  vm_end = 139720639541248,
	  vm_next = 0xffff880029332788,
	  vm_prev = 0xffff88003c2fa918,
	  vm_page_prot = {
		pgprot = 9223372036854775845
	  },
	  vm_flags = 1048691,
	  vm_rb = {
		rb_parent_color = 18446612133323974193,
		rb_right = 0xffff8800293327c0,
		rb_left = 0xffff88003c2fa950
	  },
	  ...


	crash_7.0.8> p/x 139720639524864
	$4 = 0x7f133f163000
```

所以对应的vma就是0xffff88002d29c5f8，用内核函数follow_page找到对应page

follow_page.c
```
	#include <linux/module.h>
	#include <linux/kernel.h>
	#include <linux/init.h>
	#include <linux/types.h>

	#include <linux/sysctl.h>
	#include <linux/timer.h>
	#include <linux/hardirq.h>
	#include <linux/bottom_half.h>
	#include <linux/preempt.h>

	#include <linux/types.h>
	#include <linux/proc_fs.h>
	#include <linux/file.h>

	#include <linux/kprobes.h>

	#include <linux/mm.h>
	#include <linux/mm_types.h>

	static int __init test_init(void)
	{
		int i;
		struct page *(*follow_page_p)(struct vm_area_struct *vma, unsigned long address, unsigned int flags)
			= (struct page *(*)(struct vm_area_struct *vma, unsigned long address, unsigned int flags))0xffffffff81133ab0;
		struct vm_area_struct *vma = (struct vm_area_struct *)0xffff88002d29c5f8;
		unsigned long address = 139720639524864UL;
		struct page *pa;  
		char ch[4096+10]; 
		pa = follow_page_p(vma, address, 0);
		memcpy(ch, page_address(pa), 4096); 
		printk("page = %p\n", pa);
		printk("%s\n", ch);   
		return 0;
	}

	static void __exit test_exit(void)
	{
		printk("test exit\n");
	}

	module_init(test_init);
	module_exit(test_exit);

	MODULE_LICENSE("GPL");
```

```
	obj-m := follow_page.o
	KDIR:=/lib/modules/$(shell uname -r)/build/
	PWD=$(shell pwd)

	all:
		make -C $(KDIR) M=$(PWD) modules
	clean:
		make -C $(KDIR) M=$(PWD) clean
```

```
	# insmod ./follow_page.ko
	# rmmod follow_page
	# dmesg
	page = ffffea000077a1a8
	ABCDEFGHIJKL1234567890!@#$%^&*()KKKKKKKKKKKKKKKKKKK
	test exit
```



--------------


```
	#include <linux/module.h> 
	#include <linux/kernel.h> 
	#include <linux/init.h>   
	#include <linux/types.h>  

	#include <linux/sysctl.h> 
	#include <linux/timer.h>  
	#include <linux/hardirq.h>
	#include <linux/bottom_half.h>
	#include <linux/preempt.h>

	#include <linux/types.h>  
	#include <linux/proc_fs.h>
	#include <linux/file.h>   

	#include <linux/kprobes.h>

	#include <linux/mm.h>
	#include <linux/mm_types.h>

	static int __init test_init(void)
	{
		struct page *(*follow_page_p)(struct vm_area_struct *vma, unsigned long address, unsigned int flags)
			= (struct page *(*)(struct vm_area_struct *vma, unsigned long address, unsigned int flags))0xffffffff81133ab0;
		struct vm_area_struct *vma = (struct vm_area_struct *)0xffff88002d29c5f8;
		unsigned long address = 139720639524864UL;
		struct page *pa;  
		char ch[4096+10]; 
		pa = follow_page_p(vma, address, 0);
		memcpy(ch, page_address(pa), 4096);
		{
			pgd_t *pgd;
			pud_t *pud;
			pmd_t *pmd;
			pte_t *pte;
			unsigned long pfn;

			pgd = pgd_offset(vma->vm_mm, address);
			pud = pud_offset(pgd, address);
			pmd = pmd_offset(pud, address);
			pte = pte_offset_map(pmd, address);
			pfn = pte_pfn(*pte);

			printk("follow_page=%p\n\n", pa);

			printk("PTE_PFN_MASK=0x%lx PAGE_OFFSET=%lx __va(x)=x+PAGE_OFFSET\n\n", PTE_PFN_MASK, PAGE_OFFSET);

			printk("mm->pgd=%p\n", vma->vm_mm->pgd);
			printk("PGDIR_SHIFT=%u PTRS_PER_PGD=%u pgd_index*8=0x%lx mm->pgd+index==pgd=%p\n\n", PGDIR_SHIFT, PTRS_PER_PGD, pgd_index(address)*8, pgd);

			printk("*pgd=0x%lx *pgd&MASK=0x%lx __va=%p\n", (*pgd).pgd, ((*pgd).pgd)&PTE_PFN_MASK, __va(((*pgd).pgd)&PTE_PFN_MASK));
			printk("PUD_SHIFT=%u PTRS_PER_PUD=%u pud_index*8=0x%lx __va+index==pud=%p\n\n", PUD_SHIFT, PTRS_PER_PUD, pud_index(address)*8, pud);

			printk("*pud=0x%lx *pud&MASK=0x%lx __va=%p\n", (*pud).pud, ((*pud).pud)&PTE_PFN_MASK, __va(((*pud).pud)&PTE_PFN_MASK));
			printk("PMD_SHIFT=%d PTRS_PER_PMD=%d pmd_index*8=0x%lx __va+index==pmd=%p\n\n", PMD_SHIFT, PTRS_PER_PMD, pmd_index(address)*8, pmd);

			printk("*pmd=0x%lx *pmd&MASK=0x%lx __va=%p\n", (*pmd).pmd, ((*pmd).pmd)&PTE_PFN_MASK, __va(((*pmd).pmd)&PTE_PFN_MASK));
			printk("PAGE_SHIFT=%d PTRS_PER_PTE=%d pte_index*8=0x%lx __va+index==pte=%p\n\n", PAGE_SHIFT, PTRS_PER_PTE, pte_index(address)*8, pte);

			printk("*pte=0x%lx *pte&MASK=0x%lx pte_pfn=%lx pfn=%lx\n", (*pte).pte, ((*pte).pte)&PTE_PFN_MASK, (((*pte).pte)&PTE_PFN_MASK)>>PAGE_SHIFT, pfn);
			printk("vmemmap=%p pfn*sizeof(page)=0x%lx cal_page=%p==follow_page\n\n", vmemmap, pfn*sizeof(struct page), vmemmap+pfn);
		}
		printk("%s\n", ch);
		return 0;
	}

	static void __exit test_exit(void)
	{
		printk("test exit\n");
	}

	module_init(test_init);   
	module_exit(test_exit);   

	MODULE_LICENSE("GPL");
```

```
	# dmesg
	follow_page=ffffea000077a1a8

	PTE_PFN_MASK=0x3ffffffff000 PAGE_OFFSET=ffff880000000000 __va(x)=x+PAGE_OFFSET

	mm->pgd=ffff88000c952000
	PGDIR_SHIFT=39 PTRS_PER_PGD=512 pgd_index*8=0x7f0 mm->pgd+index==pgd=ffff88000c9527f0

	*pgd=0x30bee067 *pgd&MASK=0x30bee000 __va=ffff880030bee000
	PUD_SHIFT=30 PTRS_PER_PUD=512 pud_index*8=0x260 __va+index==pud=ffff880030bee260

	*pud=0x323b1067 *pud&MASK=0x323b1000 __va=ffff8800323b1000
	PMD_SHIFT=21 PTRS_PER_PMD=512 pmd_index*8=0xfc0 __va+index==pmd=ffff8800323b1fc0

	*pmd=0xc934067 *pmd&MASK=0xc934000 __va=ffff88000c934000
	PAGE_SHIFT=12 PTRS_PER_PTE=512 pte_index*8=0xb18 __va+index==pte=ffff88000c934b18

	*pte=0x80000000222e3047 *pte&MASK=0x222e3000 pte_pfn=222e3 pfn=222e3
	vmemmap=ffffea0000000000 pfn*sizeof(page)=0x77a1a8 cal_page=ffffea000077a1a8==follow_page

	ABCDEFGHIJKL1234567890!@#$%^&*()KKKKKKKKKKKKKKKKKKK
	test exit
```



-----------------

#### dfs all vma, 虚拟地址连续，物理地址不连续

```
	...
	mmap(NULL, 8192, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x7f90fd1e3000
	...
```

```
	#include <linux/module.h>
	#include <linux/kernel.h>
	#include <linux/init.h> 
	#include <linux/types.h>

	#include <linux/sysctl.h>
	#include <linux/timer.h>
	#include <linux/hardirq.h>
	#include <linux/bottom_half.h>
	#include <linux/preempt.h>

	#include <linux/types.h>
	#include <linux/proc_fs.h>
	#include <linux/file.h> 

	#include <linux/kprobes.h>

	#include <linux/mm.h>   
	#include <linux/mm_types.h>

	#define N 10000000
	char ch[N];

	void dfs(struct rb_node *rb)
	{
		struct page *(*follow_page_p)(struct vm_area_struct *vma, unsigned long address, unsigned int flags)
			= (struct page *(*)(struct vm_area_struct *vma, unsigned long address, unsigned int flags))0xffffffff81133ab0;
		struct vm_area_struct *vma;
		unsigned long start, end, addr = 0x7f90fd1e3000;
		struct page *pa;
		if (!rb)
			return;
		vma = rb_entry(rb, struct vm_area_struct, vm_rb);
		start = vma->vm_start;
		end = vma->vm_end;
		if (addr >= start && addr < end && end-start <= N) {
			pa = follow_page_p(vma, addr, 0);
			if (pa) {
				memcpy(ch, page_address(pa), 4096);
				printk("page=%p ch=%s\n", pa, ch);
			}

			pa = follow_page_p(vma, addr+4096, 0);
			if (pa) {
				memcpy(ch, page_address(pa), 4096);
				printk("page=%p ch=%s\n", pa, ch);
			}
		}
		dfs(rb->rb_left);
		dfs(rb->rb_right);
	}

	static int __init test_init(void)
	{
		struct mm_struct *mm = (struct mm_struct*)0xffff8800303a3880;
		printk("test start task->mm=%p\n", mm->mm_rb.rb_node);
		dfs(mm->mm_rb.rb_node);
		return 0;
	}


	static void __exit test_exit(void)
	{
		printk("test exit\n");
	}

	module_init(test_init);
	module_exit(test_exit);

	MODULE_LICENSE("GPL");
```

```
	test start task->mm=ffff88002cc05e40
	page=ffffea000066e618 ch=ABCDEFGHIJKL1234567890!@#$%^&*()KKKKKKKKKKKKKKKKKKK
	page=ffffea000062bec0 ch=AAAAAAAAAAAAAAAAAAABBBBBBBBBBBBCCCCCCCCCCC
	test exit
```

