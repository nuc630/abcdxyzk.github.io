---
layout: post
title: "理解Ksplice执行过程"
date: 2016-03-29 16:00:00 +0800
comments: false
categories:
- 2016
- 2016~03
- debug
- debug~ksplice
tags:
---

http://m.blog.chinaunix.net/uid-29280350-id-4717510.html

http://m.blog.chinaunix.net/uid-29280350-id-4906197.html

-----------

注：在Linux-3.0.0 到 linux-3.8.0上能够正常运行，超过3.8.13就会导致系统桌面崩溃                                                                                                                 
 
### 1.Ksplice-create

Ksplice-create用于创建补丁文件，根据用户提供的不同的更新文件，ksplice-create有三种不同的途径：  
  1）Patch文件  
  2）Diffext指定新文件的后缀  
  3）使用git指定新的标记  

同时，ksplice-create还需要指定orig_config_dir（指定config的目录），在该目录下要有以下几个文件：  
  1）当前run内核的System.map  
  2）当前run内核的.config  
  3）当前run内核的modules库下的build链接  
以上三项缺一不可。

 
#### 1.1配置

根据配置变量，组织make命令：
```
	make -rR
```

如果定义了jobs
```
	-jn
```

如果定义了verbose level

```
	V=1 否则 -s
```

make_ksplice 变量：
```
	@make -f $datadir/Makefile.ksplice @kbuild_flags
```

如果定义了build_modules
```
	KSPLICE_BUILD_MODULES=1
```

#### 1.2 Revert

配置变量完成后，ksplice-create会查找linux内核代码目录下是否会存在*.KSPLICE_presrc文件，存在该类型的文件则表明在该linux内核目录下曾制作过补丁文件，因此需要先将代码恢复为原始代码。
```
	my @revert_flags=("KSPLICE_MODE=revert");
		Revert_orig()
			Find出*.KSPLICE_presrc的文件，将之恢复为原始文件
			执行命令：make -rR -f Makefile.ksplice KSPLICE_MODE=revert

	进入Makefile.ksplice文件：
		Makefile.ksplice默认目标是__ksplice，
		__ksplice: $(ksplice-deps) $(ksplice-dirs)
			@:

		目标只是依赖两个dirs，没有具体的执行命令，所有的执行命令都是在依赖中执行的。对于ksplice-dirs的命令：

		$(ksplice-dirs):
			$(Q) $(MAKE) $(build)=$(@:_ksplice_%=%)
			其中
			build := -f $(ksplice-makefile) obj

			所以命令展开就是：
			make -f /usr/local/share/ksplice/Makefile.ksplice obj=arch/x86/crypto

			又再次进入makefile.ksplice，这次传入了obj。
```

revert的作用就是把.ksplice_pre的文件执行cmd_ksplice-revert。

最后通过$(call cmd, ksplice-revert)调用

```
	cmd_ksplice-revert = touch -r ksplice-revert-stamp $(@:_ksplice-revert_%=%); \
		mv $(@:_ksplice-revert_%=%) $(@:_ksplice-revert_%.KSPLICE_pre=%)
```
在然后根据ksplice-clean-files把ksplice生成的文件clean掉。
 
#### 1.3 SNAP

执行完revert之后，重新回到ksplice-create文件中继续执行
```
	@snap_flags = (“KSPLICE_MODE=snap”);
	runval_raw(@make_ksplice,@snap_flags)
```
展开即为：
```
	执行命令：make -rR -f Makefile.ksplice KSPLICE_MODE=snap
```

进入Makefile.ksplice文件：
```
	ifeq ($(KSPLICE_MODE),snap)
	$(obj)/%.o.KSPLICE: $(obj)/%.o FORCE
		$(if $(strip $(wildcard $<.KSPLICE_pre) $(filter $<, $?)), \
			$(call cmd, ksplice-snap))
		else
			$(obj)/%. o.KSPLICE:$(obj)/%.o
			$(call cmd, ksplice-diff)
		endif
```

其中
```
	cmd_ksplice-snap = $(ksplice-script) snap $@
	cmd_ksplice-diff = $(ksplice-script) diff $@
	ksplice-scrript = $(dir $(ksplice-makefile))ksplice-obj.pl
```

进入ksplice-obj.pl文件中:

```
	sub do_snap {
		my ($out) = @_;
		my ($obj) = $out = ~ /^(.*)\.KSPLICE$/ or die;
		die if (!-e $obj);
		unlink "$obj.KSPLICE_pre" if (-e "$obj.KSPLICE_pre");
		empty_diff($out);
	}
```

```
	sub empty_diff {
		my ($out) = @_;
		my ($obj) = $out =~ /^(.*)\.KSPLICE$/ or die;
		unlink "$obj.KSPLICE_new_code" if (-e "$obj.KSPLICE_new_code");
		unlink "$obj.KSPLICE_old_code" if (-e "$obj.KSPLICE_old_code");
		open OUT, '>', "$out.tmp";
		close OUT;
		rename "$out.tmp", $out;
	}
```

snap的工作就是生成一个.o.KSPLICE空文件，函数empty_diff就是用来生成空文件的。.o.KSPLICE文件用来作为一个标志位，只是为了后续diff阶段，如果有不同的.o就会把.o.KSPLICE中写入1，最后遍历所有的.o.KSPLICE，哪些为1就知道哪些有差异了。

```
	sub do_diff {
		my ($out) = @_;
		my ($obj) = $out =~ /^(.*)\.KSPLICE$/ or die;
		my $obj_pre = "$obj.KSPLICE_pre";
		die if (!-e $obj);
		die "Patch creates new object $obj" if (!-e $obj_pre);
		if (system('cmp', '-s', '--', $obj_pre, $obj) == 0) {
			unlink $obj_pre;
			return empty_diff($out);
		}

		runval("$libexecdir/ksplice-objmanip", $obj, "$obj.KSPLICE_new_code", "keep-new-code", "$obj.KSPLICE_pre", $ENV{KSPLICE_KID});
		return empty_diff($out) if (!-e "$obj.KSPLICE_new_code");

		open OUT, '>', "$out.tmp";
		print OUT "1\n";
		close OUT;
		rename "$out.tmp", $out;
		runval("$libexecdir/ksplice-objmanip", $obj_pre, "$obj.KSPLICE_old_code", "keep-old-code");
	}
```

无论snap还是diff都是要创建目标.o.KSPLICE, 但是动作不一样，并且snap是FORCE，diff不是强制的，最关键的就是打了patch之后，就会重新生成patch对应的.o，此时依赖条件更新了，就会执行diff命令。

#### 1.4 创建ksplice模块

将kmodsrc目录拷贝到tmp目录下，执行命令：
```
	@make_kmodsrc = (@make, "-C", $kernel_headers_dir, "M=$kmodsrc", "KSPLICE_KID=$kid", "KSPLICE_VERSION=1.0", "map_printk=$map_printk");
```

编译内核模块，然后make modules_install，
```
	@make_kmodsrc_install = (@make_kmodsrc, qw(modules_install --old-file=_modinst_post --old-file=_emodinst_post), "MAKE=make --old-file=_modinst_post --old-file=_emodinst_post", "INSTALL_MOD_STRIP=1", "MODLIB=$tmpdir/ksplice-modules");
```
 
#### 1.5 PATCH

将准备的patch文件更新到内核中：
```
	runval_infile($patchfile, "patch", @patch_opt, "-bz", ".KSPLICE_presrc")；
```

-bz的意思：  
-b 备份原始文件  
-z 是用.KSPLICE_presrc为后缀备份原始文件。  


要注意patch文件中各个文件的行号等内容要对齐，不然patch文件无法更新到内核源码中（要每个文件都要检查，并确认patch文件可用）。

打上补丁后，执行：
```
	make_ksplice KSPLICE_MODE=diff
```

#### 1.6 DIFF

```
	my @diff_flags = ("KSPLICE_MODE=diff")
	runval_raw(@make_ksplice, @diff_flags);
```

即执行命令：
```
	make -rR -f Makefile.ksplice KSPLICE_MODE=diff
```

进入Makefile.ksplice文件：
```
	ifeq ($(KSPLICE_MODE),diff)
		define ksplice-cow-check
			$(if $(strip $(1)),$(if $(filter-out %.KSPLICE,$@),$(if $(wildcard $@),$(if $(wildcard $@.KSPLICE_pre),,$(call cmd,ksplice-cow)))))$(1)
		endef

		define ksplice-add-cow-check
			$(v) = $$(call ksplice-cow-check,$(value $(v)))
		endef

		ksplice-cow-eval += $(foreach v,if_changed if_changed_dep if_changed_rule,$(ksplice-add-cow-check))
	endif   # KSPLICE_MODE
```

其中
```
	cmd_ksplice-cow = cp -a $@ $@.KSPLICE_pre
```

diff比较的是.o.KSPLICE_pre 和 新编译的.o，从do_diff的实现来看，在diff之前，KSPLICE_pre就已经生成了，生成KSPLICE_pre的命令只有cmd-ksplice-cow, 即diff操作的结果。

```
	$KSPLICE_MODE ?= diff
	ifeq ($(KSPLICE_MODE),snap)
		$(obj)/%.o.KSPLICE: $(obj)/%.o FORCE
			$(if $(strip $(wildcard $<.KSPLICE_pre) $(filter $<, $?)), \
				$(call cmd, ksplice-snap))
	else
		$(obj)/%. o.KSPLICE:$(obj)/%.o
		$(call cmd, ksplice-diff)
	endif
```
在此处调用
```
	cmd_ksplice-diff=$(ksplice-script) diff $@
```

进入ksplice-obj.pl中调用函数do_diff

```
	sub do_diff {
		my ($out) = @_;
		my ($obj) = $out =~ /^(.*)\.KSPLICE$/ or die;
		my $obj_pre = "$obj.KSPLICE_pre";
		die if (!-e $obj);
		die "Patch creates new object $obj" if (!-e $obj_pre);
		if (system('cmp', '-s', '--', $obj_pre, $obj) == 0) {
			unlink $obj_pre;
			return empty_diff($out);
		}
		runval("$libexecdir/ksplice-objmanip", $obj, "$obj.KSPLICE_new_code", "keep-new-code", "$obj.KSPLICE_pre", $ENV{KSPLICE_KID});
		return empty_diff($out) if (!-e "$obj.KSPLICE_new_code");

		open OUT, '>', "$out.tmp";
		print OUT "1\n";
		close OUT;
		rename "$out.tmp", $out;

		runval("$libexecdir/ksplice-objmanip", $obj_pre, "$obj.KSPLICE_old_code", "keep-old-code");
	}
```

此处有三个关键点，第一system系统调用cmp，比较$(obj)和$obj_pre之间的不同，第二通过调用ksplice-objmanip（即objmanip）生成new_code，并且在.o.KSPLICE_pre中写入标志位1，第三步调用ksplice-objmanip（即objmanip）将未打patch之前的代码生成old_code。第二步和第三步进入到C文件objmanip.c的main()函数中，根据传入的参数的不同，调用不同的函数，最后生成new和old。


#### 1.7 模块编译

命令：
```
	runstr（qw(find -name *.KSPLCE* !  ( - name *.KSPLICE -empty ) ! -name .*.KSPLICE.cmd -print0)）
```

找出所有*.KSPLICE*非空的文件，将读入的内容保存到@modules中。对MOD的处理是在KSPLICE_KMODSRC中生成的。

命令：
```
	runval(@make_ksplice, "KSPLICE_MODE=modinst", "MODLIB=$tmpdir/modules", "INSTALL_MOD_STRIP=1", "modules=@modulepaths");
```

在Makefile.ksplice中，对modinst的处理是：
```
	ifeq ($(KSPLICE_MODE),modinst)
	ksplice-deps += ksplice_modinst
	PHONY += ksplice_modinst
	ksplice_modinst:
		$(Q) $(MAKE) –f $(srctree)/scripts/Makefile.modinst
	endif
```

这里的Makefile.modinst和Makefile.modpost都是内核script中的Makefile。

在ksplice-create中分别调用了两次make_kmodsrc， 第一次编译出ksplice.ko模块，第二次传入参数KSPLICE_MODULES=@modules 生成new.ko 和 old.ko文件。在kmodsrc目录中的Makefile中，第一次编译的是KSPLICE_CORE:
```
	KSPLICE_CORE = ksplice-$(KSPLICE_KID)
	obj-m += $(KSPLICE_CORE).o
```

实际上最终编译生成ksplice-kid.ko 还是依靠的obj-m的方法编译的。

第二次编译的时候传入的modules，同时KSPLICE_SKIP_CORE=1，表示不编译ksplice.ko

在ksplice-create中，执行命令：
```
	runval(@make_kmodsrc, "KSPLICE_MODULES=@modules", "KSPLICE_SKIP_CORE=1");
	runval(@make_kmodsrc_install, "KSPLICE_MODULES=@modules", "KSPLICE_SKIP_CORE=1");
```

在kmodsrc/Makefile中：

```
	ifneq ($(KSPLICE_MODULES),)
		$(foreach mod,$(KSPLICE_MODULES),$(obj)/new-code-$(target).o): $(obj)/%.o: $ (src)/new_code_loader.c FORCE
		$(call if_changed_rule,cc_o_c)
		$(foreach mod,$(KSPLICE_MODULES),$(obj)/old-code-$(target).o): $(obj)/%.o: $ (src)/old_code_loader.c FORCE
		$(call if_changed_rule,cc_o_c)
	endif
```

以new为例：
```
	$(KSPLICE)-n-objs = $(ksplice-new-code-objs)
	ksplice-new-code-objs = new-code-$(target).o collect-new-code-$(mod).o
```

new.ko由new-code-mod.o 和 collect-new-code-$(mod).o 组成。

new-code-mod.o的命令：

```
	$(foreach mod,$(KSPLICE_MODULES),$(obj)/new-code-$(target).o): $(obj)/%.o: \
		$ (src)/new_code_loader.c FORCE
	$(call if_changed_rule,cc_o_c)
```

collect-new-code-$(mod).o的命令：

```
	$(obj)/collect-new-code-%.o: $(obj)/%.o.KSPLICE_new_code $(obj)/ksplice.lds     FORCE
	$(call if_changed,ksplice-collect)
	cmd_ksplice-collect = \
		$(ksplice-script) finalize $< $<.final $* && \
		$(LD) --script=$(obj)/ksplice.lds -r -o $@ $<.final
```

collect的命令最后调用do_finalize生成mod.final，再结合ksplice.lds 生成collect-new-code-mod.o

 
### 2.ksplice-apply

#### 2.1 校验补丁文件

第一，执行命令：chdir(unpack_update($file))

其中 unpack_update()在文件Ksplice.pm中，首先检测使用的补丁文件是否是目录，如果是则返回到ksplice-apply文件中；如果是压缩文件则将其解压到/tmp/临时目录下，然后将路径返回到ksplice-apply文件中。

第二，检测目标路径中是否存在contents文件，不存在就退出ksplice-apply程序。

第三，检测当前系统/sys/moudle下面是否已经加载了该补丁文件。

在上述操作中，如果有不满足要求的，通过设置apply_errors来输出错误信息。


#### 2.2 加载补丁文件

执行命令load_module($change->{new_code_file})
```
	sub load_module {
		my ($module, @params) = @_;
		push @modules_loaded, ($module =~ m/^(.)\.ko$/);
		if (runval_raw("insmod", $module, @params) != 0){
			pop @modules_loaded;
			child_error();
			return 0;
		}
		return 1;
	}
```
在函数load_module()中调用系统函数insmod来加载ko文件。如果在加载过程中出现错误，由insmod返回错误信息。

