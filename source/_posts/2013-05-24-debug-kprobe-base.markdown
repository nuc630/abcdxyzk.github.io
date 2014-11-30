---
layout: post
title: "Linux内核kprobe机制"
date: 2013-05-24 10:22:00 +0800
comments: false
categories:
- 2013
- 2013~05
- debug
- debug~kprobe
tags:
---
* 探测点处理函数在运行时是失效抢占的，依赖于特定的架构，探测点处理函数运行时也可能是中断失效的。  
* 因此，对于任何探测点处理函数，不要使用导致睡眠或进程调度的任何内核函数（如尝试获得semaphore)。

  Kprobe机制是内核提供的一种调试机制，它提供了一种方法，能够在不修改现有代码的基础上，灵活的跟踪内核函数的执行。它的基本工作原理是：用户指定一个探测点，并把一个用户定义的处理函数关联到该探测点，当内核执行到该探测点时，相应的关联函数被执行，然后继续执行正常的代码路径。

  Kprobe提供了三种形式的探测点，一种是最基本的kprobe，能够在指定代码执行前、执行后进行探测，但此时不能访问被探测函数内的相关变量信 息；一种是jprobe，用于探测某一函数的入口，并且能够访问对应的函数参数；一种是kretprobe，用于完成指定函数返回值的探测功能。其中最基 本的就是kprobe机制，jprobe以及kretprobe的实现都依赖于kprobe，但其代码的实现都很巧妙，强烈建议每一个内核爱好者阅读。
	
#### 代码：
##### 首先是struct kprobe结构，每一个探测点的基本结构。
```
	structkprobe {
		/*用于保存kprobe的全局hash表，以被探测的addr为key*/
		structhlist_node hlist;

		/* list of kprobes for multi-handler support */
		/*当对同一个探测点存在多个探测函数时，所有的函数挂在这条链上*/
		structlist_head list;

		/*count the number of times this probe was temporarily disarmed */
		unsigned longnmissed;

		/* location of the probe point */
		/*被探测的目标地址*/
		kprobe_opcode_t *addr;

		/* Allow user to indicate symbol name of the probe point */
		/*symblo_name的存在，允许用户指定函数名而非确定的地址*/
		constchar*symbol_name;

		/* Offset into the symbol */
		/*如果被探测点为函数内部某个指令，需要使用addr + offset的方式*/
		unsigned intoffset;

		/* Called before addr is executed. */
		/*探测函数，在目标探测点执行之前调用*/
		kprobe_pre_handler_t pre_handler;

		/* Called after addr is executed, unless... */
		/*探测函数，在目标探测点执行之后调用*/
		kprobe_post_handler_t post_handler;

		/*
		 * ... called if executing addr causes a fault (eg. page fault).
		 * Return 1 if it handled fault, otherwise kernel will see it.
		 */
		kprobe_fault_handler_t fault_handler;

		/*
		 * ... called if breakpoint trap occurs in probe handler.
		 * Return 1 if it handled break, otherwise kernel will see it.
		 */
		kprobe_break_handler_t break_handler;

		/*opcode 以及 ainsn 用于保存被替换的指令码*/
	
		/* Saved opcode (which has been replaced with breakpoint) */
		kprobe_opcode_t opcode;

		/* copy of the original instruction */
		structarch_specific_insn ainsn;

		/*
		 * Indicates various status flags.
		 * Protected by kprobe_mutex after this kprobe is registered.
		 */
		u32 flags;
	};
```
  对于kprobe功能的实现主要利用了内核中的两个功能特性：异常（尤其是int 3），单步执行（EFLAGS中的TF标志）。

##### 大概的流程：
```
 1）在注册探测点的时候，对被探测函数的指令码进行替换，替换为int 3的指令码；
 2）在执行int 3的异常执行中，通过通知链的方式调用kprobe的异常处理函数；
 3）在kprobe的异常出来函数中，判断是否存在pre_handler钩子，存在则执行；
 4）执行完后，准备进入单步调试，通过设置EFLAGS中的TF标志位，并且把异常返回的地址修改为保存的原指令码；
 5）代码返回，执行原有指令，执行结束后触发单步异常；
 6）在单步异常的处理中，清除单步标志，执行post_handler流程，并最终返回；
```
  下面又进入代码时间，首先看一下kprobe模块的初始化代码，初始化代码主要做了两件事：标记出哪些代码是不能被探测的，这些代码属于kprobe实现的关键代码；注册通知链到die_notifier，用于接收异常通知。

##### 初始化代码位于kernel/kprobes.c中
```
	staticint__init init_kprobes(void)
	{
		inti,err =0;
			....

		 /*kprobe_blacklist中保存的是kprobe实现的关键代码路径，这些函数不应该被kprobe探测*/
		/*
		 * Lookup and populate the kprobe_blacklist.
		 *
		 * Unlike the kretprobe blacklist, we'll need to determine
		 * the range of addresses that belong to the said functions,
		 * since a kprobe need not necessarily be at the beginning
		 * of a function.
		 */
		for(kb =kprobe_blacklist;kb->name!=NULL;kb++){
			kprobe_lookup_name(kb->name,addr);
			if(!addr)
				continue;

			kb->start_addr =(unsigned long)addr;
			symbol_name =kallsyms_lookup(kb->start_addr,
					&size,&offset,&modname,namebuf);
			if(!symbol_name)
				kb->range =0;
			else
				kb->range =size;
		}
			....
		if(!err)
			/*注册通知链到die_notifier，用于接收int 3的异常信息*/
			err =register_die_notifier(&kprobe_exceptions_nb);
			 ....
	}
```
##### 其中的通知链：
```
	staticstructnotifier_block kprobe_exceptions_nb ={
		.notifier_call =kprobe_exceptions_notify,
		/*优先级最高，保证最先执行*/
		.priority =0x7fffffff /* we need to be notified first */
	};
```
###### kprobe的注册流程register_kprobe。
```
	int__kprobes register_kprobe(structkprobe *p)
	{
		intret =0;
		structkprobe *old_p;
		structmodule *probed_mod;
		kprobe_opcode_t *addr;

		/*获取被探测点的地址，指定了symbol_name，则从kallsyms中获取；指定了offset，则返回addr + offset*/
		addr =kprobe_addr(p);
		if(!addr)
			return-EINVAL;
		p->addr =addr;

		/*判断同一个kprobe是否被重复注册*/
		ret =check_kprobe_rereg(p);
		if(ret)
			returnret;

		jump_label_lock();
		preempt_disable();
		/*判断被注册的函数是否位于内核的代码段内，或位于不能探测的kprobe实现路径中*/
		if(!kernel_text_address((unsigned long)p->addr)||
			in_kprobes_functions((unsigned long)p->addr)||
			ftrace_text_reserved(p->addr,p->addr)||
			jump_label_text_reserved(p->addr,p->addr))
			gotofail_with_jump_label;

		/* User can pass only KPROBE_FLAG_DISABLED to register_kprobe */
		p->flags&=KPROBE_FLAG_DISABLED;

		/*
		 * Check if are we probing a module.
		 */
		/*判断被探测的地址是否属于某一个模块，并且位于模块的text section内*/
		probed_mod =__module_text_address((unsigned long)p->addr);
		if(probed_mod){
			/*如果被探测的为模块地址，首先要增加模块的引用计数*/
			/*
			 * We must hold a refcount of the probed module while updating
			 * its code to prohibit unexpected unloading.
			 */
			if(unlikely(!try_module_get(probed_mod)))
				gotofail_with_jump_label;

			/*
			 * If the module freed .init.text, we couldn't insert
			 * kprobes in there.
			 */
			/*如果被探测的地址位于模块的init地址段内，但该段代码区间已被释放，则直接退出*/
			if(within_module_init((unsigned long)p->addr,probed_mod)&&
				probed_mod->state!=MODULE_STATE_COMING){
				module_put(probed_mod);
				gotofail_with_jump_label;
			}
		}
		preempt_enable();
		jump_label_unlock();

		p->nmissed =0;
		INIT_LIST_HEAD(&p->list);
		mutex_lock(&kprobe_mutex);

		jump_label_lock();/* needed to call jump_label_text_reserved() */

		get_online_cpus();	/* For avoiding text_mutex deadlock. */
		mutex_lock(&text_mutex);

		/*判断在同一个探测点是否已经注册了其他的探测函数*/
		old_p =get_kprobe(p->addr);
		if(old_p){
			/* Since this may unoptimize old_p, locking text_mutex. */
			/*如果已经存在注册过的kprobe，则将探测点的函数修改为aggr_pre_handler，并将所有的handler挂载到其链表上，由其负责所有handler函数的执行*/
			ret =register_aggr_kprobe(old_p,p);
			gotoout;
		}

		/* 分配特定的内存地址用于保存原有的指令
		 * 按照内核注释，被分配的地址必须must be on special executable page on x86.
		 * 该地址被保存在kprobe->ainsn.insn
		 */
		ret =arch_prepare_kprobe(p);
		if(ret)
			gotoout;

		/*将kprobe加入到相应的hash表内*/
		INIT_HLIST_NODE(&p->hlist);
		hlist_add_head_rcu(&p->hlist,
				   &kprobe_table[hash_ptr(p->addr,KPROBE_HASH_BITS)]);

		if(!kprobes_all_disarmed &&!kprobe_disabled(p))
	/*将探测点的指令码修改为int 3指令*/
			__arm_kprobe(p);

		/* Try to optimize kprobe */
		try_to_optimize_kprobe(p);

	out:
		mutex_unlock(&text_mutex);
		put_online_cpus();
		jump_label_unlock();
		mutex_unlock(&kprobe_mutex);

		if(probed_mod)
			module_put(probed_mod);

		returnret;

	fail_with_jump_label:
		preempt_enable();
		jump_label_unlock();
		return-EINVAL;
```
##### 注册完毕，就开始kprobe的执行流程了。对于该探测点，由于其起始指令已经被修改为int3，因此在执行到该地址时，必然会触发3号中断向量的处理流程do_int3.
```
	/* May run on IST stack. */
	dotraplinkage void__kprobes do_int3(structpt_regs *regs,longerror_code)
	{
	#ifdef CONFIG_KGDB_LOW_LEVEL_TRAP
		if(kgdb_ll_trap(DIE_INT3,"int3",regs,error_code,3,SIGTRAP)
				==NOTIFY_STOP)
			return;
	#endif /* CONFIG_KGDB_LOW_LEVEL_TRAP */
	#ifdef CONFIG_KPROBES
		/*在这里以DIE_INT3，通知kprobe注册的通知链*/
		if(notify_die(DIE_INT3,"int3",regs,error_code,3,SIGTRAP)
				==NOTIFY_STOP)
			return;
	#else
		if(notify_die(DIE_TRAP,"int3",regs,error_code,3,SIGTRAP)
				==NOTIFY_STOP)
			return;
	#endif

		preempt_conditional_sti(regs);
		do_trap(3,SIGTRAP,"int3",regs,error_code,NULL);
		preempt_conditional_cli(regs);
	}
```
##### 在do_int3中触发kprobe注册的通知链函数，kprobe_exceptions_notify。由于kprobe以及jprobe等机制的处 理核心都在此函数内，这里只针对kprobe的流程进行分析：进入函数的原因是DIE_INT3,并且是第一次进入该函数。
```
	int__kprobes kprobe_exceptions_notify(structnotifier_block *self,
						   unsigned longval,void*data)
	{
		structdie_args *args =data;
		intret =NOTIFY_DONE;

		if(args->regs &&user_mode_vm(args->regs))
			returnret;

		switch(val){
		caseDIE_INT3:
	/*对于kprobe，进入kprobe_handle*/
			if(kprobe_handler(args->regs))
				ret =NOTIFY_STOP;
			break;
		caseDIE_DEBUG:
			if(post_kprobe_handler(args->regs)){
				/*
				 * Reset the BS bit in dr6 (pointed by args->err) to
				 * denote completion of processing
				 */
				(*(unsigned long*)ERR_PTR(args->err))&=~DR_STEP;
				ret =NOTIFY_STOP;
			}
			break;
		caseDIE_GPF:
			/*
			 * To be potentially processing a kprobe fault and to
			 * trust the result from kprobe_running(), we have
			 * be non-preemptible.
			 */
			if(!preemptible()&&kprobe_running()&&
				kprobe_fault_handler(args->regs,args->trapnr))
				ret =NOTIFY_STOP;
			break;
		default:
			break;
		}
		returnret;
	}

	staticint__kprobes kprobe_handler(structpt_regs *regs)
	{
		kprobe_opcode_t *addr;
		structkprobe *p;
		structkprobe_ctlblk *kcb;

		/*对于int 3中断，其被Intel定义为Trap，那么异常发生时EIP寄存器内指向的为异常指令的后一条指令*/
		addr =(kprobe_opcode_t *)(regs->ip -sizeof(kprobe_opcode_t));
		/*
		 * We don't want to be preempted for the entire
		 * duration of kprobe processing. We conditionally
		 * re-enable preemption at the end of this function,
		 * and also in reenter_kprobe() and setup_singlestep().
		 */
		preempt_disable();

		kcb =get_kprobe_ctlblk();
		/*获取addr对应的kprobe*/
		p =get_kprobe(addr);

		if(p){
	/*如果异常的进入是由kprobe导致，则进入reenter_kprobe(jprobe需要，到时候分析)*/
			if(kprobe_running()){
				if(reenter_kprobe(p,regs,kcb))
					return1;
			}else{
				set_current_kprobe(p,regs,kcb);
				kcb->kprobe_status =KPROBE_HIT_ACTIVE;

				/*
				 * If we have no pre-handler or it returned 0, we
				 * continue with normal processing.  If we have a
				 * pre-handler and it returned non-zero, it prepped
				 * for calling the break_handler below on re-entry
				 * for jprobe processing, so get out doing nothing
				 * more here.
				 */
		/*执行在此地址上挂载的pre_handle函数*/
				if(!p->pre_handler ||!p->pre_handler(p,regs))
	/*设置单步调试模式，为post_handle函数的执行做准备*/
					setup_singlestep(p,regs,kcb,0);
				return1;
			}
		}elseif(*addr !=BREAKPOINT_INSTRUCTION){
			/*
			 * The breakpoint instruction was removed right
			 * after we hit it.  Another cpu has removed
			 * either a probepoint or a debugger breakpoint
			 * at this address.  In either case, no further
			 * handling of this interrupt is appropriate.
			 * Back up over the (now missing) int3 and run
			 * the original instruction.
			 */
			regs->ip =(unsigned long)addr;
			preempt_enable_no_resched();
			return1;
		}elseif(kprobe_running()){
			p =__this_cpu_read(current_kprobe);
			if(p->break_handler &&p->break_handler(p,regs)){
				setup_singlestep(p,regs,kcb,0);
				return1;
			}
		}/* else: not a kprobe fault; let the kernel handle it */

		preempt_enable_no_resched();
		return0;
	}

	staticvoid__kprobes setup_singlestep(structkprobe *p,structpt_regs *regs,
						   structkprobe_ctlblk *kcb,intreenter)
	{
		if(setup_detour_execution(p,regs,reenter))
			return;

	#if!defined(CONFIG_PREEMPT)
		if(p->ainsn.boostable ==1 &&!p->post_handler){
			/* Boost up -- we can execute copied instructions directly */
			if(!reenter)
				reset_current_kprobe();
			/*
			 * Reentering boosted probe doesn't reset current_kprobe,
			 * nor set current_kprobe, because it doesn't use single
			 * stepping.
			 */
			regs->ip =(unsigned long)p->ainsn.insn;
			preempt_enable_no_resched();
			return;
		}
	#endif
		/*jprobe*/
		if(reenter){
			save_previous_kprobe(kcb);
			set_current_kprobe(p,regs,kcb);
			kcb->kprobe_status =KPROBE_REENTER;
		}else
			kcb->kprobe_status =KPROBE_HIT_SS;
		/* Prepare real single stepping */
		/*准备单步模式，设置EFLAGS的TF标志位，清楚IF标志位(禁止中断)*/
		clear_btf();
		regs->flags|=X86_EFLAGS_TF;
		regs->flags&=~X86_EFLAGS_IF;
		/* single step inline if the instruction is an int3 */
		if(p->opcode ==BREAKPOINT_INSTRUCTION)
			regs->ip =(unsigned long)p->addr;
		else
	/*设置异常返回的指令为保存的被探测点的指令*/
			regs->ip =(unsigned long)p->ainsn.insn;
	}
```
##### 对应kprobe,pre_handle的执行就结束了，按照代码，程序开始执行保存的被探测点的指令，由于开启了单步调试模式，执行完指令后会继续触发异常，这次的是do_debug异常处理流程。
```
	dotraplinkage void__kprobes do_debug(structpt_regs *regs,longerror_code)
	{
		....

		/*在do_debug中，以DIE_DEBUG再一次触发kprobe的通知链*/
		if(notify_die(DIE_DEBUG,"debug",regs,PTR_ERR(&dr6),error_code,
								SIGTRAP)==NOTIFY_STOP)
			return;
	   
		....
		return;
	}

	/*对于kprobe_exceptions_notify，其DIE_DEBUG处理流程*/
	caseDIE_DEBUG:
			if(post_kprobe_handler(args->regs)){
				/*
				 * Reset the BS bit in dr6 (pointed by args->err) to
				 * denote completion of processing
				 */
				(*(unsigned long*)ERR_PTR(args->err))&=~DR_STEP;
				ret =NOTIFY_STOP;
			}
			break;

	staticint__kprobes post_kprobe_handler(structpt_regs *regs)
	{
		structkprobe *cur =kprobe_running();
		structkprobe_ctlblk *kcb =get_kprobe_ctlblk();

		if(!cur)
			return0;

		/*设置异常返回的EIP为下一条需要执行的指令*/
		resume_execution(cur,regs,kcb);
		/*恢复异常执行前的EFLAGS*/
		regs->flags|=kcb->kprobe_saved_flags;

		/*执行post_handler函数*/
		if((kcb->kprobe_status !=KPROBE_REENTER)&&cur->post_handler){
			kcb->kprobe_status =KPROBE_HIT_SSDONE;
			cur->post_handler(cur,regs,0);
		}

		/* Restore back the original saved kprobes variables and continue. */
		if(kcb->kprobe_status ==KPROBE_REENTER){
			restore_previous_kprobe(kcb);
			gotoout;
		}
		reset_current_kprobe();
	out:
		preempt_enable_no_resched();

		/*
		 * if somebody else is singlestepping across a probe point, flags
		 * will have TF set, in which case, continue the remaining processing
		 * of do_debug, as if this is not a probe hit.
		 */
		if(regs->flags&X86_EFLAGS_TF)
			return0;

		return1;
	}
```
至此，一个典型的kprobe的流程已经执行完毕了。

