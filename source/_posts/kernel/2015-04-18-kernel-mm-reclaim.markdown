---
layout: post
title: "Linux内存管理--内存回收"
date: 2015-04-18 23:01:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~mm
tags:
---
os.51cto.com/art/201310/412758_all.htm

  内存的回收在Linux内存管理中占据非常重要的地位，系统的内存毕竟是有限的，跑的进程成百上千，系统内存越来越小，我们必须选择一些内存进行回收，以满足别的任务的需求。在内存回收过程中，有哪些内存可以回收，什么时候进行回收，回收内存时如何尽可能的减少对系统性能的影响，回收内存的策略，这些是我们着重要关注的问题，也是本文主要阐述的重点。

#### 1.1 内存回收的目标
不是所有的物理内存都可以参与回收的，比如要是把内核代码段的内存给回收了，系统就无法正常运行了，一般内核代码段，数据段，内核kmalloc()出来的内存，内核线程占用的内存等都是不可以回收的，除此之外的内存都是我们要回收的目标。

回收的内存主要是由用户态进程占用的内存和内核自己在运行时所使用的一些内存组成。用户态进程占用的内存主要是我们常见的进程代码段，数据段，堆栈等，内核运行使用的内存主要是磁盘高速缓存(如索引节点，目录项高速缓存），页面高速缓存(访问文件时系统生成的页面cache)，mmap()文件时所用的有名映射所使用的物理内存。后面的这些内才能虽然也是内核管理使用的内存，但对其进行回收的时候，顶多影响内核的性能，而不会导致系统无法运行。

#### 1.2 内存回收的时机
1、内存紧缺回收：grow_buffers()无法获取缓冲区页，alloc_page_buffers()无法获取页临时缓冲区首部，__alloc_pages()无法再给定的内存区分配一组连续页框。

2、周期回收：必要时，激活相应内核线程执行内存回收算法：kswapd()内核线程，检查某个内存管理区的空闲页框数是否已低于pages_high值的标高。events内核线程，一个工作者线程，回收位于高速内存缓存中的所有空闲的slab。

#### 1.3 内存回收的策略

##### 1.3.1 内存回收的分类
内存回收主要是要回收两类内存：最近最少使用的内存以及高速内存缓存中空闲的slab。前者主要包括用户态进程的代码段，数据段，堆栈，文件映射内存，页高速内存，后者主要包括磁盘高速缓存及一些其他的空闲内存高速缓存。

最近最少使用内存存放在一个lru链表上，每个内存管理区zone都有一个lru结构，里面含有active和inactive两个链表头，active链表上记录当前的活跃的报文，inactive用来记录当前不活跃的报文。一般我们回首lru上的inactive链表上的内存页。同时，在内存回收的过程中，会从active链表向inactive链表上补充对应的最近最少使用内存页。每个内存页的内核数据结构page上有一个标记位PG_referenced,该标记位使得一个页从"不活动“状态转为”活动“状态的时间加倍，反之亦然。比如:一个页面可能1个小时内没人反应，不能因为偶然的一次访问就认为它是活跃的，得两次才认为它是一个活跃的页面。下面是页面在inactive和active链表上转移的变化图。

Slab内存高速缓存中经常会有一些完全空闲的slab，这些是我们回收的另一个目标。

##### 1.3.2 反向映射
对于可以通过用户态线性地址空间可以直接访问到的物理页来说，可以分为匿名页和文件映射页两类，匿名页指的是不与具体文件对应映射的物理页，比如代码段，堆栈等使用的物理页，映射页指的是映射到文件某一部分的物理页，通常使用mmap()来进行相关的映射。

对于匿名映射和文件映射来说，可能一段物理内存会在多个进程的页表中使用，比如对于匿名映射，fork()一个进程，一开始会共用父进程的物理内存，对于文件映射，多个进程可能同时映射到一个文件的同一部分文件。所以在页面回收时，需要将该页面在所有的页表引用中给去除掉。这种手段称为反向映射。想要找到使用这些物理页的页表项的话，需要先找到引用他们的页表，而页表的地址记录在每个进程的内存描述符里面，同时用来描述进程用户态地址空间的每个vm_area_struct都记录了一个指针，指向所属的内存描述符。因此只要通过物理页找到引用他们的vm_area_struct,就能找到内存描述符，从而找到页表，找到对应的页表项。

匿名页的反向映射：

对于匿名页来说，每个页面的mapping字段指向一个anon_vma描述符，anon_vma描述符中存在一个链表头，所有引用该页面的vm_area_struct都存放在里面。page,anon_vma,vm_area_struct这些数据结构的关系如下图所示：

对于匿名页来说，其被别的地址空间引用，基本上都是因为fork（）进程时，子进程复制父进程的地址空间，从而被引用的。各个vm_area_struct加入anon_vma的链表的过程如下：

假设当前一个进程p，后来fork出一个子进程c。

1、当进程P为某个vm_area_struct加入第一个物理页时，比如说发生了缺页异常，动态分配一个anon_vma的数据结构，将vm_area_struct加入该anon_vma所管理的链表，vm_area_struct结构中的anon_vma字段指向该anon_vma,同时把该页面中的mapping字段赋值为该anon_vma.对于后续为该vm_area_struct申请的物理页面，其mapping字段都赋值为该anon_vma。

2、当该进程p执行fork()时，在fork的处理过程中，会调用dup_mmap()来复制进程p的线性地址空间，在dup_mmap()会复制进程p的每一个vm_area_struct，加入到自己的地址空间中，并将vm_area_struct加入到anon_vma所管理的链表中，参看anon_vma_link()。此时为进程p申请的页面被进程c共享，通过页面的mapping字段可以找到anon_vma，从anon_vma可以遍历进程p,c。

3、考虑一个问题，在进程c中才触发缺页异常被申请的内存页，其mmapping被赋值为所属vm_area_struct的vma_anon，但进程p并没有使用到该页，所以一个物理页mapping字段指向的vma_anon所下挂的vm_area_struct可能并不包含该物理页。

文件映射页的反向映射：

对于每个文件映射页，其page mapping字段指向的是对应文件的address_space数据结构，address_space中有个 struct prio_tree_root i_mmap 字段，指向一个优先树，优先树里面会把所有映射该文件内容的vm_area_struct 给组织起来。在该树中，其树的节点基地址和堆地址分别是映射的文件内容的起始地址和结束地址，要是多个进程同时映射该地址段，会用链表在该节点上将vm_area_struct串起来。

##### 1.3.3 内存回收流程介绍
睡眠回收我们不关注，主要介绍内存紧缺回收及周期回收：

1、内存紧缺回收主要函数是try_to_free_pages()，该函数会执行一个循环，按照优先级从12到0，依次调用shrink_caches()，shrink_slab()来回收页面，直到回收至少32个内存页面。

依次调用以下辅助函数：

shrink_caches()：调用shrink_zone()对传入的zone链表中的每个zone，进行lru上面的页面回收。

shrink_slab()：对磁盘索引节点cache和目录项索引节点等磁盘高速缓存进行回收，由于磁盘索引节点和目录项索引节点都是从slab高速缓存中分配的，这样就会导致空闲slab的产生，空闲slab后续会在周期性回收的cache_reap工作队列中被回收。估计也就是因为最终会清零空闲slab，才会起这么一个函数名。^_^

shrink_zone()：对内存管理区上的lru链表中的非活跃页面进行回收，在非活跃页面不足的时候，调用refill_inactive_zone()对lru上的inactive链表补充非活跃页面,同时shrink_zone()调用shrink_cache()来进行页面的回收，该函数的具体解析可以参照下面的源码浅析。

shrink_list()：该辅助函数在shrink_cache()中被调用，该函数对在shrink_cache（）中传入的非活跃page列表进行遍历，对每个页面进行回收工作，该函数的具体解析可以参考下面的源码解析。

refill_inactie_zone()：该辅助函数根据一定的规则将处于lru active链表上的活跃页面移动到inactive链表上，以补充可以回收的页面，在lru链表里有两类页，一类是属于用户态空间的页，比如用户态进程的代码段，数据段，一类是在页高速缓存中的页，系统为了降低对应用程序的影响，将要优先将页高速缓存页进行回收，同时为了系统整体性能也会适当回收用户态进程页。按照如下经验公式进行选择：

交换倾向值=映射比率/2+负荷值+交换值

2、kswapd进程一般会在系统中睡眠，但当__alloc_page()发现各个管理区的剩余页面都低于警告值(由内存管理描述符的pages_low字段和protection字段推算出来)时，会激活kswapd进程进行页面回收，直到回收的页面使得管理区的剩余页面高于zone->pages_high时才停止回收，本质上也是调用了shrink_zone（）和shrink_slab()。

3、cache_reap工作队列定期运行来回收slab高速缓存中空闲的slab占用的页。

#### 1.4 相关源代码的浅析
```
	static void 
	shrink_zone(struct zone *zone, struct scan_control *sc) 
	{ 
		unsigned long nr_active; 
		unsigned long nr_inactive; 

		//根据优先级，得到可以扫描的页面数，优先级越高， 
		//代表越不急迫，可以扫描的页面数也最少 
		zone->nr_scan_active += (zone->nr_active >> sc->priority) + 1; 
		nr_active = zone->nr_scan_active; 
		if (nr_active >= SWAP_CLUSTER_MAX) 
			zone->nr_scan_active = 0; 
		else 
			nr_active = 0; 

		zone->nr_scan_inactive += (zone->nr_inactive >> sc->priority) + 1; 
		nr_inactive = zone->nr_scan_inactive; 
		//非活动页比较少的话，可以先忽略过去，将跳过的页面记录到nr_scan_inactive中 
		//留待下一次再处理 
		if (nr_inactive >= SWAP_CLUSTER_MAX) 
			zone->nr_scan_inactive = 0; 
		else 
			nr_inactive = 0; 

		//设置需要回收的页面数为32个 
		sc->nr_to_reclaim = SWAP_CLUSTER_MAX; 

		//开始回收页面，每次扫描32个页面，多了不干噢!!! 
		while (nr_active || nr_inactive) { 
			if (nr_active) { 
				//设置每次要扫描的非活动页面数，需要将其放 
				//入到inactive list里面 
				sc->nr_to_scan = min(nr_active, 
				(unsigned long)SWAP_CLUSTER_MAX); 
				nr_active -= sc->nr_to_scan; 
				//补充inactive list中的页面 
				refill_inactive_zone(zone, sc); 
			} 

			if (nr_inactive) { 
				//设置每次将要扫描的页面，最多也就32个页面 
				sc->nr_to_scan = min(nr_inactive, 
				(unsigned long)SWAP_CLUSTER_MAX); 

				nr_inactive -= sc->nr_to_scan; 
				//开始正式回收inactive list中的页面 
				shrink_cache(zone, sc); 
				//32个页面被回收完毕，大功告成了!!! 
				if (sc->nr_to_reclaim <= 0) 
					break; 
			}
		} 
	} 

	static int shrink_list(struct list_head *page_list, struct scan_control *sc) 
	{ 
		LIST_HEAD(ret_pages);
		struct pagevec freed_pvec;
		int pgactivate = 0;
		int reclaimed = 0;
		//有进程需要调度，先进行调度 
		cond_resched();

		pagevec_init(&freed_pvec, 1); 
		//对于page_list 链表上的每一个页面试图进行回收 
		while (!list_empty(page_list)) { 
			struct address_space *mapping; 
			struct page *page; 
			int may_enter_fs; 
			int referenced; 

			//获取一个页面 
			page = lru_to_page(page_list); 
			//从lru上摘除 
			list_del(&page->lru); 
			//page被锁定，不能回收 
			if (TestSetPageLocked(page))//page is locked? 
				goto keep; 

			BUG_ON(PageActive(page)); 
			//page正在被writeback，不能回收 
			if (PageWriteback(page))//page is writeback? 
				goto keep_locked; 

			sc->nr_scanned++; 
			/* Double the slab pressure for mapped and swapcache pages */ 

			if (page_mapped(page) || PageSwapCache(page)) 
				sc->nr_scanned++; 
			//查看最近该页面有无被访问过 
			referenced = page_referenced(page, 1, sc->priority <= 0); 
			/* In active use or really unfreeable?  Activate it. */ 
			//1页面被访问过，2页面在用户态空间，页面是文件映射页面， 
			//页面在交换高速缓存中，同时满足这两个条件的话，页面不被回收 
			if (referenced && page_mapping_inuse(page)) 
				goto activate_locked; 

			#ifdef CONFIG_SWAP
			//page is anon and page has not been add to swapcache 
			//该页面是匿名映射的页面，且该页面不在swapcache中 
			if (PageAnon(page) && !PageSwapCache(page)) { 
				//将页面加入到swap cache中 
				if (!add_to_swap(page)) 
					goto activate_locked; 
			}
			#endif /* CONFIG_SWAP */ 
			//得到对应的address_space，有可能是对应文件的address_space,或者是 
			//swap cache的address_space 
			mapping = page_mapping(page); 
			may_enter_fs = (sc->gfp_mask & __GFP_FS) || 
					(PageSwapCache(page) && (sc->gfp_mask & __GFP_IO)); 

			//该页面被映射到某个用户页表中 
			if (page_mapped(page) && mapping) { 
				//将该页面在用户页表中的页表项通通清除 
				switch (try_to_unmap(page)) { 
					case SWAP_FAIL: 
					goto activate_locked; 
					case SWAP_AGAIN: 
					goto keep_locked; 
					case SWAP_SUCCESS: 
					; /* try to free the page below */ 
				} 
			} 
			//页面是脏的，哈哈，准备往文件或swapcache里面写硬盘吧 
			if (PageDirty(page)) { 
				if (referenced) 
					goto keep_locked; 
				if (!may_enter_fs) 
					goto keep_locked; 
				if (laptop_mode && !sc->may_writepage) 
					goto keep_locked; 

				/* Page is dirty, try to write it out here */ 
				//往磁盘上写页面 
				switch(pageout(page, mapping)) { 
					case PAGE_KEEP: 
						goto keep_locked; 
					case PAGE_ACTIVATE: 
						goto activate_locked; 
					case PAGE_SUCCESS: 
						if (PageWriteback(page) || PageDirty(page)) 
							goto keep; 

						if (TestSetPageLocked(page)) 
							goto keep; 
						if (PageDirty(page) || PageWriteback(page)) 
							goto keep_locked; 
						mapping = page_mapping(page); 
					case PAGE_CLEAN: 
						; /* try to free the page below */ 
				} 
			}

			//若页面是缓冲区页面，将对应的buffer_head给释放掉 
			if (PagePrivate(page)) { 
				if (!try_to_release_page(page, sc->gfp_mask)) 
					goto activate_locked; 
				if (!mapping && page_count(page) == 1) 
					goto free_it; 
			} 

			if (!mapping) 
				goto keep_locked; 
			/* truncate got there first */ 

			spin_lock_irq(&mapping->tree_lock); 

			//页面为脏页面或者page的引用计数为2，都是不可以回收的  
			if (page_count(page) != 2 || PageDirty(page)) { 
				spin_unlock_irq(&mapping->tree_lock); 
				goto keep_locked; 
			}

			#ifdef CONFIG_SWAP 
				//到达这里，说明该page只被swap cache或者页高速缓存及 
				//fpra所共有，需要将其从swap cache上或者页高速缓存上删除。 
			if (PageSwapCache(page)) { 
				swp_entry_t swap = { .val = page->private }; 
				//从swap cache上进行删除 
				__delete_from_swap_cache(page); 
				spin_unlock_irq(&mapping->tree_lock); 
				swap_free(swap); 
				__put_page(page); 
				/* The pagecache ref */ 
				goto free_it; 
			} 
			#endif /* CONFIG_SWAP */ 

			//从页面高速缓存中将该页面删除 
			__remove_from_page_cache(page); 
			spin_unlock_irq(&mapping->tree_lock); 
			__put_page(page); 

			free_it: 
				unlock_page(page); 
				reclaimed++; 
				if (!pagevec_add(&freed_pvec, page)) 
					__pagevec_release_nonlru(&freed_pvec); 
				continue; 

			activate_locked: 
				//将页面设为active页面，等回去将其放入lru的active链表 
				SetPageActive(page); 
				pgactivate++; 
			keep_locked: 
				//保持页面的状态不变，放入对应的lru active或inactive链表中 
				unlock_page(page); 
			keep: 
				//将该无法回收的页面，放入到ret_pages链表中 
				list_add(&page->lru, &ret_pages); 
				BUG_ON(PageLRU(page)); 
		} 
		//此处将无法回收的页面放入page_list中，在函数返回后，去其进行处理 
		list_splice(&ret_pages, page_list); 
		//此处将可以释放的页面通通给释放掉，回收了^_^ 

		if (pagevec_count(&freed_pvec)) 
			__pagevec_release_nonlru(&freed_pvec); 
		mod_page_state(pgactivate, pgactivate); 
		sc->nr_reclaimed += reclaimed; 
		return reclaimed; 
	}
```

