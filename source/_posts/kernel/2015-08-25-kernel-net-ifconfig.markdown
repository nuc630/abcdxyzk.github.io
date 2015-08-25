---
layout: post
title: "ifconfig statistics"
date: 2015-08-25 14:27:00 +0800
comments: false
categories:
- 2015
- 2015~08
- kernel
- kernel~net
tags:
---

http://jaseywang.me/2014/08/16/ifconfig-%E4%B8%8B%E9%9D%A2%E7%9A%84%E4%B8%80%E4%BA%9B%E5%AD%97%E6%AE%B5errors-dropped-overruns/

http://unix.stackexchange.com/questions/184604/whats-the-difference-between-errors-dropped-overruns-and-frame-fiel

RX errors: 表示总的收包的错误数量，这包括 too-long-frames 错误，Ring Buffer 溢出错误，crc 校验错误，帧同步错误，fifo overruns 以及 missed pkg 等等。

RX dropped: 表示数据包已经进入了 Ring Buffer，但是由于内存不够等系统原因，导致在拷贝到内存的过程中被丢弃。

RX overruns: 表示了 fifo 的 overruns，这是由于 Ring Buffer(aka Driver Queue) 传输的 IO 大于 kernel 能够处理的 IO 导致的，而 Ring Buffer 则是指在发起 IRQ 请求之前的那块 buffer。很明显，overruns 的增大意味着数据包没到 Ring Buffer 就被网卡物理层给丢弃了，而 CPU 无法即使的处理中断是造成 Ring Buffer 满的原因之一，上面那台有问题的机器就是因为 interruprs 分布的不均匀(都压在 core0)，没有做 affinity 而造成的丢包。

RX frame: 表示 misaligned 的 frames，接收到的位长度不是8的倍数，不是字节。it means frames with a length not divisible by 8. Because of that length is not a valid frame and it is simply discarded.
