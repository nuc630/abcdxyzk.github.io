---
layout: post
title: "Linux内存管理"
date: 2015-06-02 15:05:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~mm
tags:
---
http://blog.csdn.net/myarrow/article/details/8624687

http://blog.csdn.net/myarrow/article/details/8682819

#### 1. Linux物理内存三级架构

![](/images/kernel/2015-06-02-20.png)  

对于内存管理，Linux采用了与具体体系架构不相关的设计模型，实现了良好的可伸缩性。它主要由内存节点node、内存区域zone和物理页框page三级架构组成。

##### 内存节点node

  内存节点node是计算机系统中对物理内存的一种描述方法，一个总线主设备访问位于同一个节点中的任意内存单元所花的代价相同，而访问任意两个不同节点中的内存单元所花的代价不同。在一致存储结构(Uniform Memory Architecture，简称UMA)计算机系统中只有一个节点，而在非一致性存储结构(NUMA)计算机系统中有多个节点。Linux内核中使用数据结构pg_data_t来表示内存节点node。如常用的ARM架构为UMA架构。

##### 内存区域zone

  内存区域位于同一个内存节点之内，由于各种原因它们的用途和使用方法并不一样。如基于IA32体系结构的个人计算机系统中，由于历史原因使得ISA设备只能使用最低16MB来进行DMA传输。又如，由于Linux内核采用

 • 物理页框page

#### 2. Linux虚拟内存三级页表

Linux虚拟内存三级管理由以下三级组成：  
 • PGD: Page Global Directory (页目录)  
 • PMD: Page Middle Directory (页目录)  
 • PTE:  Page Table Entry     (页表项)  

每一级有以下三个关键描述宏：  
 • SHIFT  
 • SIZE  
 • MASK  

如页的对应描述为：
```
	/* PAGE_SHIFT determines the page size  asm/page.h */  
	#define PAGE_SHIFT      12  
	#define PAGE_SIZE       (_AC(1,UL) << PAGE_SHIFT)  
	#define PAGE_MASK       (~(PAGE_SIZE-1))  
```

数据结构定义如下：
```
	/* asm/page.h */  
	typedef unsigned long pteval_t;  

	typedef pteval_t pte_t;  
	typedef unsigned long pmd_t;  
	typedef unsigned long pgd_t[2];  
	typedef unsigned long pgprot_t;  

	#define pte_val(x)      (x)  
	#define pmd_val(x)      (x)  
	#define pgd_val(x)  ((x)[0])  
	#define pgprot_val(x)   (x)  

	#define __pte(x)        (x)  
	#define __pmd(x)        (x)  
	#define __pgprot(x)     (x)  
```
 
##### 2.1 Page Directory (PGD and PMD)

  每个进程有它自己的PGD( Page Global Directory)，它是一个物理页，并包含一个pgd_t数组。其定义见<asm/page.h>。 进程的pgd_t数据见 task_struct -> mm_struct -> pgd_t * pgd;    

  ARM架构的PGD和PMD的定义如下<arch/arm/include/asm/pgtable.h>：
```
	#define PTRS_PER_PTE  512    // PTE中可包含的指针<u32>数 (21-12=9bit)  
	#define PTRS_PER_PMD  1  
	#define PTRS_PER_PGD  2048   // PGD中可包含的指针<u32>数 (32-21=11bit)</p><p>#define PTE_HWTABLE_PTRS (PTRS_PER_PTE)  
	#define PTE_HWTABLE_OFF  (PTE_HWTABLE_PTRS * sizeof(pte_t))  
	#define PTE_HWTABLE_SIZE (PTRS_PER_PTE * sizeof(u32))
	/*  
	 * PMD_SHIFT determines the size of the area a second-level page table can map  
	 * PGDIR_SHIFT determines what a third-level page table entry can map  
	 */  
	#define PMD_SHIFT  21  
	#define PGDIR_SHIFT  21
```

虚拟地址SHIFT宏图：

![](/images/kernel/2015-06-02-21.png)  

虚拟地址MASK和SIZE宏图：

![](/images/kernel/2015-06-02-22.png)  


##### 2.2 Page Table Entry

PTEs, PMDs和PGDs分别由pte_t, pmd_t 和pgd_t来描述。为了存储保护位，pgprot_t被定义，它拥有相关的flags并经常被存储在page table entry低位(lower bits)，其具体的存储方式依赖于CPU架构。

每个pte_t指向一个物理页的地址，并且所有的地址都是页对齐的。因此在32位地址中有PAGE_SHIFT(12)位是空闲的，它可以为PTE的状态位。

PTE的保护和状态位如下图所示：

![](/images/kernel/2015-06-02-23.png)  

##### 2.3 如何通过3级页表访问物理内存
为了通过PGD、PMD和PTE访问物理内存，其相关宏在asm/pgtable.h中定义。

• pgd_offset 

根据当前虚拟地址和当前进程的mm_struct获取pgd项的宏定义如下： 
```
	/* to find an entry in a page-table-directory */  
	#define pgd_index(addr)     ((addr) >> PGDIR_SHIFT)  //获得在pgd表中的索引  

	#define pgd_offset(mm, addr)    ((mm)->pgd + pgd_index(addr)) //获得pmd表的起始地址  

	/* to find an entry in a kernel page-table-directory */  
	#define pgd_offset_k(addr)  pgd_offset(&init_mm, addr)  
```

• pmd_offset

根据通过pgd_offset获取的pgd 项和虚拟地址，获取相关的pmd项(即pte表的起始地址) 
```
	/* Find an entry in the second-level page table.. */  
	#define pmd_offset(dir, addr)   ((pmd_t *)(dir))   //即为pgd项的值  
```

• pte_offset

  根据通过pmd_offset获取的pmd项和虚拟地址，获取相关的pte项(即物理页的起始地址)
```
	#ifndef CONFIG_HIGHPTE  
	#define __pte_map(pmd)      pmd_page_vaddr(*(pmd))  
	#define __pte_unmap(pte)    do { } while (0)  
	#else  
	#define __pte_map(pmd)      (pte_t *)kmap_atomic(pmd_page(*(pmd)))  
	#define __pte_unmap(pte)    kunmap_atomic(pte)  
	#endif  

	#define pte_index(addr)     (((addr) >> PAGE_SHIFT) & (PTRS_PER_PTE - 1))  

	#define pte_offset_kernel(pmd,addr) (pmd_page_vaddr(*(pmd)) + pte_index(addr))  

	#define pte_offset_map(pmd,addr)    (__pte_map(pmd) + pte_index(addr))  
	#define pte_unmap(pte)          __pte_unmap(pte)  

	#define pte_pfn(pte)        (pte_val(pte) >> PAGE_SHIFT)  
	#define pfn_pte(pfn,prot)   __pte(__pfn_to_phys(pfn) | pgprot_val(prot))  

	#define pte_page(pte)       pfn_to_page(pte_pfn(pte))  
	#define mk_pte(page,prot)   pfn_pte(page_to_pfn(page), prot)  

	#define set_pte_ext(ptep,pte,ext) cpu_set_pte_ext(ptep,pte,ext)  
	#define pte_clear(mm,addr,ptep) set_pte_ext(ptep, __pte(0), 0)  
```
其示意图如下图所示：

![](/images/kernel/2015-06-02-24.png)  

##### 2.4 根据虚拟地址获取物理页的示例代码

  根据虚拟地址获取物理页的示例代码详见<mm/memory.c中的函数follow_page>。

```
	/** 
	 * follow_page - look up a page descriptor from a user-virtual address 
	 * @vma: vm_area_struct mapping @address 
	 * @address: virtual address to look up 
	 * @flags: flags modifying lookup behaviour 
	 * 
	 * @flags can have FOLL_ flags set, defined in <linux/mm.h> 
	 * 
	 * Returns the mapped (struct page *), %NULL if no mapping exists, or 
	 * an error pointer if there is a mapping to something not represented 
	 * by a page descriptor (see also vm_normal_page()). 
	 */  
	struct page *follow_page(struct vm_area_struct *vma, unsigned long address,  
			    unsigned int flags)  
	{  
		pgd_t *pgd;  
		pud_t *pud;  
		pmd_t *pmd;  
		pte_t *ptep, pte;  
		spinlock_t *ptl;  
		struct page *page;  
		struct mm_struct *mm = vma->vm_mm;  

		page = follow_huge_addr(mm, address, flags & FOLL_WRITE);  
		if (!IS_ERR(page)) {  
			BUG_ON(flags & FOLL_GET);  
			goto out;  
		}  

		page = NULL;  
		pgd = pgd_offset(mm, address);  
		if (pgd_none(*pgd) || unlikely(pgd_bad(*pgd)))  
			goto no_page_table;  

		pud = pud_offset(pgd, address);  
		if (pud_none(*pud))  
			goto no_page_table;  
		if (pud_huge(*pud) && vma->vm_flags & VM_HUGETLB) {  
			BUG_ON(flags & FOLL_GET);  
			page = follow_huge_pud(mm, address, pud, flags & FOLL_WRITE);  
			goto out;  
		}  
		if (unlikely(pud_bad(*pud)))  
			goto no_page_table;  

		pmd = pmd_offset(pud, address);  
		if (pmd_none(*pmd))  
			goto no_page_table;  
		if (pmd_huge(*pmd) && vma->vm_flags & VM_HUGETLB) {  
			BUG_ON(flags & FOLL_GET);  
			page = follow_huge_pmd(mm, address, pmd, flags & FOLL_WRITE);  
			goto out;  
		}  
		if (pmd_trans_huge(*pmd)) {  
			if (flags & FOLL_SPLIT) {  
			    split_huge_page_pmd(mm, pmd);  
			    goto split_fallthrough;  
			}  
			spin_lock(&mm->page_table_lock);  
			if (likely(pmd_trans_huge(*pmd))) {  
			    if (unlikely(pmd_trans_splitting(*pmd))) {  
			        spin_unlock(&mm->page_table_lock);  
			        wait_split_huge_page(vma->anon_vma, pmd);  
			    } else {  
			        page = follow_trans_huge_pmd(mm, address,  
			                         pmd, flags);  
			        spin_unlock(&mm->page_table_lock);  
			        goto out;  
			    }  
			} else  
			    spin_unlock(&mm->page_table_lock);  
			/* fall through */  
		}  
	split_fallthrough:  
		if (unlikely(pmd_bad(*pmd)))  
			goto no_page_table;  

		ptep = pte_offset_map_lock(mm, pmd, address, &ptl);  

		pte = *ptep;  
		if (!pte_present(pte))  
			goto no_page;  
		if ((flags & FOLL_WRITE) && !pte_write(pte))  
			goto unlock;  

		page = vm_normal_page(vma, address, pte);  
		if (unlikely(!page)) {  
			if ((flags & FOLL_DUMP) ||  
			    !is_zero_pfn(pte_pfn(pte)))  
			    goto bad_page;  
			page = pte_page(pte);  
		}  

		if (flags & FOLL_GET)  
			get_page(page);  
		if (flags & FOLL_TOUCH) {  
			if ((flags & FOLL_WRITE) &&  
			    !pte_dirty(pte) && !PageDirty(page))  
			    set_page_dirty(page);  
			/* 
			 * pte_mkyoung() would be more correct here, but atomic care 
			 * is needed to avoid losing the dirty bit: it is easier to use 
			 * mark_page_accessed(). 
			 */  
			mark_page_accessed(page);  
		}  
		if ((flags & FOLL_MLOCK) && (vma->vm_flags & VM_LOCKED)) {  
			/* 
			 * The preliminary mapping check is mainly to avoid the 
			 * pointless overhead of lock_page on the ZERO_PAGE 
			 * which might bounce very badly if there is contention. 
			 * 
			 * If the page is already locked, we don't need to 
			 * handle it now - vmscan will handle it later if and 
			 * when it attempts to reclaim the page. 
			 */  
			if (page->mapping && trylock_page(page)) {  
			    lru_add_drain();  /* push cached pages to LRU */  
			    /* 
			     * Because we lock page here and migration is 
			     * blocked by the pte's page reference, we need 
			     * only check for file-cache page truncation. 
			     */  
			    if (page->mapping)  
			        mlock_vma_page(page);  
			    unlock_page(page);  
			}  
		}  
	unlock:  
		pte_unmap_unlock(ptep, ptl);  
	out:  
		return page;  

	bad_page:  
		pte_unmap_unlock(ptep, ptl);  
		return ERR_PTR(-EFAULT);  

	no_page:  
		pte_unmap_unlock(ptep, ptl);  
		if (!pte_none(pte))  
			return page;  

	no_page_table:  
		/* 
		 * When core dumping an enormous anonymous area that nobody 
		 * has touched so far, we don't want to allocate unnecessary pages or 
		 * page tables.  Return error instead of NULL to skip handle_mm_fault, 
		 * then get_dump_page() will return NULL to leave a hole in the dump. 
		 * But we can only make this optimization where a hole would surely 
		 * be zero-filled if handle_mm_fault() actually did handle it. 
		 */  
		if ((flags & FOLL_DUMP) &&  
			(!vma->vm_ops || !vma->vm_ops->fault))  
			return ERR_PTR(-EFAULT);  
		return page;  
	}
```

-------------

#### 1. First Fit分配器

  First Fit分配器是最基本的内存分配器，它使用bitmap而不是空闲块列表来表示内存。在bitmap中，如果page对应位为1，则表示此page已经被分配，为0则表示此page没有被分配。为了分配小于一个page的内存块，First Fit分配器记录了最后被分配的PFN (Page Frame Number)和分配的结束地址在页内的偏移量。随后小的内存分配被Merge到一起并存储到同一页中。

  First Fit分配器不会造成严重的内存碎片，但其效率较低，由于内存经常通过线性地址进行search，而First Fit中的小块内存经常在物理内存的开始处，为了分配大块内存而不得不扫描前面大量的内存。

#### 2. Boot Memory分配器

  物理内存分配器如何分配内存来初始化其自己呢？

  答案是：通过Boot Memory分配器来实现，而Boot Memory分配器则通过最基本的First Fit分配器来实现。

##### 2.1 Boot Map定义 

  Boot Map通过数据结构bootmem_data来定义，详见<linux/bootmem.h>，其定义如下所示： 

```
	typedef struct bootmem_data {  
		unsigned long node_boot_start; // 描述的物理内存的起始地址  
		unsigned long node_low_pfn;    // 结束物理地址，即ZONE_NORMAL的结束  
		void *node_bootmem_map;        // 描述“使用或空闲的位图”的地址  
		unsigned long last_offset;     // 最后被分配的页内偏移量，即在llast_pos描述的物理页中，  
			                         // 从last_offset开始，没有被分配   
		unsigned long last_pos;        // 最后被分配的页的PFN  
	} bootmem_data_t;  
```

所有bootmem_data被放于全局变量bdata_list中。

##### 2.2 Boot Memory分配器初始化

  每一个CPU架构被要求提供setup_arch函数，它负责获取初始化boot memory分配器的必要参数。不同的CPU架构通过不同的函数来实现，如ARM通过bootmem_init来实现。它负责获取以下参数：
```
	• min_low_pfn： 系统中可获得的最小的PFN，装载kernel image结束之后的第一页，在mm/bootmem.c中定义
	• max_low_pfn：低端内存(ZONE_NORMAL)中可获得的最大PFN
	• highstart_pfn：高端内存(ZONE_HIGHMEM)的起始PFN
	• highend_pfn：高端内存(ZONE_HIGHMEM)的结束PFN
	• max_pfn：系统中可获得的最大的PFN， 在mm/bootmem.c中定义
```

PFN是在物理内存map的偏移量，以page为单位。Kernel可直接访问ZONE_NORMAL，其偏移量为：PAGE_OFFSET。

通过以上5个参数明确了可用物理内存之后，调用init_bootmem->init_bootmem_core来初始化contig_page_data。它主要完成以下两件事：  
  1) 将把与此node对应pgdat_data_t插入到pgdat_list中  
  2) 初始化bootmem_data_t的中参数，并分配表示页分配状态的bitmap，其大小为: (end_pfn-start_pfn+7)/8  

bitmap的物理地址为：bootmem_data_t->node_boot_start  
bitmap的虚拟地直为：bootmem_data_t->node_bootmem_map  

##### 2.3 分配内存
 • reserve_bootmem：用于预留物理页面。但用于通用的内存分配是低率的，它主要用于各种驱动(如：Video Codec)预留内存。

常用的内存分配函数如下(in UMA架构，我们常的ARM架构为UMA架构)：
```
	• alloc_bootmem
	• alloc_bootmem_low
	• alloc_bootmem_pages
	• alloc_bootmem_low_pages
```

其调用关系如下图所示：

###### 2.3.1 `__alloc_bootmem`

`__alloc_bootmem()` 需要以下参数：  
 • pgdat 用于分配内存块的节点，在UMA架构中，它被忽略，因为它总是为：contig_page_data  
 • size  指定请求分配的内存大小，以字节为单位  
 • align 请求以多少字节对齐，地于小块内存分配，一般以SMP_CACHE_BYTES对齐，如在X86上，与L1硬件cache对齐  
 • goal  偏好的分配内存的起始地址,  

###### 2.3.2 __alloc_bootmem_core

它从goal指定的地址开始，线性地扫描内存，以寻找可以满足内存分配要求的内存块。它的另外一项功能是决定是否需要把新分配的内存块与以前已经分配的内存块merge到一起。

分配内存常用函数定义如下： 

```
	#ifdef CONFIG_NO_BOOTMEM  
	/* We are using top down, so it is safe to use 0 here */  
	#define BOOTMEM_LOW_LIMIT 0  
	#else  
	#define BOOTMEM_LOW_LIMIT __pa(MAX_DMA_ADDRESS)  
	#endif  

	#define alloc_bootmem(x) \  
		__alloc_bootmem(x, SMP_CACHE_BYTES, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_align(x, align) \  
		__alloc_bootmem(x, align, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_nopanic(x) \  
		__alloc_bootmem_nopanic(x, SMP_CACHE_BYTES, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_pages(x) \  
		__alloc_bootmem(x, PAGE_SIZE, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_pages_nopanic(x) \  
		__alloc_bootmem_nopanic(x, PAGE_SIZE, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_node(pgdat, x) \  
		__alloc_bootmem_node(pgdat, x, SMP_CACHE_BYTES, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_node_nopanic(pgdat, x) \  
		__alloc_bootmem_node_nopanic(pgdat, x, SMP_CACHE_BYTES, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_pages_node(pgdat, x) \  
		__alloc_bootmem_node(pgdat, x, PAGE_SIZE, BOOTMEM_LOW_LIMIT)  
	#define alloc_bootmem_pages_node_nopanic(pgdat, x) \  
		__alloc_bootmem_node_nopanic(pgdat, x, PAGE_SIZE, BOOTMEM_LOW_LIMIT)  

	#define alloc_bootmem_low(x) \  
		__alloc_bootmem_low(x, SMP_CACHE_BYTES, 0)  
	#define alloc_bootmem_low_pages(x) \  
		__alloc_bootmem_low(x, PAGE_SIZE, 0)  
	#define alloc_bootmem_low_pages_node(pgdat, x) \  
		__alloc_bootmem_low_node(pgdat, x, PAGE_SIZE, 0)  
```

##### 2.4 释放内存

调用free_bootmem来释放内存。
```
	void __init free_bootmem(unsigned long addr, unsigned long size)  
	{  
		unsigned long start, end;  

		kmemleak_free_part(__va(addr), size);  

		start = PFN_UP(addr);  
		end = PFN_DOWN(addr + size);  

		mark_bootmem(start, end, 0, 0);  
	}
```

