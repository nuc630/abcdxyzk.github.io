---
layout: post
title: "HAProxy 研究笔记 -- rules 实现"
date: 2015-07-29 16:00:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://blog.chinaunix.net/uid-10167808-id-3775567.html

本文研究 haproxy-1.5-dev17 中 rules 的相关实现。

```
    1. ACL
    2. rule 的组成
    3. rule 的执行
    4. rule 的种类
```

#### 1. ACL

如果要实现功能丰富的 rules，需要有配套的 ACL 机制。

ACL 的格式如下：
```
    acl [flags] [operator] ... 
```

haproxy 中 ACL 数据结构的定义：

```
	/* The acl will be linked to from the proxy where it is declared */
	struct acl {
		struct list list;           /* chaining */
		char *name;		    /* acl name */
		struct list expr;	    /* list of acl_exprs */
		int cache_idx;              /* ACL index in cache */
		unsigned int requires;      /* or'ed bit mask of all acl_expr's ACL_USE_* */
	};
```

其中：

```
    name: ACL 的名字
    expr: ACL 定义的表达式。就是定义的 ACL 名字后面的表达式。这是一个链表结构。因此，可以定义多条表达式不同但是名字相同的 ACL。这样，多个表达式都属于同一个 ACL。
    requires: 所有表达式中关键字对应的作用域（该关键字可以用在什么场合）的集合

函数 parse_acl() 负责解析定义好的 ACL:

    查找 ACL 的名字，如果不存在的话，则 alloc 一个新的 acl 结构
    通过调用 parse_acl_expr() 对表达式进行解析，并返回 struct acl_expr 结构
        ACL 中的表达式应该只有一个 kw
        查找该关键字，必须是已经注册好的。并返回该关键字注册时的数据结构 struct acl_expr
        alloc 一个 struct acl_expr 结构体，记录下返回的 kw 的数据结构，并作成员的初始化
        调用对应 kw 的 parse 方法，将解析的结果保存在 struct acl_pattern 结构体中，并将该结构体加入到 expr->patterns 的链表中
    将解析到的表达式插入到 acl 中的 expr 链表中
```

总结： 一个 ACL 包含一到多个表达式。每个表达式包含一个 kw及一到多个 pattern。

#### 2. rule 的组成

这里简要描述 rule 与 acl 之间的逻辑关系：

```
    rule 应该是 action + condition 组成
        有些动作自身可能也需要记录一些信息。不同的 rule 对应动作的信息可能不同，比如 reqirep 等
        block rules 的动作比较单一， condition 满足之后处理结果均相同
    condition，完成 rule 检测的判断条件 对应数据结构： struct acl_cond

            struct acl_cond {
            	struct list list;           /* Some specific tests may use multiple conditions */
            	struct list suites;         /* list of acl_term_suites */
            	int pol;                    /* polarity: ACL_COND_IF / ACL_COND_UNLESS */
            	unsigned int requires;      /* or'ed bit mask of all acl's ACL_USE_* */
            	const char *file;           /* config file where the condition is declared */
            	int line;                   /* line in the config file where the condition is declared */
            };
            

    condition 包含多个 ACL 组。组的分割逻辑是逻辑或（|| 或者 or），即 struct list suites 的成员，组的数据结构 struct acl_term_suite

        struct acl_term_suite {
        	struct list list;           /* chaining of term suites */
        	struct list terms;          /* list of acl_terms */
        };

        该数据结构可以包含多个 ACL，以及每个 ACL 可能的一个取反标识 '!'
        所有表达式中相邻的 ACL 且其逻辑关系为逻辑与(&&) 的构成一个 ACL 组
            比如 if acl1 !acl2 or acl3 acl4，则构成两个 acl_term_suite，分别是 acl1 !acl2 和 acl3 acl4
            每个 ACL 及其可能的取反标记对应的数据结构： struct acl_term

                struct acl_term {
                	struct list list;           /* chaining */
                	struct acl *acl;            /* acl pointed to by this term */
                	int neg;                    /* 1 if the ACL result must be negated */
                };

        一个 ACL 包含多个 expr
```

#### 3. rule 的执行

概括起来很简单，执行判断条件。符合条件，然后执行对应动作。

下面是 rspadd 的示例代码：

```
	/* add response headers from the rule sets in the same order */
	list_for_each_entry(wl, &rule_set->rsp_add, list) {
		if (txn->status < 200)
			break;
		if (wl->cond) {
			int ret = acl_exec_cond(wl->cond, px, t, txn, SMP_OPT_DIR_RES|SMP_OPT_FINAL);
			ret = acl_pass(ret);
			if (((struct acl_cond *)wl->cond)->pol == ACL_COND_UNLESS)
				ret = !ret;
			if (!ret)
				continue;
		}
		if (unlikely(http_header_add_tail(&txn->rsp, &txn->hdr_idx, wl->s) < 0))
			goto return_bad_resp;
	}
```

对于同一个种类的 rules，执行逻辑如下：

```
    主要遍历 rule，调用 acl_exec_cond 执行该 rule 的检测条件。该检测结果只给出匹配与否。
        逐个遍历 cond 上的 ACL 组，即cond->suites。任一 suite 匹配成功，则认为匹配成功
        同一个 ACL 组上，遍历所有 suite->terms （ACL + 取反逻辑）。任意一个 ACL 匹配失败，则跳到下一个 ACL 组继续匹配。同一组全部 ACL 匹配成功，则认为该 ACL 组匹配
            同一个 ACL 上的匹配，则是逐一遍历 ACL 的 expr。只要任意一个 expr 匹配成功，则认为该 ACL 匹配成功
    结合 condition 中的条件 if/unless，确定最终匹配结果
    如果匹配则执行对应的 action，否则检测下一条规则。
```

#### 4. rule 的种类

从 proxy 结构体可以看出 rule 的种类

```
	struct proxy {
		...
		struct list acl;                        /* ACL declared on this proxy */
		struct list http_req_rules;		/* HTTP request rules: allow/deny/http-auth */
		struct list block_cond;                 /* early blocking conditions (chained) */
		struct list redirect_rules;             /* content redirecting rules (chained) */
		struct list switching_rules;            /* content switching rules (chained) */
		struct list persist_rules;		/* 'force-persist' and 'ignore-persist' rules (chained) */
		struct list sticking_rules;             /* content sticking rules (chained) */
		struct list storersp_rules;             /* content store response rules (chained) */
		struct list server_rules;               /* server switching rules (chained) */
		struct {                                /* TCP request processing */
			unsigned int inspect_delay;     /* inspection delay */
			struct list inspect_rules;      /* inspection rules */
			struct list l4_rules;           /* layer4 rules */
		} tcp_req;
		struct {                                /* TCP request processing */
			unsigned int inspect_delay;     /* inspection delay */
			struct list inspect_rules;      /* inspection rules */
		} tcp_rep;
		...
	}
```

其中， 函数 http_process_req_common 中处理的规则如下：

```
	http_process_req_common
	{
		... 
		1. process block rules
		...
		2. process http req rules
		...
		3. execute regular exp if any
		...
		4. req add
		...
		5. process redirect rules
		...
	}
```

这里没有详细的介绍各种具体用途的 rules。随后具体分析代码的时候总结一下再加上。 

