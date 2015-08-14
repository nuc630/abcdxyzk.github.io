---
layout: post
title: "TCP校验和的原理和实现"
date: 2015-04-15 14:07:00 +0800
comments: false
categories:
- 2015
- 2015~04
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/zhangskd/article/details/11770647

#### 概述
TCP校验和是一个端到端的校验和，由发送端计算，然后由接收端验证。其目的是为了发现TCP首部和数据在发送端到接收端之间发生的任何改动。如果接收方检测到校验和有差错，则TCP段会被直接丢弃。

TCP校验和覆盖TCP首部和TCP数据，而IP首部中的校验和只覆盖IP的首部，不覆盖IP数据报中的任何数据。

TCP的校验和是必需的，而UDP的校验和是可选的。

TCP和UDP计算校验和时，都要加上一个12字节的伪首部。


#### 伪首部

![](/images/kernel/2015-04-15-1.jpeg)  

伪首部共有12字节，包含如下信息：源IP地址、目的IP地址、保留字节(置0)、传输层协议号(TCP是6)、TCP报文长度(报头+数据)。

伪首部是为了增加TCP校验和的检错能力：如检查TCP报文是否收错了(目的IP地址)、传输层协议是否选对了(传输层协议号)等。

#### 定义
##### (1) RFC 793的TCP校验和定义

The checksum field is the 16 bit one's complement of the one's complement sum of all 16-bit words in the header and text. If a segment contains an odd number of header and text octets to be checksummed, the last octet is padded on the right with zeros to form a 16-bit word for checksum purposes. The pad is not transmitted as part of the segment. While computing the checksum, the checksum field itself is replaced with zeros.

上述的定义说得很明确：  
首先，把伪首部、TCP报头、TCP数据分为16位的字，如果总长度为奇数个字节，则在最后增添一个位都为0的字节。把TCP报头中的校验和字段置为0（否则就陷入鸡生蛋还是蛋生鸡的问题）。

其次，用反码相加法累加所有的16位字（进位也要累加）。

最后，对计算结果取反，作为TCP的校验和。

##### (2) RFC 1071的IP校验和定义

1.Adjacent octets to be checksummed are paired to form 16-bit integers, and the 1's complement sum of these 16-bit integers is formed.

2.To generate a checksum, the checksum field itself is cleared, the 16-bit 1's complement sum is computed over the octets concerned, and the 1's complement of this sum is placed in the checksum field.

3.To check a checksum, the 1's complement sum is computed over the same set of octets, including the checksum field. If the result is all 1 bits (-0 in 1's complement arithmetic), the check succeeds.

可以看到，TCP校验和、IP校验和的计算方法是基本一致的，除了计算的范围不同。
 
#### 实现

基于2.6.18、x86_64。

csum_tcpudp_nofold()按4字节累加伪首部到sum中。
```
	static inline unsigned long csum_tcpudp_nofold (unsigned long saddr, unsigned long daddr,  
							unsigned short len, unsigned short proto,  
							unsigned int sum)  
	{  
		asm("addl %1, %0\n"    /* 累加daddr */  
			"adcl %2, %0\n"    /* 累加saddr */  
			"adcl %3, %0\n"    /* 累加len(2字节), proto, 0*/  
			"adcl $0, %0\n"    /*加上进位 */  
			: "=r" (sum)  
			: "g" (daddr), "g" (saddr), "g" ((ntohs(len) << 16) + proto*256), "0" (sum));  
		return sum;  
	}   
```

csum_tcpudp_magic()产生最终的校验和。

首先，按4字节累加伪首部到sum中。

其次，累加sum的低16位、sum的高16位，并且对累加的结果取反。

最后，截取sum的高16位，作为校验和。
```
	static inline unsigned short int csum_tcpudp_magic(unsigned long saddr, unsigned long daddr,  
								unsigned short len, unsigned short proto,  
								unsigned int sum)  
	{  
		return csum_fold(csum_tcpudp_nofold(saddr, daddr, len, proto, sum));  
	}  
	  
	static inline unsigned int csum_fold(unsigned int sum)  
	{  
		__asm__(  
			"addl %1, %0\n"  
			"adcl 0xffff, %0"  
			: "=r" (sum)  
			: "r" (sum << 16), "0" (sum & 0xffff0000)   
	  
			/* 将sum的低16位，作为寄存器1的高16位，寄存器1的低16位补0。 
			  * 将sum的高16位，作为寄存器0的高16位，寄存器0的低16位补0。 
			  * 这样，addl %1, %0就累加了sum的高16位和低16位。 
			  * 
			 * 还要考虑进位。如果有进位，adcl 0xfff, %0为：0x1 + 0xffff + %0，寄存器0的高16位加1。 
			  * 如果没有进位，adcl 0xffff, %0为：0xffff + %0，对寄存器0的高16位无影响。 
			  */  
	  
		);  
	  
		return (~sum) >> 16; /* 对sum取反，返回它的高16位，作为最终的校验和 */  
	}  
```
 
#### 发送校验

```
	#define CHECKSUM_NONE 0 /* 不使用校验和，UDP可选 */  
	#define CHECKSUM_HW 1 /* 由硬件计算报头和首部的校验和 */  
	#define CHECKSUM_UNNECESSARY 2 /* 表示不需要校验，或者已经成功校验了 */  
	#define CHECKSUM_PARTIAL CHECKSUM_HW  
	#define CHECKSUM_COMPLETE CHECKSUM_HW  
```

##### @tcp_transmit_skb()
	icsk->icsk_af_ops->send_check(sk, skb->len, skb); /* 计算校验和 */
 
```
	void tcp_v4_send_check(struct sock *sk, int len, struct sk_buff *skb)  
	{  
		struct inet_sock *inet = inet_sk(sk);  
		struct tcphdr *th = skb->h.th;  
	   
		if (skb->ip_summed == CHECKSUM_HW) {  
			/* 只计算伪首部，TCP报头和TCP数据的累加由硬件完成 */  
			th->check = ~tcp_v4_check(th, len, inet->saddr, inet->daddr, 0);  
			skb->csum = offsetof(struct tcphdr, check); /* 校验和值在TCP首部的偏移 */  
	  
		} else {  
			/* tcp_v4_check累加伪首部，获取最终的校验和。 
			 * csum_partial累加TCP报头。 
			 * 那么skb->csum应该是TCP数据部分的累加，这是在从用户空间复制时顺便累加的。 
			 */  
			th->check = tcp_v4_check(th, len, inet->saddr, inet->daddr,  
						csum_partial((char *)th, th->doff << 2, skb->csum));  
		}  
	}  

```
```
	unsigned csum_partial(const unsigned char *buff, unsigned len, unsigned sum)  
	{  
		return add32_with_carry(do_csum(buff, len), sum);  
	}  
	  
	static inline unsigned add32_with_carry(unsigned a, unsigned b)  
	{  
		asm("addl %2, %0\n\t"  
			 "adcl $0, %0"  
			 : "=r" (a)  
			 : "0" (a), "r" (b));  
		return a;  
	}   
```

do_csum()用于计算一段内存的校验和，这里用于累加TCP报头。

具体计算时用到一些技巧：  
1.反码累加时，按16位、32位、64位来累加的效果是一样的。  
2.使用内存对齐，减少内存操作的次数。

```
	static __force_inline unsigned do_csum(const unsigned char *buff, unsigned len)  
	{  
		unsigned odd, count;  
		unsigned long result = 0;  
	  
		if (unlikely(len == 0))  
			return result;  
	  
		/* 使起始地址为XXX0，接下来可按2字节对齐 */  
		odd = 1 & (unsigned long) buff;  
		if (unlikely(odd)) {  
			result = *buff << 8; /* 因为机器是小端的 */  
			len--;  
			buff++;  
		}  
		count = len >> 1; /* nr of 16-bit words，这里可能余下1字节未算，最后会处理*/  
	  
		if (count) {  
			/* 使起始地址为XX00，接下来可按4字节对齐 */  
			if (2 & (unsigned long) buff) {  
				result += *(unsigned short *)buff;  
				count--;  
				len -= 2;  
				buff += 2;  
			}  
			count >>= 1; /* nr of 32-bit words，这里可能余下2字节未算，最后会处理 */  
	  
			if (count) {  
				unsigned long zero;  
				unsigned count64;  
				/* 使起始地址为X000，接下来可按8字节对齐 */  
				if (4 & (unsigned long)buff) {  
					result += *(unsigned int *)buff;  
					count--;  
					len -= 4;  
					buff += 4;  
				}  
				count >>= 1; /* nr of 64-bit words，这里可能余下4字节未算，最后会处理*/  
	  
				/* main loop using 64byte blocks */  
				zero = 0;  
				count64 = count >> 3; /* 64字节的块数，这里可能余下56字节未算，最后会处理 */  
				while (count64) { /* 反码累加所有的64字节块 */  
					asm ("addq 0*8(%[src]), %[res]\n\t"    /* b、w、l、q分别对应8、16、32、64位操作 */  
						"addq 1*8(%[src]), %[res]\n\t"    /* [src]为指定寄存器的别名，效果应该等同于0、1等 */  
						"adcq 2*8(%[src]), %[res]\n\t"  
						"adcq 3*8(%[src]), %[res]\n\t"  
						"adcq 4*8(%[src]), %[res]\n\t"  
						"adcq 5*8(%[src]), %[res]\n\t"  
						"adcq 6*8(%[src]), %[res]\n\t"  
						"adcq 7*8(%[src]), %[res]\n\t"  
						"adcq %[zero], %[res]"  
						: [res] "=r" (result)  
						: [src] "r" (buff), [zero] "r" (zero), "[res]" (result));  
					buff += 64;  
					count64--;  
				}  
	  
				/* 从这里开始，反序处理之前可能漏算的字节 */  
	  
				/* last upto 7 8byte blocks，前面按8个8字节做计算单位，所以最多可能剩下7个8字节 */  
				count %= 8;  
				while (count) {  
					asm ("addq %1, %0\n\t"  
						 "adcq %2, %0\n"  
						 : "=r" (result)  
						 : "m" (*(unsigned long *)buff), "r" (zero), "0" (result));  
					--count;  
					buff += 8;  
				}  
	  
				/* 带进位累加result的高32位和低32位 */  
				result = add32_with_carry(result>>32, result&0xffffffff);  
	  
				/* 之前始按8字节对齐，可能有4字节剩下 */  
				if (len & 4) {  
					result += *(unsigned int *) buff;  
					buff += 4;  
				}  
			}  
	  
		   /* 更早前按4字节对齐，可能有2字节剩下 */  
			if (len & 2) {  
				result += *(unsigned short *) buff;  
				buff += 2;  
			}  
		}  
	  
		/* 最早之前按2字节对齐，可能有1字节剩下 */  
		if (len & 1)  
			result += *buff;  
	  
		/* 再次带进位累加result的高32位和低32位 */  
		result = add32_with_carry(result>>32, result & 0xffffffff);   
	  
		/* 这里涉及到一个技巧，用于处理初始地址为奇数的情况 */  
		if (unlikely(odd)) {  
			result = from32to16(result); /* 累加到result的低16位 */  
			/* result为：0 0 a b 
			 * 然后交换a和b，result变为：0 0 b a 
			 */  
			result = ((result >> 8) & 0xff) | ((result & oxff) << 8);  
		}  
	  
		return result; /* 返回result的低32位 */  
	}  
```

```
	static inline unsigned short from32to16(unsigned a)  
	{  
		unsigned short b = a >> 16;  
		asm ("addw %w2, %w0\n\t"  
				  "adcw $0, %w0\n"  
				  : "=r" (b)  
				  : "0" (b), "r" (a));  
		return b;  
	}  
```

csum_partial_copy_from_user()用于拷贝用户空间数据到内核空间，同时计算用户数据的校验和，结果保存到skb->csum中（X86_64）。

```
	/** 
	 * csum_partial_copy_from_user - Copy and checksum from user space. 
	 * @src: source address (user space) 
	 * @dst: destination address 
	 * @len: number of bytes to be copied. 
	 * @isum: initial sum that is added into the result (32bit unfolded) 
	 * @errp: set to -EFAULT for an bad source address. 
	 * 
	 * Returns an 32bit unfolded checksum of the buffer. 
	 * src and dst are best aligned to 64bits. 
	 */  
	  
	unsigned int csum_partial_copy_from_user(const unsigned char __user *src,  
							unsigned char *dst, int len, unsigned int isum, int *errp)  
	{  
		might_sleep();  
		*errp = 0;  
	  
		if (likely(access_ok(VERIFY_READ, src, len))) {  
	  
			/* Why 6, not 7? To handle odd addresses aligned we would need to do considerable 
			 * complications to fix the checksum which is defined as an 16bit accumulator. The fix 
			 * alignment code is primarily for performance compatibility with 32bit and that will handle 
			 * odd addresses slowly too. 
			 * 处理X010、X100、X110的起始地址。不处理X001，因为这会使复杂度大增加。 
			 */  
			if (unlikely((unsigned long)src & 6)) {  
				while (((unsigned long)src & 6) && len >= 2) {  
					__u16 val16;  
					*errp = __get_user(val16, (__u16 __user *)src);  
					if (*errp)  
						return isum;  
					*(__u16 *)dst = val16;  
					isum = add32_with_carry(isum, val16);  
					src += 2;  
					dst += 2;  
					len -= 2;  
				}  
			}  
	  
			/* 计算函数是用纯汇编实现的，应该是因为效率吧 */  
			isum = csum_parial_copy_generic((__force void *)src, dst, len, isum, errp, NULL);  
	  
			if (likely(*errp == 0))  
				return isum; /* 成功 */  
		}  
	  
		*errp = -EFAULT;  
		memset(dst, 0, len);  
		return isum;  
	}  
```

上述的实现比较复杂，来看下最简单的csum_partial_copy_from_user()实现（um）。
```
	unsigned int csum_partial_copy_from_user(const unsigned char *src,  
							unsigned char *dst, int len, int sum,  
							int *err_ptr)  
	{  
		if (copy_from_user(dst, src, len)) { /* 拷贝用户空间数据到内核空间 */  
			*err_ptr = -EFAULT; /* bad address */  
			return (-1);  
		}  
	  
		return csum_partial(dst, len, sum); /* 计算用户数据的校验和，会存到skb->csum中 */  
	}  
```
 
#### 接收校验

##### @tcp_v4_rcv
	/* 检查校验和 */
	if (skb->ip_summed != CHECKSUM_UNNECESSARY && tcp_v4_checksum_init(skb))  
		goto bad_packet;   


接收校验的第一部分，主要是计算伪首部。
```
	static int tcp_v4_checksum_init(struct sk_buff *skb)  
	{  
		/* 如果TCP报头、TCP数据的反码累加已经由硬件完成 */  
		if (skb->ip_summed == CHECKSUM_HW) {  
	  
			/* 现在只需要再累加上伪首部，取反获取最终的校验和。 
			 * 校验和为0时，表示TCP数据报正确。 
			 */  
			if (! tcp_v4_check(skb->h.th, skb->len, skb->nh.iph->saddr, skb->nh.iph->daddr, skb->csum)) {  
				skb->ip_summed = CHECKSUM_UNNECESSARY;  
				return 0; /* 校验成功 */  
	  
			} /* 没有else失败退出吗？*/  
		}  
	  
		/* 对伪首部进行反码累加，主要用于软件方法 */  
		skb->csum = csum_tcpudp_nofold(skb->nh.iph->saddr, skb->nh.iph->daddr, skb->len, IPPROTO_TCP, 0);  
	   
	  
		/* 对于长度小于76字节的小包，接着累加TCP报头和报文，完成校验；否则，以后再完成检验。*/  
		if (skb->len <= 76) {  
			return __skb_checksum_complete(skb);  
		}  
	}  
```

接收校验的第二部分，计算报头和报文。
```
tcp_v4_rcv、tcp_v4_do_rcv()

	| --> tcp_checksum_complete()

		| --> __tcp_checksum_complete()

			| --> __skb_checksum_complete()


tcp_rcv_established()

	| --> tcp_checksum_complete_user()

		| --> __tcp_checksum_complete_user()

			| --> __tcp_checksum_complete()

				| --> __skb_checksum_complete()
```

```
	unsigned int __skb_checksum_complete(struct sk_buff *skb)  
	{  
		unsigned int sum;  
	  
		sum = (u16) csum_fold(skb_checksum(skb, 0, skb->len, skb->csum));  
	  
		if (likely(!sum)) { /* sum为0表示成功了 */  
			/* 硬件检测失败，软件检测成功了，说明硬件检测有误 */  
			if (unlikely(skb->ip_summed == CHECKSUM_HW))  
				netdev_rx_csum_fault(skb->dev);  
			skb->ip_summed = CHECKSUM_UNNECESSARY;  
		}  
		return sum;  
	}  
```

计算skb包的校验和时，可以指定相对于skb->data的偏移量offset。由于skb包可能由分页和分段，所以需要考虑skb->data + offset是位于此skb段的线性区中、还是此skb的分页中，或者位于其它分段中。这个函数逻辑比较复杂。

```
	/* Checksum skb data. */  
	unsigned int skb_checksum(const struct sk_buff *skb, int offset, int len, unsigned int csum)  
	{  
		int start = skb_headlen(skb); /* 线性区域长度 */  
		/* copy > 0，说明offset在线性区域中。 
		 * copy < 0，说明offset在此skb的分页数据中，或者在其它分段skb中。 
		 */  
		int i, copy = start - offset;  
		int pos = 0; /* 表示校验了多少数据 */  
	  
		/* Checksum header. */  
		if (copy > 0) { /* 说明offset在本skb的线性区域中 */  
			if (copy > len)  
				copy = len; /* 不能超过指定的校验长度 */  
	  
			/* 累加copy长度的线性区校验 */  
			csum = csum_partial(skb->data + offset, copy, csum);  
	  
			if ((len -= copy) == 0)  
				return csum;  
	  
			offset += copy; /* 接下来从这里继续处理 */  
			pos = copy; /* 已处理数据长 */  
		}  
	  
		/* 累加本skb分页数据的校验和 */  
		for (i = 0; i < skb_shinfo(skb)->nr_frags; i++) {  
			int end;  
			BUG_TRAP(start <= offset + len);  
		  
			end = start + skb_shinfo(skb)->frags[i].size;  
	  
			if ((copy = end - offset) > 0) { /* 如果offset位于本页中，或者线性区中 */  
				unsigned int csum2;  
				u8 *vaddr; /* 8位够吗？*/  
				skb_frag_t *frag = &skb_shinfo(skb)->frags[i];  
	   
				if (copy > len)  
					copy = len;  
	  
				vaddr = kmap_skb_frag(frag); /* 把物理页映射到内核空间 */  
				csum2 = csum_partial(vaddr + frag->page_offset + offset - start, copy, 0);  
				kunmap_skb_frag(vaddr); /* 解除映射 */  
	  
				/* 如果pos为奇数，需要对csum2进行处理。 
				 * csum2：a, b, c, d => b, a, d, c 
				 */  
				csum = csum_block_add(csum, csum2, pos);  
	  
				if (! (len -= copy))  
					return csum;  
	  
				offset += copy;  
				pos += copy;  
			}  
			start = end; /* 接下来从这里处理 */  
		}  
	   
		/* 如果此skb是个大包，还有其它分段 */  
		if (skb_shinfo(skb)->frag_list) {  
			struct sk_buff *list = skb_shinfo(skb)->frag_list;  
	  
			for (; list; list = list->next) {  
				int end;  
				BUG_TRAP(start <= offset + len);  
	   
				end = start + list->len;  
	  
				if ((copy = end - offset) > 0) { /* 如果offset位于此skb分段中，或者分页，或者线性区 */  
					unsigned int csum2;  
					if (copy > len)  
						copy = len;  
	  
					csum2 = skb_checksum(list, offset - start, copy, 0); /* 递归调用 */  
					csum = csum_block_add(csum, csum2, pos);  
					if ((len -= copy) == 0)  
						return csum;  
	  
					offset += copy;  
					pos += copy;  
				}  
				start = end;  
			}  
		}  
	  
		BUG_ON(len);  
		return csum;  
	}
```

#### 重算skb的checksum
```
	#include <linux/version.h>
	#include <linux/net.h>
	#include <linux/ip.h>
	#include <linux/tcp.h>
	#include <net/tcp.h>

	void skbcsum(struct sk_buff *skb)
	{
		struct tcphdr *tcph;
		struct iphdr *iph;
		int iphl;
		int tcphl;
		int tcplen;

		iph = (struct iphdr *)skb->data;
		iphl = iph->ihl << 2;
		tcph = (struct tcphdr *)(skb->data + iphl);
		tcphl = tcph->doff << 2;

		iph->check	= 0;
		iph->check	= ip_fast_csum((unsigned char *)iph, iph->ihl);

		tcph->check	= 0;
		tcplen		= skb->len - (iph->ihl << 2);
		if (skb->ip_summed == CHECKSUM_PARTIAL) {
			tcph->check = ~csum_tcpudp_magic(iph->saddr, iph->daddr,
					tcplen, IPPROTO_TCP, 0);
	#if LINUX_VERSION_CODE < KERNEL_VERSION(2, 6, 32)
			skb->csum = offsetof(struct tcphdr, check);
	#else
			skb->csum_start	= skb_transport_header(skb) - skb->head;
			skb->csum_offset = offsetof(struct tcphdr, check);
	#endif
		}
		else {
			skb->csum = 0;
			skb->csum = skb_checksum(skb, iph->ihl << 2, tcplen, 0);
			tcph->check = csum_tcpudp_magic(iph->saddr, iph->daddr,
					tcplen, IPPROTO_TCP, skb->csum);

		}
	}
```

