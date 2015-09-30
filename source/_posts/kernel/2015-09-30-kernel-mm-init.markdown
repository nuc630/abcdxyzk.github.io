---
layout: post
title: "kernel 3.10内核源码分析--内核页表创建"
date: 2015-09-30 15:53:00 +0800
comments: false
categories:
- 2015
- 2015~09
- kernel
- kernel~mm
tags:
---
http://blog.chinaunix.net/uid-20671208-id-4440253.html

内核页表创建基本流程：
```
	start_kernel
		setup_arch
			init_mem_mapping
				init_range_memory_mapping
					init_memory_mapping
						kernel_physical_mapping_init  
```

```
	/*
	  * 创建内核页表，将内核页表中能线性映射的部分(0-896M，还要刨去ISA等区域)
	  * 进行映射，创建相应的页表项，在内核初始化的时候(setup_arch())完成。
	  */
	unsigned long __init
	kernel_physical_mapping_init(unsigned long start,
				 unsigned long end,
				 unsigned long page_size_mask)
	{
		int use_pse = page_size_mask == (1<<PG_LEVEL_2M);
		unsigned long last_map_addr = end;
		unsigned long start_pfn, end_pfn;
		 /*内核页表页目录所在的位置，其所占的内存是在head_32.S中预先分配好的*/
		pgd_t *pgd_base = swapper_pg_dir;
		int pgd_idx, pmd_idx, pte_ofs;
		unsigned long pfn;
		pgd_t *pgd;
		pmd_t *pmd;
		pte_t *pte;
		unsigned pages_2m, pages_4k;
		int mapping_iter;
		/*计算欲映射区域的起始和结束pfn*/
		start_pfn = start >> PAGE_SHIFT;
		end_pfn = end >> PAGE_SHIFT;

		/*
		 * First iteration will setup identity mapping using large/small pages
		 * based on use_pse, with other attributes same as set by
		 * the early code in head_32.S
		 *
		 * Second iteration will setup the appropriate attributes (NX, GLOBAL..)
		 * as desired for the kernel identity mapping.
		 *
		 * This two pass mechanism conforms to the TLB app note which says:
		 *
		 * "Software should not write to a paging-structure entry in a way
		 * that would change, for any linear address, both the page size
		 * and either the page frame or attributes."
		 */
		mapping_iter = 1;

		if (!cpu_has_pse)
			use_pse = 0;

	repeat:
		pages_2m = pages_4k = 0;
		pfn = start_pfn;
		pgd_idx = pgd_index((pfn<<PAGE_SHIFT) + PAGE_OFFSET);
		/*
		 * pgd、pmd等存放的是本级页表中对应index项的虚拟地址，页表项的内容中存放的是
		 * 下一级页表的起始物理地址
		 */
		pgd = pgd_base + pgd_idx;
		for (; pgd_idx < PTRS_PER_PGD; pgd++, pgd_idx++) {
			//创建pmd，如果没有pmd，则返回pgd。实际通过get_free_page接口分配，此时buddy系统已经可用?
			pmd = one_md_table_init(pgd);

			if (pfn >= end_pfn)
				continue;
	#ifdef CONFIG_X86_PAE
			pmd_idx = pmd_index((pfn<<PAGE_SHIFT) + PAGE_OFFSET);
			pmd += pmd_idx;
	#else
			pmd_idx = 0;
	#endif
			for (; pmd_idx < PTRS_PER_PMD && pfn < end_pfn;
			 pmd++, pmd_idx++) {
				/*
				 * 页框虚拟地址，就是物理地址(pfn * PAGE_SIZE)+固定偏移
				 * 这就是线性映射的实质。
				*/
				unsigned int addr = pfn * PAGE_SIZE + PAGE_OFFSET;

				/*
				 * Map with big pages if possible, otherwise
				 * create normal page tables:
				 */
				if (use_pse) {
					unsigned int addr2;
					pgprot_t prot = PAGE_KERNEL_LARGE;
					/*
					 * first pass will use the same initial
					 * identity mapping attribute + _PAGE_PSE.
					 */
					pgprot_t init_prot =
						__pgprot(PTE_IDENT_ATTR |
							_PAGE_PSE);

					pfn &= PMD_MASK >> PAGE_SHIFT;
					addr2 = (pfn + PTRS_PER_PTE-1) * PAGE_SIZE +
						PAGE_OFFSET + PAGE_SIZE-1;

					if (is_kernel_text(addr) ||
					 is_kernel_text(addr2))
						prot = PAGE_KERNEL_LARGE_EXEC;

					pages_2m++;
					if (mapping_iter == 1)
						set_pmd(pmd, pfn_pmd(pfn, init_prot));
					else
						set_pmd(pmd, pfn_pmd(pfn, prot));

					pfn += PTRS_PER_PTE;
					continue;
				}
				// 创建页表
				pte = one_page_table_init(pmd);

				pte_ofs = pte_index((pfn<<PAGE_SHIFT) + PAGE_OFFSET);
				pte += pte_ofs;
				// 填写每项页表的内容。
				for (; pte_ofs < PTRS_PER_PTE && pfn < end_pfn;
				 pte++, pfn++, pte_ofs++, addr += PAGE_SIZE) {
					pgprot_t prot = PAGE_KERNEL;
					/*
					 * first pass will use the same initial
					 * identity mapping attribute.
					 */
					pgprot_t init_prot = __pgprot(PTE_IDENT_ATTR);

					if (is_kernel_text(addr))
						prot = PAGE_KERNEL_EXEC;

					pages_4k++;
					if (mapping_iter == 1) {
						// 将pfn(页框号)和相关属性转换为物理地址，然后写入pte中
						set_pte(pte, pfn_pte(pfn, init_prot));
						last_map_addr = (pfn << PAGE_SHIFT) + PAGE_SIZE;
					} else
						set_pte(pte, pfn_pte(pfn, prot));
				}
			}
		}
		if (mapping_iter == 1) {
			/*
			 * update direct mapping page count only in the first
			 * iteration.
			 */
			update_page_count(PG_LEVEL_2M, pages_2m);
			update_page_count(PG_LEVEL_4K, pages_4k);

			/*
			 * local global flush tlb, which will flush the previous
			 * mappings present in both small and large page TLB's.
			 */
			__flush_tlb_all();

			/*
			 * Second iteration will set the actual desired PTE attributes.
			 */
			mapping_iter = 2;
			goto repeat;
		}
		return last_map_addr;
```

swapper_pg_dir为内核页表页目录所在的位置，其所占的内存是在head_32.S中预先分配好的，从下面的汇编代码看，预先分配了1024*4=4k的空间，可以容纳1024个entry。

```
	ENTRY(swapper_pg_dir)
		.fill 1024,4,0
```
