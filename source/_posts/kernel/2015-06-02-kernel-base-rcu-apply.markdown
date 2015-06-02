---
layout: post
title: "Linux kernel 内存屏障在RCU上的应用"
date: 2015-06-02 17:36:00 +0800
comments: false
categories:
- 2015
- 2015~06
- kernel
- kernel~base
tags:
---
http://blog.csdn.net/jianchaolv/article/details/7527647

内存屏障主要解决的问题是编译器的优化和CPU的乱序执行。

编译器在优化的时候，生成的汇编指令可能和c语言程序的执行顺序不一样，在需要程序严格按照c语言顺序执行时，需要显式的告诉编译不需要优化，这在linux下是通过barrier()宏完成的，它依靠volidate关键字和memory关键字，前者告诉编译barrier()周围的指令不要被优化，后者作用是告诉编译器汇编代码会使内存里面的值更改，编译器应使用内存里的新值而非寄存器里保存的老值。

同样，CPU执行会通过乱序以提高性能。汇编里的指令不一定是按照我们看到的顺序执行的。linux中通过mb()系列宏来保证执行的顺序。简单的说，如果在程序某处插入了mb()/rmb()/wmb()宏，则宏之前的程序保证比宏之后的程序先执行，从而实现串行化。

即使是编译器生成的汇编码有序，处理器也不一定能保证有序。就算编译器生成了有序的汇编码，到了处理器那里也拿不准是不 是会按照代码顺序执行。所以就算编译器保证有序了，程序员也还是要往代码里面加内存屏障才能保证绝对访存有序，这倒不如编译器干脆不管算了，因为内存屏障 本身就是一个sequence point，加入后已经能够保证编译器也有序。


处理器虽然乱序执行，但最终会得出正确的结果，所以逻辑上讲程序员本不需要关心处理器乱序的问题。但是在SMP并发执行的情况下，处理器无法知道并发程序之间的逻辑，比如，在不同core上的读者和写者之间的逻辑。简单讲，处理器只保证在单个core上按照code中的顺序给出最终结果。这就要求程序员通过mb()/rmb()/wmb()/read_barrier_depends来告知处理器，从而得到正确的并发结果。内存屏障、数据依赖屏障都是为了处理SMP环境下的数据同步问题，UP根本不存在这个问题。

下面分析下内存屏障在RCU上的应用：
```
	#define rcu_assign_pointer(p, v) ({ \
		smp_wmb();                      \
		(p)= (v);                       \
	})

	#define rcu_dereference(p) ({     \
		typeof(p)_________p1 = p;     \
		smp_read_barrier_depends();   \
		(_________p1);                \
	}) 
```
        
rcu_assign_pointer()通常用于写者的发布，rcu_dereference()通常用于读者的订阅。

写者：
```
	p->a = 1;
	p->b = 2;
	p->c = 3;
	rcu_assign_pointer(gp, p);
```

读者：
```
	rcu_read_lock();
	p = rcu_dereference(gp);
	if (p != NULL) {
		do_something_with(p->a, p->b, p->c);
	}
	rcu_read_unlock();
```

rcu_assign_pointer()是说，先把那块内存写好，再把指针指过去。这里使用的内存写屏障是为了保证并发的读者读到数据一致性。在这条语句之前的读者读到旧的指针和旧的内存，这条语句之后的读者读到新的指针和新的内存。如果没有这条语句，很有可能出现读者读到新的指针和旧的内存。也就是说，这里通过内存屏障刷新了p所指向的内存的值，至于gp本身的值有没有更新还不确定。实际上，gp本身值的真正更新要等到并发的读者来促发。

rcu_dereference() 原语用的是数据依赖屏障，smp_read_barrier_dependence,它要求后面的读操作如果依赖前面的读操作，则前面的读操作需要首先完成。根据数据之间的依赖，要读p->a, p->b, p->c, 就必须先读p，要先读p，就必须先读p1，要先读p1，就必须先读gp。也就是说读者所在的core在进行后续的操作之前，gp必须是同步过的当前时刻的最新值。如果没有这个数据依赖屏障，有可能读者所在的core很长一段时间内一直用的是旧的gp值。所以，这里使用数据依赖屏障是为了督促写者将gp值准备好，是为了呼应写者，这个呼应的诉求是通过数据之间的依赖关系来促发的，也就是说到了非呼应不可的地步了。

下面看看kernel中常用的链表操作是如何使用这样的发布、订阅机制的：

写者：
```
	static inline void list_add_rcu(struct list_head *new, struct list_head *head)
	{
		__list_add_rcu(new, head, head->next);
	}

	static inline void __list_add_rcu(struct list_head * new,
	struct list_head * prev, struct list_head * next)
	{
		new->next = next;
		new->prev = prev;
		smp_wmb();
		next->prev = new;
		prev->next = new;
	}
```

读者：

```
	#define list_for_each_entry_rcu(pos, head, member)                \
		for(pos = list_entry((head)->next, typeof(*pos), member);     \
				prefetch(rcu_dereference(pos)->member.next),          \
				&pos->member!= (head);                                \
			pos= list_entry(pos->member.next, typeof(*pos), member))
```

写者通过调用list_add_rcu来发布新的节点，其实是发布next->prev, prev->next这两个指针。读者通过list_for_each_entry_rcu来订阅这连个指针，我们将list_for_each_entry_rcu订阅部分简化如下：

```
	pos = prev->next;
	prefetch(rcu_dereference(pos)->next);
```

读者通过rcu_dereference订阅的是pos，而由于数据依赖关系，又间接订阅了prev->next指针，或者说是促发prev->next的更新。

下面介绍下其他相关链表操作的函数：

safe版本的iterate的函数？为什么就safe了？

```
	#define list_for_each_safe(pos,n, head)                    \
		for(pos = (head)->next, n = pos->next; pos != (head);  \
				pos= n, n = pos->next)

	#define list_for_each(pos, head)                                \
		for(pos = (head)->next; prefetch(pos->next), pos != (head); \
				pos= pos->next)
```

当在iterate的过程中执行删除操作的时候，比如：
```
	list_for_each(pos,head)
		list_del(pos)
```
这样会断链，为了避免这种断链，增加了safe版本的iterate函数。另外，由于preftech的缘故，有可能引用一个无效的指针LIST_POISON1。这里的safe是指，为避免有些cpu的preftech的影响，干脆在iterate的过程中去掉preftech。

还有一个既有rcu+safe版本的iterative函数：
```
	#define list_for_each_safe_rcu(pos, n, head)              \
		for(pos = (head)->next;                               \
				n= rcu_dereference(pos)->next, pos != (head); \
				pos= n)
```

只要用这个版本的iterate函数，就可以和多个_rcu版本的写操作(如：list_add_rcu())并发执行。


