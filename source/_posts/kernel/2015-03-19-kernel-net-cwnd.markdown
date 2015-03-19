---
layout: post
title: "拥塞窗口cwnd的理解"
date: 2015-03-19 18:15:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---
http://blog.csdn.net/linweixuan/article/details/4353015

开始的时候拥塞窗口是1，发一个数据包等ACK回来 cwnd++即2,这个时候可以发送两个包,发送间隔几乎没有, 对方回的ACK到达发送方几乎是同时到达的.一个RTT来回,cwnd就翻倍,cwnd++,cwnd++即4了.如此下去,cwnd是指数增加. 

![](/images/kernel/2015-03-19-2.jpg)  

snd_cwnd_clamp这个变量我们可以不管,假定是一个大值.窗口到了我们设置的门限,snd_cwnd不在增加 而通过snd_cwnd_cnt变量来计数增加,一直增加到大过cwnd值,cwnd才加1,然后snd_cwnd_cnt重新计数, 通过snd_cwnd_cnt延缓cwnd计数,由于TCP是固定大小报文,每一个snd_cwnd代表了一个报文段的增加,snd_cwnd_cnt则看成byte的增加
```
	void tcp_cong_avoid(struct send_queue* sq)
	{
		/* In saft area, increase*/
		if (sq->snd_cwnd <= sq->snd_ssthresh){
		    if (sq->snd_cwnd < sq->snd_cwnd_clamp)
		        sq->snd_cwnd++;
		}
		else{ 
		    /* In theory this is tp->snd_cwnd += 1 / tp->snd_cwnd */
		    if (sq->snd_cwnd_cnt >= sq->snd_cwnd) {
		        if (sq->snd_cwnd < sq->snd_cwnd_clamp)
		            sq->snd_cwnd++;
		        sq->snd_cwnd_cnt = 0;
		    } else
		        sq->snd_cwnd_cnt++;
		} 
	}
```

snd_cwnd 还没到达门限不断增加snd_cwnd++  
snd_cwnd++                      | <--snd_ssthresh
                                ^

到达了snd_ssthresh转入拥塞避免，这个阶段由变量snd_cwnd_cnt来控制
 
转入拥塞,由于snd_cwnd_cnt从0开始小于snd_ssthresh，即从snd_ssthresh那个点开始计数, 一旦计数达到snd_cwnd拥塞窗口的值，但是还小过牵制snd_cwnd_clamp值

```
                              snd_cwnd_clamp
                                     ^
        snd_cwnd++                   |            | <--snd_ssthresh
                                                  ^
                                        snd_cwnd++        
                                                              snd_cwnd_clamp
                                                                     ^
                                    snd_cwnd_cnt++                   |            | <--snd_ssthresh
                                                                                  ^
                                                   0      --->       snd_cwnd_cnt++
 
 
                   <------                       时间                      ------->
```

