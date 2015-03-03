---
layout: post
title: "Linux slab 分配器"
date: 2015-03-03 17:32:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~mm
tags:
---
[Linux Slab分配器(一)-概述](http://www.linuxidc.com/Linux/2012-06/62965.htm)  
[Linux Slab分配器(二)-初始化](http://www.linuxidc.com/Linux/2012-06/62966.htm)  
[Linux Slab分配器(三)-创建缓存](http://www.linuxidc.com/Linux/2012-06/63109.htm)  
[Linux Slab分配器(四)-分配对象](http://www.linuxidc.com/Linux/2012-06/63138.htm)  

## 一、概述
  slab分配器是Linux内存管理中非常重要和复杂的一部分，其工作是针对一些经常分配并释放的对象，如进程描述符等，这些对象的大小一般比较小，如果直接采用伙伴系统来进行分配和释放，不仅会造成大量的内碎片，而且处理速度也太慢。而slab分配器是基于对象进行管理的，相同类型的对象归为一类(如进程描述符就是一类)，每当要申请这样一个对象，slab分配器就从一个slab列表中分配一个这样大小的单元出去，而当要释放时，将其重新保存在该列表中，而不是直接返回给伙伴系统。slab分配对象时，会使用最近释放的对象内存块，因此其驻留在CPU高速缓存的概率较高。

##### 用于描述和管理cache的数据结构是struct kmem_cache
```
    struct kmem_cache {  
    /* 1) per-cpu data, touched during every alloc/free */  
        /*per-CPU数据，记录了本地高速缓存的信息，也用于跟踪最近释放的对象，每次分配和释放都要直接访问它*/  
        struct array_cache *array[NR_CPUS];   
    /* 2) Cache tunables. Protected by cache_chain_mutex */  
        unsigned int batchcount;  /*本地高速缓存转入或转出的大批对象数量*/  
        unsigned int limit;       /*本地高速缓存中空闲对象的最大数目*/  
        unsigned int shared;  

        unsigned int buffer_size;/*管理对象的大小*/  
        u32 reciprocal_buffer_size;/*buffer_size的倒数值*/  
    /* 3) touched by every alloc & free from the backend */  

        unsigned int flags;          /* 高速缓存的永久标识*/  
        unsigned int num;         /* 一个slab所包含的对象数目 */  

    /* 4) cache_grow/shrink */  
        /* order of pgs per slab (2^n) */  
        unsigned int gfporder;   /*一个slab包含的连续页框数的对数*/  

        /* force GFP flags, e.g. GFP_DMA */  
        gfp_t gfpflags;          /*与伙伴系统交互时所提供的分配标识*/  

        size_t colour;         /* 颜色的个数*/  
        unsigned int colour_off; /* 着色的偏移量 */  

        /*如果将slab描述符存储在外部，该指针指向存储slab描述符的cache, 
          否则为NULL*/  
        struct kmem_cache *slabp_cache;  
        unsigned int slab_size;  /*slab管理区的大小*/  
        unsigned int dflags;     /*动态标识*/  

        /* constructor func */  
        void (*ctor)(void *obj); /*创建高速缓存时的构造函数指针*/  

    /* 5) cache creation/removal */  
        const char *name;         /*高速缓存名*/  
        struct list_head next;    /*用于将高速缓存链入cache chain*/  

    /* 6) statistics */  
    #ifdef CONFIG_DEBUG_SLAB /*一些用于调试用的变量*/   
        unsigned long num_active;  
        unsigned long num_allocations;  
        unsigned long high_mark;  
        unsigned long grown;  
        unsigned long reaped;  
        unsigned long errors;  
        unsigned long max_freeable;  
        unsigned long node_allocs;  
        unsigned long node_frees;  
        unsigned long node_overflow;  
        atomic_t allochit;  
        atomic_t allocmiss;  
        atomic_t freehit;  
        atomic_t freemiss;  

        /* 
         * If debugging is enabled, then the allocator can add additional 
         * fields and/or padding to every object. buffer_size contains the total 
         * object size including these internal fields, the following two 
         * variables contain the offset to the user object and its size. 
         */  
        int obj_offset;  
        int obj_size;  
    #endif /* CONFIG_DEBUG_SLAB */   

        /* 
         * We put nodelists[] at the end of kmem_cache, because we want to size 
         * this array to nr_node_ids slots instead of MAX_NUMNODES 
         * (see kmem_cache_init()) 
         * We still use [MAX_NUMNODES] and not [1] or [0] because cache_cache 
         * is statically defined, so we reserve the max number of nodes. 
         */  
         /*struct kmem_list3用于组织该高速缓存中的slab*/  
        struct kmem_list3 *nodelists[MAX_NUMNODES];  
        /* 
         * Do not add fields after nodelists[] 
         */  
    }; 
```

```
    struct kmem_list3 {  
        struct list_head slabs_partial;/*slab链表，包含空闲对象和已分配对象的slab描述符*/  
        struct list_head slabs_full;   /*slab链表，只包含非空闲的slab描述符*/  
        struct list_head slabs_free;   /*slab链表，只包含空闲的slab描述符*/  
        unsigned long free_objects;    /*高速缓存中空闲对象的个数*/  
        unsigned int free_limit;       /*空闲对象的上限*/  
        unsigned int colour_next;       /*下一个slab使用的颜色*/  
        spinlock_t list_lock;  
        struct array_cache *shared; /* shared per node */  
        struct array_cache **alien; /* on other nodes */  
        unsigned long next_reap;    /* updated without locking */  
        int free_touched;       /* updated without locking */  
    };  
```

##### 描述和管理单个slab的结构是struct slab
```
    struct slab {  
        struct list_head list;  /*用于将slab链入kmem_list3的链表*/  
        unsigned long colouroff;/*该slab的着色偏移*/  
        void *s_mem;            /*指向slab中的第一个对象*/  
        unsigned int inuse;     /*已分配出去的对象*/  
        kmem_bufctl_t free;     /*下一个空闲对象的下标*/  
        unsigned short nodeid;  /*节点标识号*/  
    };
```

<!-- more -->

  还要介绍的一个数据结构就是struct array_cache。struct kmem_cache中定义了一个struct array_cache指针数组，数组的元素个数对应了系统的CPU数，和伙伴系统中的每CPU页框高速缓存类似，该结构用来描述每个CPU的本地高速缓存，它可以减少SMP系统中对于自旋锁的竞争。在每个array_cache的末端都用一个指针数组记录了slab中的空闲对象，分配对象时，采用LIFO方式，也就是将该数组中的最后一个索引对应的对象分配出去，以保证该对象还驻留在高速缓存中的可能性。实际上，每次分配内存都是直接与本地CPU高速缓存进行交互，只有当其空闲内存不足时，才会从kmem_list中的slab中引入一部分对象到本地高速缓存中，而kmem_list中的空闲对象也不足了，那么就要从伙伴系统中引入新的页来建立新的slab了，这一点也和伙伴系统的每CPU页框高速缓存很类似。
```
    struct array_cache {  
        unsigned int avail;/*本地高速缓存中可用的空闲对象数*/  
        unsigned int limit;/*空闲对象的上限*/  
        unsigned int batchcount;/*一次转入和转出的对象数量*/  
        unsigned int touched;   /*标识本地CPU最近是否被使用*/  
        spinlock_t lock;  
        void *entry[];  /*这是一个伪数组，便于对后面用于跟踪空闲对象的指针数组的访问 
                 * Must have this definition in here for the proper 
                 * alignment of array_cache. Also simplifies accessing 
                 * the entries. 
                 */  
    };
```

slab分配器涉及到了一些繁杂的概念，这些在后面再逐一结合代码进行讲解，在理解slab分配器的工作之前，必须先理解上述这些数据结构之间的联系，下图给出了一个清晰的描述

![](/images/kernel/2015-03-03-11.png)


## 二、初始化
在前文中介绍了slab所涉及到的数据结构， slab分配器的初始化工作都是围绕这些数据结构来展开的，主要是针对以下两个问题:  
1. 创建kmem_cache高速缓存用来存储所有的cache描述符  
2. 创建array_cache和kmem_list3高速缓存用来存储slab数据结构中的这两个关键结构

这里明显有点自相矛盾，那就是slab管理器尚未建立起来，又如何靠slab分配高速缓存来给这些结构分配空间呢？

  解决第一个问题的方法是直接静态定义一个名为cache_cache的kmem_cache结构，来管理所有的kmem_cache描述符，对于array_cache和kmem_list3，内核也是先静态定义，然后建立起普通高速缓存(general cache)，再使用kmalloc分配普通高速缓存空间来替代之前静态定义的部分。

##### 普通高速缓存是一组大小按几何倍数增长的高速缓存的合集，一个普通高速缓存用如下结构描述
```
    /* Size description struct for general caches. */  
    struct cache_sizes {  
        size_t          cs_size;   /*general cache的大小*/  
        struct kmem_cache   *cs_cachep;         /*general cache的cache描述符指针*/  
    #ifdef CONFIG_ZONE_DMA   
        struct kmem_cache   *cs_dmacachep;  
    #endif   
    };
```
普通高速缓存的大小由malloc_sizes表来确定
```
    /* 
     * These are the default caches for kmalloc. Custom caches can have other sizes. 
     */  
    struct cache_sizes malloc_sizes[] = {  
    #define CACHE(x) { .cs_size = (x) },   
    #include <linux/kmalloc_sizes.h>   
        CACHE(ULONG_MAX)  
    #undef CACHE   
    };
```
其中<linux/kmalloc_sizes.h>中的内容为
```
    #if (PAGE_SIZE == 4096)   
        CACHE(32)  
    #endif   
        CACHE(64)  
    #if L1_CACHE_BYTES < 64   
        CACHE(96)  
    #endif   
        CACHE(128)  
    #if L1_CACHE_BYTES < 128   
        CACHE(192)  
    #endif   
        CACHE(256)  
        CACHE(512)  
        CACHE(1024)  
        CACHE(2048)  
        CACHE(4096)  
        CACHE(8192)  
        CACHE(16384)  
        CACHE(32768)  
        CACHE(65536)  
        CACHE(131072)  
    #if KMALLOC_MAX_SIZE >= 262144   
        CACHE(262144)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 524288   
        CACHE(524288)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 1048576   
        CACHE(1048576)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 2097152   
        CACHE(2097152)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 4194304   
        CACHE(4194304)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 8388608   
        CACHE(8388608)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 16777216   
        CACHE(16777216)  
    #endif   
    #if KMALLOC_MAX_SIZE >= 33554432   
        CACHE(33554432)  
    #endif
```

##### cache_cache的初始化和普通高速缓存的建立
由`start_kernel()-->mm_init()-->kmem_cache_init()`函数来完成，下面就来看具体的初始化代码
```
    void __init kmem_cache_init(void)  
    {  
        size_t left_over;  
        struct cache_sizes *sizes;  
        struct cache_names *names;  
        int i;  
        int order;  
        int node;  

        if (num_possible_nodes() == 1)  
            use_alien_caches = 0;  

        /*初始化静态L3变量initkmem_list3*/  
        for (i = 0; i < NUM_INIT_LISTS; i++) {  
            kmem_list3_init(&initkmem_list3[i]);  
            if (i < MAX_NUMNODES)  
                cache_cache.nodelists[i] = NULL;  
        }  
        /*将cache_cache和initkmem_list3相关联*/  
        set_up_list3s(&cache_cache, CACHE_CACHE);  

        /* 
         * Fragmentation resistance on low memory - only use bigger 
         * page orders on machines with more than 32MB of memory. 
         */  
        if (totalram_pages > (32 << 20) >> PAGE_SHIFT)  
            slab_break_gfp_order = BREAK_GFP_ORDER_HI;  

        /* Bootstrap is tricky, because several objects are allocated 
         * from caches that do not exist yet: 
         * 1) initialize the cache_cache cache: it contains the struct 
         *    kmem_cache structures of all caches, except cache_cache itself: 
         *    cache_cache is statically allocated. 
         *    Initially an __init data area is used for the head array and the 
         *    kmem_list3 structures, it's replaced with a kmalloc allocated 
         *    array at the end of the bootstrap. 
         * 2) Create the first kmalloc cache. 
         *    The struct kmem_cache for the new cache is allocated normally. 
         *    An __init data area is used for the head array. 
         * 3) Create the remaining kmalloc caches, with minimally sized 
         *    head arrays. 
         * 4) Replace the __init data head arrays for cache_cache and the first 
         *    kmalloc cache with kmalloc allocated arrays. 
         * 5) Replace the __init data for kmem_list3 for cache_cache and 
         *    the other cache's with kmalloc allocated memory. 
         * 6) Resize the head arrays of the kmalloc caches to their final sizes. 
         */  

        node = numa_node_id();  

        /*初始化cache_cache的其余部分*/  

        /* 1) create the cache_cache */  
        INIT_LIST_HEAD(&cache_chain);  
        list_add(&cache_cache.next, &cache_chain);  
        cache_cache.colour_off = cache_line_size();  
        cache_cache.array[smp_processor_id()] = &initarray_cache.cache;  
        cache_cache.nodelists[node] = &initkmem_list3[CACHE_CACHE + node];  

        /* 
         * struct kmem_cache size depends on nr_node_ids, which 
         * can be less than MAX_NUMNODES. 
         */  
        cache_cache.buffer_size = offsetof(struct kmem_cache, nodelists) +  
                     nr_node_ids * sizeof(struct kmem_list3 *);  
    #if DEBUG   
        cache_cache.obj_size = cache_cache.buffer_size;  
    #endif   
        cache_cache.buffer_size = ALIGN(cache_cache.buffer_size,  
                        cache_line_size());  
        cache_cache.reciprocal_buffer_size =  
            reciprocal_value(cache_cache.buffer_size);  

        /*计算cache_cache的剩余空间以及slab中对象的数目，order决定了slab的大小(PAGE_SIZE<<order)*/  
        for (order = 0; order < MAX_ORDER; order++) {  
            cache_estimate(order, cache_cache.buffer_size,  
                cache_line_size(), 0, &left_over, &cache_cache.num);  
            /*当该order计算出来的num,即slab中对象的数目不为0时，则跳出循环*/  
            if (cache_cache.num)  
                break;  
        }  
        BUG_ON(!cache_cache.num);  
        cache_cache.gfporder = order;/*确定分配给每个slab的页数的对数*/  
        cache_cache.colour = left_over / cache_cache.colour_off;/*确定可用颜色的数目*/  
        /*确定slab管理区的大小，即slab描述符以及kmem_bufctl_t数组*/  
        cache_cache.slab_size = ALIGN(cache_cache.num * sizeof(kmem_bufctl_t) +  
                          sizeof(struct slab), cache_line_size());  

        /* 2+3) create the kmalloc caches */  
        sizes = malloc_sizes;  
        names = cache_names;  

        /* 
         * Initialize the caches that provide memory for the array cache and the 
         * kmem_list3 structures first.  Without this, further allocations will 
         * bug. 
         */  
        /*为了后面能够调用kmalloc()创建per-CPU高速缓存和kmem_list3高速缓存， 
           这里必须先创建大小相应的general cache*/  
        sizes[INDEX_AC].cs_cachep = kmem_cache_create(names[INDEX_AC].name,  
                        sizes[INDEX_AC].cs_size,  
                        ARCH_KMALLOC_MINALIGN,  
                        ARCH_KMALLOC_FLAGS|SLAB_PANIC,  
                        NULL);  

        /*如果AC和L3在malloc_sizes中的偏移不一样，也就是说它们的大小不属于同一级别， 
         则创建AC的gerneral cache，否则两者共用一个gerneral cache*/  
        if (INDEX_AC != INDEX_L3) {  
            sizes[INDEX_L3].cs_cachep =  
                kmem_cache_create(names[INDEX_L3].name,  
                    sizes[INDEX_L3].cs_size,  
                    ARCH_KMALLOC_MINALIGN,  
                    ARCH_KMALLOC_FLAGS|SLAB_PANIC,  
                    NULL);  
        }  

        slab_early_init = 0;  

        /*创建各级的gerneral cache*/  
        while (sizes->cs_size != ULONG_MAX) {  
            /* 
             * For performance, all the general caches are L1 aligned. 
             * This should be particularly beneficial on SMP boxes, as it 
             * eliminates "false sharing". 
             * Note for systems short on memory removing the alignment will 
             * allow tighter packing of the smaller caches. 
             */  
            if (!sizes->cs_cachep) {  
                sizes->cs_cachep = kmem_cache_create(names->name,  
                        sizes->cs_size,  
                        ARCH_KMALLOC_MINALIGN,  
                        ARCH_KMALLOC_FLAGS|SLAB_PANIC,  
                        NULL);  
            }  
    #ifdef CONFIG_ZONE_DMA   
            sizes->cs_dmacachep = kmem_cache_create(  
                        names->name_dma,  
                        sizes->cs_size,  
                        ARCH_KMALLOC_MINALIGN,  
                        ARCH_KMALLOC_FLAGS|SLAB_CACHE_DMA|  
                            SLAB_PANIC,  
                        NULL);  
    #endif   
            sizes++;  
            names++;  
        }  
        /* 4) Replace the bootstrap head arrays */  
        {  
            struct array_cache *ptr;  

            /*这里调用kmalloc()为cache_cache创建per-CPU高速缓存*/  
            ptr = kmalloc(sizeof(struct arraycache_init), GFP_NOWAIT);  

            BUG_ON(cpu_cache_get(&cache_cache) != &initarray_cache.cache);  
            /*将静态定义的initarray_cache中的array_cache拷贝到malloc申请到的空间中*/  
            memcpy(ptr, cpu_cache_get(&cache_cache),  
                   sizeof(struct arraycache_init));  
            /* 
             * Do not assume that spinlocks can be initialized via memcpy: 
             */  
            spin_lock_init(&ptr->lock);  

            /*将cache_cache与保存per-CPU高速缓存的空间关联*/  
            cache_cache.array[smp_processor_id()] = ptr;  

            /*为之前创建的AC gerneral cache创建per-CPU高速缓存，替换静态定义的initarray_generic.cache*/  
            ptr = kmalloc(sizeof(struct arraycache_init), GFP_NOWAIT);  

            BUG_ON(cpu_cache_get(malloc_sizes[INDEX_AC].cs_cachep)  
                   != &initarray_generic.cache);  
            memcpy(ptr, cpu_cache_get(malloc_sizes[INDEX_AC].cs_cachep),  
                   sizeof(struct arraycache_init));  
            /* 
             * Do not assume that spinlocks can be initialized via memcpy: 
             */  
            spin_lock_init(&ptr->lock);  

            malloc_sizes[INDEX_AC].cs_cachep->array[smp_processor_id()] =  
                ptr;  
        }  
        /* 5) Replace the bootstrap kmem_list3's */  
        {  
            int nid;  

            for_each_online_node(nid) {  

                /*为cache_cache的kmem_list3申请高速缓存空间，并替换静态定义的initkmem_list3*/  
                init_list(&cache_cache, &initkmem_list3[CACHE_CACHE + nid], nid);  

                /*为AC的kmem_list3申请高速缓存空间，并替换静态定义的initkmem_list3*/  
                init_list(malloc_sizes[INDEX_AC].cs_cachep,  
                      &initkmem_list3[SIZE_AC + nid], nid);  

                if (INDEX_AC != INDEX_L3) {  
                /*为L3的kmem_list3申请高速缓存空间，并替换静态定义的initkmem_list3*/  
                    init_list(malloc_sizes[INDEX_L3].cs_cachep,  
                          &initkmem_list3[SIZE_L3 + nid], nid);  
                }  
            }  
        }  

        g_cpucache_up = EARLY;  
    }
```

* 前面大部分的代码都是围绕cache_cache展开的，主要是将cache_cache同静态kmem_list3进行关联，将cache_cache添加到cache_chain链表中，并且计算初始化内部的一些数据项  
* 现在还没有高速缓存来存储cache_cache中的kmem_list3描述符和array_cache描述符，因此下面就要调用kmem_cache_create()建立高速缓存来存储这两种描述符  
* 内核使用g_cpucache_up这个枚举量来表示slab分配器的初始化进度  

```
    static enum {  
        NONE,  
        PARTIAL_AC,  
        PARTIAL_L3,  
        EARLY,  
        FULL  
    } g_cpucache_up;
```
  这个值的更新是在`kmem_cache_create()-->setup_cpu_cache()`函数中进行更新的，每调用一次kmem_cache_create(),g_cpucache_up的值就加1，直到它等于EARLY，比如说第一次调用kmem_cache_create()创建了AC(array_cache)的高速缓存，那么g_cpucache_up由NONE变为PARTIAL_AC，那么下次调用kmem_cache_create()创建L3高速缓存时，内核就知道AC高速缓存已经准备好了，也就是说可以在array_cache高速缓存中为L3高速缓存描述符的array_cache描述符分配高速缓存空间了。

* 创建了AC和L3高速缓存后就循环创建各级普通高速缓存，此时创建的高速缓存都是完整的了！也就是说里面的结构变量都已经是存储在相应的高速缓存中  
* 由于AC高速缓存已经创建，因此kmalloc()动态创建一个array_cache对象替换cache_cache的静态array_cache  
* 由于AC高速缓存描述符本身的array_cache描述符还未动态创建，因此同样kmalloc()动态创建一个array_cache替换AC高速缓存的静态array_cache  
* 为cache_cache,AC,L3高速缓存分别动态创建kmem_list描述符对象，替换静态的initkmem_list3   
* 将g_cpucache_up置为EARLY,表示slab分配器的初始化已初步完成   

##### slab分配器初始化工作的最后一步由kmem_cache_init_late()函数完成
这个函数就不做详细分析了，它的工作就是设置cache_cache和各级普通高速缓存中的array_cache本地高速缓存的相关属性
```
    void __init kmem_cache_init_late(void)  
    {  
        struct kmem_cache *cachep;  

        /* 6) resize the head arrays to their final sizes */  
        mutex_lock(&cache_chain_mutex);  
        list_for_each_entry(cachep, &cache_chain, next)  
            if (enable_cpucache(cachep, GFP_NOWAIT))  
                BUG();  
        mutex_unlock(&cache_chain_mutex);  

        /* Done! */  
        g_cpucache_up = FULL;   /*slab初始化完成*/  

        /* Annotate slab for lockdep -- annotate the malloc caches */  
        init_lock_keys();  

        /* 
         * Register a cpu startup notifier callback that initializes 
         * cpu_cache_get for all new cpus 
         */  
        register_cpu_notifier(&cpucache_notifier);  

        /* 
         * The reap timers are started later, with a module init call: That part 
         * of the kernel is not yet operational. 
         */  
    }
```


## 三、创建缓存
##### 创建新的缓存必须通过kmem_cache_create()函数来完成，原型如下
```
    struct kmem_cache *  
    kmem_cache_create (const char *name, size_t size, size_t align,  
        unsigned long flags, void (*ctor)(void *))
```

* name:所创建的新缓存的名字
* size :缓存所分配对象的大小
* align:对象的对齐值
* flags:创建用的标识
* ctor:创建对象时的构造函数

kmem_cache_create()的实际工作就是为新的缓存申请缓存描述符，array_cache描述符和kmem_list3描述符，并根据接收的参数对这三个结构中的变量进行相应的初始化。新创建的缓存是空的，不包含slab。
```
    struct kmem_cache *  
    kmem_cache_create (const char *name, size_t size, size_t align,  
        unsigned long flags, void (*ctor)(void *))  
    {  
        size_t left_over, slab_size, ralign;  
        struct kmem_cache *cachep = NULL, *pc;  
        gfp_t gfp;  

        /* 
         * Sanity checks... these are all serious usage bugs. 
         */  
         /*做一些必要的检查，以下情况都是不合法的: 
           1.缓存名为空 
           2.处于中断环境中 
           3.缓存中的对象大小小于处理器的字长 
           4.缓存中的对象大小大于普通缓存的最大长度*/  
        if (!name || in_interrupt() || (size < BYTES_PER_WORD) ||  
            size > KMALLOC_MAX_SIZE) {  
            printk(KERN_ERR "%s: Early error in slab %s\n", __func__,  
                    name);  
            BUG();  
        }  

        /* 
         * We use cache_chain_mutex to ensure a consistent view of 
         * cpu_online_mask as well.  Please see cpuup_callback 
         */  
        if (slab_is_available()) {  
            get_online_cpus();  
            mutex_lock(&cache_chain_mutex);  
        }  

        list_for_each_entry(pc, &cache_chain, next) {  
            char tmp;  
            int res;  

            /* 
             * This happens when the module gets unloaded and doesn't 
             * destroy its slab cache and no-one else reuses the vmalloc 
             * area of the module.  Print a warning. 
             */  
            res = probe_kernel_address(pc->name, tmp);  
            if (res) {  
                printk(KERN_ERR  
                       "SLAB: cache with size %d has lost its name\n",  
                       pc->buffer_size);  
                continue;  
            }  

            if (!strcmp(pc->name, name)) {  
                printk(KERN_ERR  
                       "kmem_cache_create: duplicate cache %s\n", name);  
                dump_stack();  
                goto oops;  
            }  
        }  

    #if DEBUG   
        WARN_ON(strchr(name, ' ')); /* It confuses parsers */  
    #if FORCED_DEBUG   
        /* 
         * Enable redzoning and last user accounting, except for caches with 
         * large objects, if the increased size would increase the object size 
         * above the next power of two: caches with object sizes just above a 
         * power of two have a significant amount of internal fragmentation. 
         */  
        if (size < 4096 || fls(size - 1) == fls(size-1 + REDZONE_ALIGN +  
                            2 * sizeof(unsigned long long)))  
            flags |= SLAB_RED_ZONE | SLAB_STORE_USER;  
        if (!(flags & SLAB_DESTROY_BY_RCU))  
            flags |= SLAB_POISON;  
    #endif   
        if (flags & SLAB_DESTROY_BY_RCU)  
            BUG_ON(flags & SLAB_POISON);  
    #endif   
        /* 
         * Always checks flags, a caller might be expecting debug support which 
         * isn't available. 
         */  
        BUG_ON(flags & ~CREATE_MASK);  

        /* 
         * Check that size is in terms of words.  This is needed to avoid 
         * unaligned accesses for some archs when redzoning is used, and makes 
         * sure any on-slab bufctl's are also correctly aligned. 
         */  
         /*如果缓存对象大小没有对齐到处理器字长，则对齐之*/  
        if (size & (BYTES_PER_WORD - 1)) {  
            size += (BYTES_PER_WORD - 1);  
            size &= ~(BYTES_PER_WORD - 1);  
        }  

        /* calculate the final buffer alignment: */  

        /* 1) arch recommendation: can be overridden for debug */  
        /*要求按照体系结构对齐*/  
        if (flags & SLAB_HWCACHE_ALIGN) {  
            /* 
             * Default alignment: as specified by the arch code.  Except if 
             * an object is really small, then squeeze multiple objects into 
             * one cacheline. 
             */  
            ralign = cache_line_size();/*对齐值取L1缓存行的大小*/  
            /*如果对象大小足够小，则不断压缩对齐值以保证能将足够多的对象装入一个缓存行*/  
            while (size <= ralign / 2)  
                ralign /= 2;  
        } else {  
            ralign = BYTES_PER_WORD; /*对齐值取处理器字长*/  
        }  

        /* 
         * Redzoning and user store require word alignment or possibly larger. 
         * Note this will be overridden by architecture or caller mandated 
         * alignment if either is greater than BYTES_PER_WORD. 
         */  
         /*如果开启了DEBUG，则按需要进行相应的对齐*/  
        if (flags & SLAB_STORE_USER)  
            ralign = BYTES_PER_WORD;  

        if (flags & SLAB_RED_ZONE) {  
            ralign = REDZONE_ALIGN;  
            /* If redzoning, ensure that the second redzone is suitably 
             * aligned, by adjusting the object size accordingly. */  
            size += REDZONE_ALIGN - 1;  
            size &= ~(REDZONE_ALIGN - 1);  
        }  

        /* 2) arch mandated alignment */  
        if (ralign < ARCH_SLAB_MINALIGN) {  
            ralign = ARCH_SLAB_MINALIGN;  
        }  
        /* 3) caller mandated alignment */  
        if (ralign < align) {  
            ralign = align;  
        }  
        /* disable debug if necessary */  
        if (ralign > __alignof__(unsigned long long))  
            flags &= ~(SLAB_RED_ZONE | SLAB_STORE_USER);  
        /* 
         * 4) Store it. 
         */  
        align = ralign;  

        if (slab_is_available())  
            gfp = GFP_KERNEL;  
        else  
            gfp = GFP_NOWAIT;  

        /* Get cache's description obj. */  
        /*从cache_cache中分配一个高速缓存描述符*/  
        cachep = kmem_cache_zalloc(&cache_cache, gfp);  
        if (!cachep)  
            goto oops;  

    #if DEBUG   
        cachep->obj_size = size;  

        /* 
         * Both debugging options require word-alignment which is calculated 
         * into align above. 
         */  
        if (flags & SLAB_RED_ZONE) {  
            /* add space for red zone words */  
            cachep->obj_offset += sizeof(unsigned long long);  
            size += 2 * sizeof(unsigned long long);  
        }  
        if (flags & SLAB_STORE_USER) {  
            /* user store requires one word storage behind the end of 
             * the real object. But if the second red zone needs to be 
             * aligned to 64 bits, we must allow that much space. 
             */  
            if (flags & SLAB_RED_ZONE)  
                size += REDZONE_ALIGN;  
            else  
                size += BYTES_PER_WORD;  
        }  
    #if FORCED_DEBUG && defined(CONFIG_DEBUG_PAGEALLOC)   
        if (size >= malloc_sizes[INDEX_L3 + 1].cs_size  
            && cachep->obj_size > cache_line_size() && ALIGN(size, align) < PAGE_SIZE) {  
            cachep->obj_offset += PAGE_SIZE - ALIGN(size, align);  
            size = PAGE_SIZE;  
        }  
    #endif   
    #endif   

        /* 
         * Determine if the slab management is 'on' or 'off' slab. 
         * (bootstrapping cannot cope with offslab caches so don't do 
         * it too early on.) 
         */  
         /*如果缓存对象的大小不小于页面大小的1/8并且不处于slab初始化阶段， 
           则选择将slab描述符放在slab外部以腾出更多的空间给对象*/  
        if ((size >= (PAGE_SIZE >> 3)) && !slab_early_init)  
            /* 
             * Size is large, assume best to place the slab management obj 
             * off-slab (should allow better packing of objs). 
             */  
            flags |= CFLGS_OFF_SLAB;  

        /*将对象大小按之前确定的align对齐*/  
        size = ALIGN(size, align);  

        /*计算slab的对象数，分配给slab的页框阶数并返回slab的剩余空间，即碎片大小*/  
        left_over = calculate_slab_order(cachep, size, align, flags);  

        if (!cachep->num) {  
            printk(KERN_ERR  
                   "kmem_cache_create: couldn't create cache %s.\n", name);  
            kmem_cache_free(&cache_cache, cachep);  
            cachep = NULL;  
            goto oops;  
        }  
        /*将slab管理区的大小按align进行对齐*/  
        slab_size = ALIGN(cachep->num * sizeof(kmem_bufctl_t)  
                  + sizeof(struct slab), align);  

        /* 
         * If the slab has been placed off-slab, and we have enough space then 
         * move it on-slab. This is at the expense of any extra colouring. 
         */  
         /*如果之前确定将slab管理区放在slab外部，但是碎片空间大于slab管理区大小， 
           这时改变策略将slab管理区放在slab内部，这样可以节省外部空间，但是会牺牲 
           着色的颜色个数*/  
        if (flags & CFLGS_OFF_SLAB && left_over >= slab_size) {  
            flags &= ~CFLGS_OFF_SLAB;  
            left_over -= slab_size;  
        }  

        /*如果的确要将slab管理区放在外部，则不需按照该slab的对齐方式进行对齐了， 
         重新计算slab_size*/  
        if (flags & CFLGS_OFF_SLAB) {  
            /* really off slab. No need for manual alignment */  
            slab_size =  
                cachep->num * sizeof(kmem_bufctl_t) + sizeof(struct slab);  

    #ifdef CONFIG_PAGE_POISONING   
            /* If we're going to use the generic kernel_map_pages() 
             * poisoning, then it's going to smash the contents of 
             * the redzone and userword anyhow, so switch them off. 
             */  
            if (size % PAGE_SIZE == 0 && flags & SLAB_POISON)  
                flags &= ~(SLAB_RED_ZONE | SLAB_STORE_USER);  
    #endif   
        }  

        /*着色偏移区L1缓存行的大小*/  
        cachep->colour_off = cache_line_size();  
        /* Offset must be a multiple of the alignment. */  
        if (cachep->colour_off < align)/*着色偏移小于align的话则要取对齐值*/  
            cachep->colour_off = align;  
        /*计算着色的颜色数目*/  
        cachep->colour = left_over / cachep->colour_off;  
        cachep->slab_size = slab_size;  
        cachep->flags = flags;  
        cachep->gfpflags = 0;  
        if (CONFIG_ZONE_DMA_FLAG && (flags & SLAB_CACHE_DMA))  
            cachep->gfpflags |= GFP_DMA;  
        cachep->buffer_size = size;  
        cachep->reciprocal_buffer_size = reciprocal_value(size);  

        if (flags & CFLGS_OFF_SLAB) {  
            cachep->slabp_cache = kmem_find_general_cachep(slab_size, 0u);  
            /* 
             * This is a possibility for one of the malloc_sizes caches. 
             * But since we go off slab only for object size greater than 
             * PAGE_SIZE/8, and malloc_sizes gets created in ascending order, 
             * this should not happen at all. 
             * But leave a BUG_ON for some lucky dude. 
             */  
            BUG_ON(ZERO_OR_NULL_PTR(cachep->slabp_cache));  
        }  
        cachep->ctor = ctor;  
        cachep->name = name;  

        if (setup_cpu_cache(cachep, gfp)) {  
            __kmem_cache_destroy(cachep);  
            cachep = NULL;  
            goto oops;  
        }  

        /* cache setup completed, link it into the list */  
        /*将该高速缓存描述符添加进cache_chain*/  
        list_add(&cachep->next, &cache_chain);  
    oops:  
        if (!cachep && (flags & SLAB_PANIC))  
            panic("kmem_cache_create(): failed to create slab `%s'\n",  
                  name);  
        if (slab_is_available()) {  
            mutex_unlock(&cache_chain_mutex);  
            put_online_cpus();  
        }  
        return cachep;  
    }
```

* 首先做参数有效性的检查
* 计算对齐值
* 分配一个缓存描述符
* 确定slab管理区(slab描述符+kmem_bufctl_t数组)的存储位置
* 调用calculate_slab_order()进行相关项的计算，包括分配给slab的页阶数，碎片大小，slab的对象数
* 计算着色偏移和可用的颜色数量
* 调用setup_cpu_cache()分配array_cache描述符和kmem_list3描述符并初始化相关变量
* 最后将缓存描述符插入cache_chain中

##### 再来看看两个辅助函数calculate_slab_order()和setup_cpu_cache()
```
    static size_t calculate_slab_order(struct kmem_cache *cachep,  
                size_t size, size_t align, unsigned long flags)  
    {  
        unsigned long offslab_limit;  
        size_t left_over = 0;  
        int gfporder;  


        for (gfporder = 0; gfporder <= KMALLOC_MAX_ORDER; gfporder++) {  
            unsigned int num;  
            size_t remainder;  

            /*根据gfporder计算对象数和剩余空间*/  
            cache_estimate(gfporder, size, align, flags, &remainder, &num);  
            if (!num)/*如果计算出来的对象数为0则要增大分配给slab的页框阶数再进行计算*/  
                continue;  

            if (flags & CFLGS_OFF_SLAB) {  
                /* 
                 * Max number of objs-per-slab for caches which 
                 * use off-slab slabs. Needed to avoid a possible 
                 * looping condition in cache_grow(). 
                 */  
                 /*offslab_limit记录了在外部存储slab描述符时所允许的slab最大对象数*/  
                offslab_limit = size - sizeof(struct slab);  
                offslab_limit /= sizeof(kmem_bufctl_t);  

                /*如果前面计算出的对象数num要大于允许的最大对象数，则不合法*/  
                if (num > offslab_limit)  
                    break;  
            }  

            /* Found something acceptable - save it away */  
            cachep->num = num;  
            cachep->gfporder = gfporder;  
            left_over = remainder;  

            /* 
             * A VFS-reclaimable slab tends to have most allocations 
             * as GFP_NOFS and we really don't want to have to be allocating 
             * higher-order pages when we are unable to shrink dcache. 
             */  
            if (flags & SLAB_RECLAIM_ACCOUNT)  
                break;  

            /* 
             * Large number of objects is good, but very large slabs are 
             * currently bad for the gfp()s. 
             */  
            if (gfporder >= slab_break_gfp_order)  
                break;  

            /* 
             * Acceptable internal fragmentation? 
             */  
            if (left_over * 8 <= (PAGE_SIZE << gfporder))  
                break;  
        }  
        return left_over;  
    }
```

```
    static void cache_estimate(unsigned long gfporder, size_t buffer_size,  
                   size_t align, int flags, size_t *left_over,  
                   unsigned int *num)  
    {  
        int nr_objs;  
        size_t mgmt_size;  
        size_t slab_size = PAGE_SIZE << gfporder;  

        /* 
         * The slab management structure can be either off the slab or 
         * on it. For the latter case, the memory allocated for a 
         * slab is used for: 
         * 
         * - The struct slab 
         * - One kmem_bufctl_t for each object 
         * - Padding to respect alignment of @align 
         * - @buffer_size bytes for each object 
         * 
         * If the slab management structure is off the slab, then the 
         * alignment will already be calculated into the size. Because 
         * the slabs are all pages aligned, the objects will be at the 
         * correct alignment when allocated. 
         */  
         /*如果slab描述符存储在slab外部，则slab的对象数即为slab_size/buffer_size*/  
        if (flags & CFLGS_OFF_SLAB) {  
            mgmt_size = 0;  
            nr_objs = slab_size / buffer_size;  

            if (nr_objs > SLAB_LIMIT)  
                nr_objs = SLAB_LIMIT;  
        } else {/*否则先减去slab管理区的大小再进行计算*/  
            /* 
             * Ignore padding for the initial guess. The padding 
             * is at most @align-1 bytes, and @buffer_size is at 
             * least @align. In the worst case, this result will 
             * be one greater than the number of objects that fit 
             * into the memory allocation when taking the padding 
             * into account. 
             */  
            nr_objs = (slab_size - sizeof(struct slab)) /  
                  (buffer_size + sizeof(kmem_bufctl_t));  

            /* 
             * This calculated number will be either the right 
             * amount, or one greater than what we want. 
             */  
            if (slab_mgmt_size(nr_objs, align) + nr_objs*buffer_size  
                   > slab_size)  
                nr_objs--;  

            if (nr_objs > SLAB_LIMIT)  
                nr_objs = SLAB_LIMIT;  
                      /*计算slab管理区的大小*/  
            mgmt_size = slab_mgmt_size(nr_objs, align);  
        }  
        /*保存slab对象数*/  
        *num = nr_objs;  
        /*计算并保存slab的剩余空间*/  
        *left_over = slab_size - nr_objs*buffer_size - mgmt_size;  
    }
```

##### 在slab初始化完成后，也就是g_cpucache_up变量的值为FULL后
setup_cpu_cache()函数等价于`setup_cpu_cache()-->enable_cpucache()`
```
    static int enable_cpucache(struct kmem_cache *cachep, gfp_t gfp)  
    {  
        int err;  
        int limit, shared;  

        /* 
         * The head array serves three purposes: 
         * - create a LIFO ordering, i.e. return objects that are cache-warm 
         * - reduce the number of spinlock operations. 
         * - reduce the number of linked list operations on the slab and 
         *   bufctl chains: array operations are cheaper. 
         * The numbers are guessed, we should auto-tune as described by 
         * Bonwick. 
         */  
         /*根据对象的大小来确定本地高速缓存中的空闲对象上限*/  
        if (cachep->buffer_size > 131072)  
            limit = 1;  
        else if (cachep->buffer_size > PAGE_SIZE)  
            limit = 8;  
        else if (cachep->buffer_size > 1024)  
            limit = 24;  
        else if (cachep->buffer_size > 256)  
            limit = 54;  
        else  
            limit = 120;  

        /* 
         * CPU bound tasks (e.g. network routing) can exhibit cpu bound 
         * allocation behaviour: Most allocs on one cpu, most free operations 
         * on another cpu. For these cases, an efficient object passing between 
         * cpus is necessary. This is provided by a shared array. The array 
         * replaces Bonwick's magazine layer. 
         * On uniprocessor, it's functionally equivalent (but less efficient) 
         * to a larger limit. Thus disabled by default. 
         */  
        shared = 0;  
        if (cachep->buffer_size <= PAGE_SIZE && num_possible_cpus() > 1)  
            shared = 8;  

    #if DEBUG   
        /* 
         * With debugging enabled, large batchcount lead to excessively long 
         * periods with disabled local interrupts. Limit the batchcount 
         */  
        if (limit > 32)  
            limit = 32;  
    #endif   
        err = do_tune_cpucache(cachep, limit, (limit + 1) / 2, shared, gfp);  
        if (err)  
            printk(KERN_ERR "enable_cpucache failed for %s, error %d.\n",  
                   cachep->name, -err);  
        return err;  
    }
```

```
    static int do_tune_cpucache(struct kmem_cache *cachep, int limit,  
                    int batchcount, int shared, gfp_t gfp)  
    {  
        struct ccupdate_struct *new;  
        int i;  

        /*申请一个ccupdate_struct*/  
        new = kzalloc(sizeof(*new), gfp);  
        if (!new)  
            return -ENOMEM;  

        /*为每个CPU申请array_cache和用来跟踪本地CPU空闲对象的指针数组*/  
        for_each_online_cpu(i) {  
            new->new[i] = alloc_arraycache(cpu_to_node(i), limit,  
                            batchcount, gfp);  
            if (!new->new[i]) {  
                for (i--; i >= 0; i--)  
                    kfree(new->new[i]);  
                kfree(new);  
                return -ENOMEM;  
            }  
        }  
        new->cachep = cachep;  

        /*将cachep和array_cache进关联*/  
        on_each_cpu(do_ccupdate_local, (void *)new, 1);  

        check_irq_on();  
        cachep->batchcount = batchcount;  
        cachep->limit = limit;  
        cachep->shared = shared;  

        for_each_online_cpu(i) {  
            struct array_cache *ccold = new->new[i];  
            if (!ccold)  
                continue;  
            spin_lock_irq(&cachep->nodelists[cpu_to_node(i)]->list_lock);  
            free_block(cachep, ccold->entry, ccold->avail, cpu_to_node(i));  
            spin_unlock_irq(&cachep->nodelists[cpu_to_node(i)]->list_lock);  
            kfree(ccold);  
        }  
        kfree(new);  
        /*申请kmem_list3*/  
        return alloc_kmemlist(cachep, gfp);  
    }
```

## 四、分配对象
从一个缓存中分配对象总是遵循下面的原则：  
1. 本地高速缓存中是否有空闲对象，如果有的话则从其中获取对象，这时分配的对象是最“热”的；  
2. 如果本地高速缓存中没有对象，则从kmem_list3中的slab链表中寻找空闲对象并填充到本地高速缓存再分配；  
3. 如果所有的slab中都没有空闲对象了，那么就要创建新的slab,再分配 。

函数kmem_cache_alloc用于从特定的缓存获取对象，kmalloc用于从普通缓存中获取对象，它们的执行流程如下图所示

![](/images/kernel/2015-03-03-12.png)

实质性的工作是从`____cache_alloc()`开始的，因此从这个函数作为入口来分析
```
    static inline void *____cache_alloc(struct kmem_cache *cachep, gfp_t flags)  
    {  
        void *objp;  
        struct array_cache *ac;  

        check_irq_off();  

        /*获取缓存的本地高速缓存的描述符array_cache*/  
        ac = cpu_cache_get(cachep);  

        /*如果本地高速缓存中还有空闲对象可以分配则从本地高速缓存中分配*/  
        if (likely(ac->avail)) {  
            STATS_INC_ALLOCHIT(cachep);  
            ac->touched = 1;  
            /*先将avail的值减1，这样avail对应的空闲对象是最热的，即最近释放出来的， 
              更有可能驻留在CPU高速缓存中*/  
            objp = ac->entry[--ac->avail];  
        } else {/*否则需要填充本地高速缓存*/  
            STATS_INC_ALLOCMISS(cachep);  
            objp = cache_alloc_refill(cachep, flags);  
        }  
        /* 
         * To avoid a false negative, if an object that is in one of the 
         * per-CPU caches is leaked, we need to make sure kmemleak doesn't 
         * treat the array pointers as a reference to the object. 
         */  
        kmemleak_erase(&ac->entry[ac->avail]);  
        return objp;  
    }
```

```
    static void *cache_alloc_refill(struct kmem_cache *cachep, gfp_t flags)  
    {  
        int batchcount;  
        struct kmem_list3 *l3;  
        struct array_cache *ac;  
        int node;  

    retry:  
        check_irq_off();  
        node = numa_node_id();  
        ac = cpu_cache_get(cachep);  
        batchcount = ac->batchcount;  /*获取批量转移的数目*/  
        if (!ac->touched && batchcount > BATCHREFILL_LIMIT) {  
            /* 
             * If there was little recent activity on this cache, then 
             * perform only a partial refill.  Otherwise we could generate 
             * refill bouncing. 
             */  
            batchcount = BATCHREFILL_LIMIT;  
        }  
        /*获取kmem_list3*/  
        l3 = cachep->nodelists[node];  

        BUG_ON(ac->avail > 0 || !l3);  
        spin_lock(&l3->list_lock);  

        /* See if we can refill from the shared array */  
        /*如果有共享本地高速缓存，则从共享本地高速缓存填充*/  
        if (l3->shared && transfer_objects(ac, l3->shared, batchcount))  
            goto alloc_done;  

        while (batchcount > 0) {  
            struct list_head *entry;  
            struct slab *slabp;  
            /* Get slab alloc is to come from. */  
            /*扫描slab链表，先从partial链表开始，如果整个partial链表都无法找到batchcount个空闲对象， 
            再扫描free链表*/  
            entry = l3->slabs_partial.next;  

            /*entry回到表头说明partial链表已经扫描完毕，开始扫描free链表*/  
            if (entry == &l3->slabs_partial) {  
                l3->free_touched = 1;  
                entry = l3->slabs_free.next;  
                if (entry == &l3->slabs_free)  
                    goto must_grow;  
            }  

            /*由链表项得到slab描述符*/  
            slabp = list_entry(entry, struct slab, list);  
            check_slabp(cachep, slabp);  
            check_spinlock_acquired(cachep);  

            /* 
             * The slab was either on partial or free list so 
             * there must be at least one object available for 
             * allocation. 
             */  
            BUG_ON(slabp->inuse >= cachep->num);  

            /*如果slabp中还存在空闲对象并且还需要继续填充对象到本地高速缓存*/  
            while (slabp->inuse < cachep->num && batchcount--) {  
                STATS_INC_ALLOCED(cachep);  
                STATS_INC_ACTIVE(cachep);  
                STATS_SET_HIGH(cachep);  

                /*填充的本质就是用ac后面的void*数组元素指向一个空闲对象*/  
                ac->entry[ac->avail++] = slab_get_obj(cachep, slabp,  
                                    node);  
            }  
            check_slabp(cachep, slabp);  

            /* move slabp to correct slabp list: */  
            /*由于从slab中分配出去了对象，因此有可能需要将slab移到其他链表中去*/  
            list_del(&slabp->list);  
            /*free等于BUFCTL_END表示空闲对象已耗尽，将slab插入full链表*/  
            if (slabp->free == BUFCTL_END)  
                list_add(&slabp->list, &l3->slabs_full);  
            else/*否则肯定是插入partial链表*/  
                list_add(&slabp->list, &l3->slabs_partial);  
        }  

    must_grow:  
        l3->free_objects -= ac->avail;/*刷新kmem_list3中的空闲对象*/  
    alloc_done:  
        spin_unlock(&l3->list_lock);  

        /*avail为0表示kmem_list3中的slab全部处于full状态或者没有slab,则要为缓存分配slab*/  
        if (unlikely(!ac->avail)) {  
            int x;  
            x = cache_grow(cachep, flags | GFP_THISNODE, node, NULL);  

            /* cache_grow can reenable interrupts, then ac could change. */  
            ac = cpu_cache_get(cachep);  
            if (!x && ac->avail == 0)    /* no objects in sight? abort */  
                return NULL;  

            if (!ac->avail)      /* objects refilled by interrupt? */  
                goto retry;  
        }  
        ac->touched = 1;  
        /*返回最后一个末端的对象*/  
        return ac->entry[--ac->avail];  
    }
```

对于所有slab都空闲对象的情况，需要调用cache_grow()来增加cache的容量，这个函数在后面分析slab的分配时再做介绍。

