---
layout: post
title: "linux 实时时钟（RTC）驱动"
date: 2016-01-12 15:53:00 +0800
comments: false
categories:
- 2016
- 2016~01
- kernel
- kernel~base
tags:
---

[Documentation/rtc.txt](/download/kernel/rtc.txt)

------------

http://blog.csdn.net/yaozhenguo2006/article/details/6820218

这个是linux内核文档关于rtc实时时钟部分的说明，此文档主要描述了rtc实时时钟的作用和编程接口，分别介绍了老的rtc接口和新的rtc类架构。并给出了一个测试rtc驱动的程序。

### linux 实时时钟（RTC）驱动
翻译：窗外云天yaozhenguo2006@126.com  最后矫正时间：2011.9.25

当linux开发者提到“实时时钟”的时候，他们通常所指的就是墙钟时间，这个时间是电池供电的，所以在系统掉电的情况下还能正常工作。除非在MS-Windows启动的时候设置，否则这个时钟不会同步于本地时区和夏令时间。事实上，他被设置成格林威治时间。

最新的非pc体系的硬件趋向于记秒数，比如time(2)系统调用的输出，但是实时时钟用公历和24小时表示日期与时间，比如gmtime(3)的输出。

linux提供两类的rtc兼容性很高的用户空间系统调用接口，如下所示：  
（1） /dev/rtc ... 这个RTC适合pc体系的系统，而并不适合非x86体系的系统  
（2） /dev/rtc0,/dev/rtc1 ... 他们依赖一种架构，这种架构在所有的系统上被RTC芯片广泛的支持。  

程序员必须知道，PC/AT的功能不总是有效，其他的系统可能会有另外的实现。这种情况下，如果在相同的系统结构上使用同样的RTC API，那么硬件会有不同的反应。例如，不是每一个RTC都提供IRQ，所以这些不能处理报警中断；标准的PC系统RTC只能处理未来24小时以内的闹钟，而其他系统的RTC可能处理未来一个世纪的任何时间。

#### 老的PC/AT驱动：/dev/rtc

所有基于PC的系统（甚至Alpha体系的机器）都有一个集成的实时时钟。通常他们集成在计算机的芯片组内，但是也有一些系统是在主板上焊接着摩托罗拉MC146818（或者类似的芯片），他们给系统提供时间和日期，这个时间和日期在系统掉电后仍然会保存。

ACPT(高级配置与电源管理接口)对MC146818的功能进行了标准化，并且在一些方面进行了功能扩展（提供了更长的定时周期，睡眠唤醒功能）。然而这些扩展的功能不适合老的驱动程序。

这个RTC还可以产生频率从 2HZ 到 8192HZ 的信号，以2的乘方增长。这些信号通过中断信号线8报告给系统。这个RTC还可以用作定时限制为24小时的闹钟，当定时时间到时产生8号中断。这个闹钟可以设置成任意一个可编程值的子集，这意味着可以设置成任意小时的任意分钟任意秒，例如，可以将这个时钟设置成在每个clk产生中断，从而产生1hz的信号。

这些中断通过/dev/rtc报告给系统（主设备号10,次设备号135，只读字符设备），中断传回一个无符号整数类型的数据。最低的位包含中断的类型（更新，闹钟，或者期），其他的字节代表了最后一次读到现在中断发生的次数。状态信息由虚拟文件/proc/driver/rtc产生，前提条件是使能了/proc文件系统。驱动应该提供锁机制，保证在同一时刻只有一个进程访问/dev/rtc。

用户进程通过系统调用read(2)或者select(2)读取/dev/rtc来获取这些中断。当调用这两个系统调用的时候，进程会阻塞或者退出直到下一个中断到来。这个功能用在需要不频繁的获取数据而又不希望通过轮询当前时间而占用CPU时间的情况下。

在高频率中断或者高系统负载下，用户进程应该检查从上次读取到现在发生中断的次数以判断是否有未处理的中断。例如，一个典型的 486-33 对/dev/rtc以大于1024hz的频率进行循环读，偶尔会产生中断积累（从上次读取到现在发生大于一次的中断）。鉴于此你应该检查读取数据的高字节，特别是在频率高于普通定时器中断--100hz的情况下。

中断频率是可编程的或可以让他超过64hz，但是只有root权限的用户可以这样做。这样做可能有点保守，但是我们不希望有恶意的用户在一个较慢的386sx-16机器上产生很多中断，这样会严重影响系统的性能。我们可以通过向/proc/sys/dev/rtc/max-user-freq写入值来修改这个64hz的限制。但是注意你一定要这样做，减少中断处理程序的代码才会亡羊补牢，使对系统性能的影响降到最小。

如果内核时间是和外部时钟源同步的，那么内核将每隔11分钟就会将时间写回CMOS时钟。在这个过程中，内核会关闭rtc周期中断，如果你的程序在做一些关键的工作一定要注意到。如果你的内核不和外部时钟源同步，那么内核会一直处理rtc中断，处理方式根据你具体的应用。

闹钟和中断频率可以通过系统调用ioctl(2)来设置，ioctl的命令定义在./include/linux/rtc.h。与其长篇大论的介绍怎么样使用这个系统调用，还不如写一个实例程序来的方便，这个程序用来演示驱动的功能，对很多人来说用驱动程序提供的功能来进行应用编程他们会更感兴趣。在这个文档的最后有这段程序。

#### 新接口 “RTC类” 驱动：/dev/rtcn

因为linux支持许多非ACPI非PC平台，其中一些平台有不只一个RTC，所以需要更多可移植性的设计，而不是仅仅在每个系统都实现类似MC146818的接口。在这种情况下，新的“RTC类”构架产生了。他提供不同的用户空间接口：
（1） /dev/rtcn 和老的接口一样
（2）/dev/class/rtc/rtcn   sysfs 属性，一些属性是只读的
（3） /dev/driver/rtc 第一个rtc会使用procfs接口。更多的信息会显示在这里而不是sysfs。

RTC类构架支持很多类型的RTC，从集成在嵌入式SOC处理器内的RTC到通过I2C，SPI和其他总线连接到CPU的芯片。这个架构甚至还支持PC系统的RTC，包括使用ACPI，PC的一些新特性。

新架构也打破了“每个系统只有一个RTC”的限制。例如，一个低功耗电池供电的RTC是一个分离的I2C接口的芯片，但是系统可能还集成了一个多功能的RTC。系统可能从分离的RTC读取系统时钟，但是对于其他任务用集成的RTC，因为这个RTC提供更多的功能。

#### SYSFS 接口

在/sys/class/rtc/rtcn下面的sysfs接口提供了操作rtc属性的方法，而不用通过Ioclt系统调用。所有的日期时间都是墙钟时间，而不是系统时间。
```
	date:           RTC提供的日期
	hctosys:        如果在内核配置选项中配置了CONFIG_RTC_HCTOSYS，RTC会在系统启动的时候提供系统时间，这种情况下这个位就是1,否则为0
	max_user_freq:  非特权用户可以从RTC得到的最大中断频率
	name:           RTC的名字，与sysfs目录相关
	since_epoch:    从纪元开始所经历的秒数
	time:           RTC提供的时间
	wakealarm:      唤醒时间的时间事件。 这是一种单次的唤醒事件，所以如果还需要唤醒，在唤醒发生后必须复位。这个域的数据结构或者是从纪元开始经历的妙数，或者是相对的秒数
```
#### IOCTL 接口

/dev/rtc支持的Ioctl系统调用，RTC类构架也支持。然而，因为芯片和系统没有一个统一的标准，一些PC/AT功能可能没有提供。以相同方式工作的一些新特性，--包括ACPI提供的，--在RTC类构架中表现出的，在老的驱动上不会工作。

（1） RTC_RD_TIME,RTC_SET_TIME .. 每一个RTC都至少支持读时间这个命令，时间格式为公历和24小时制墙钟时间。最有用的特性是，这个时间可以更新。  
（2） RTC_ATE_ON,RTC_ATE_OFF,RTC_ALM_SET,RTC_ALM_READ ... 当RTC连接了一条IRQ线，他还能处理在未来24小时的报警中断。  
（3） RTC_WKALM_SET，RTC_WKALM_RD 。。。 RTCs 使用一个功能更强大的api,他可以处理超过24小时的报警时间。这个API支持设置更长的报警时间，支持单次请求的IRQ中断。  
（4） RTC_UIE_ON,RTC_UIE_OFF ... 如果RTC提供IRQ，他可能也提供每秒更新的IRQ中断。如果需要，RTC结构可以模仿这个机制。  

（5） RTC_PIE_ON,RTC_PIE_OFF,RTC_IRQP_SET,RTC_IRQP_READ ... 如果一个IRQ是周期中断，那么这个IRQ还有可设置频率的特性（频率通常是2的n次方）

很多情况下，RTC报警时钟通常是一个系统唤醒事件，用于将Linux从低功耗睡眠模式唤醒到正常的工作模式。例如，系统会处于低功耗的模式下，直到时间到了去执行一些任务。注意这些ioctl的一些功能不必在你的驱动程序中实现。如果一个ioctl调用，你的驱动返回ENOIOCTLCMD，那么这个Ioctl就由通用RTC设备接口处理。下面是一些通用的例子：  
（6） RTC_RD_TIME, RTC_SET_TIME: read_time/set_time 函数会被调用。  
（7） RTC_ALM_SET, RTC_ALM_READ, RTC_WKALM_SET, RTC_WKALM_RD: set_alarm/read_alarm 函数将会被调用.  
（8） RTC_IRQP_SET, RTC_IRQP_READ: irq_set_freq 函数将会调用，用来设置频率，RTC类构架会处理读请求，而频率保存在RTC设备结构中的irq_freq域。你的驱动需要在模块初始化的时候初始化irq_freq，你必须在irq_set_freq函数里检查设置的频率是否在硬件允许的范围。如果不是那么驱动应该返回-EINVAL。如果你不需要改变这个频率，那么不要定义irq_set_freq这个函数。  
（7） RTC_PIE_ON, RTC_PIE_OFF: irq_set_state 函数会被调用。  

  如果所有的ioctl都失败了，用下面的rtc-test.c检查一下你的驱动吧！

```
	/*
	 *      Real Time Clock Driver Test/Example Program
	 *
	 *      Compile with:
	 *		     gcc -s -Wall -Wstrict-prototypes rtctest.c -o rtctest
	 *
	 *      Copyright (C) 1996, Paul Gortmaker.
	 *
	 *      Released under the GNU General Public License, version 2,
	 *      included herein by reference.
	 *
	 */

	#include <stdio.h>
	#include <linux/rtc.h>
	#include <sys/ioctl.h>
	#include <sys/time.h>
	#include <sys/types.h>
	#include <fcntl.h>
	#include <unistd.h>
	#include <stdlib.h>
	#include <errno.h>


	/*
	 * This expects the new RTC class driver framework, working with
	 * clocks that will often not be clones of what the PC-AT had.
	 * Use the command line to specify another RTC if you need one.
	 */
	static const char default_rtc[] = "/dev/rtc0";


	int main(int argc, char **argv)
	{
		int i, fd, retval, irqcount = 0;
		unsigned long tmp, data;
		struct rtc_time rtc_tm;
		const char *rtc = default_rtc;

		switch (argc) {
		case 2:
			rtc = argv[1];
			/* FALLTHROUGH */
		case 1:
			break;
		default:
			fprintf(stderr, "usage:  rtctest [rtcdev]\n");
			return 1;
		}

		fd = open(rtc, O_RDONLY);

		if (fd ==  -1) {
			perror(rtc);
			exit(errno);
		}

		fprintf(stderr, "\n\t\t\tRTC Driver Test Example.\n\n");

		/* Turn on update interrupts (one per second) */
		retval = ioctl(fd, RTC_UIE_ON, 0);
		if (retval == -1) {
			if (errno == ENOTTY) {
				fprintf(stderr,
					"\n...Update IRQs not supported.\n");
				goto test_READ;
			}
			perror("RTC_UIE_ON ioctl");
			exit(errno);
		}

		fprintf(stderr, "Counting 5 update (1/sec) interrupts from reading %s:",
				rtc);
		fflush(stderr);
		for (i=1; i<6; i++) {
			/* This read will block */
			retval = read(fd, &data, sizeof(unsigned long));
			if (retval == -1) {
				perror("read");
				exit(errno);
			}
			fprintf(stderr, " %d",i);
			fflush(stderr);
			irqcount++;
		}

		fprintf(stderr, "\nAgain, from using select(2) on /dev/rtc:");
		fflush(stderr);
		for (i=1; i<6; i++) {
			struct timeval tv = {5, 0};     /* 5 second timeout on select */
			fd_set readfds;

			FD_ZERO(&readfds);
			FD_SET(fd, &readfds);
			/* The select will wait until an RTC interrupt happens. */
			retval = select(fd+1, &readfds, NULL, NULL, &tv);
			if (retval == -1) {
				    perror("select");
				    exit(errno);
			}
			/* This read won't block unlike the select-less case above. */
			retval = read(fd, &data, sizeof(unsigned long));
			if (retval == -1) {
				    perror("read");
				    exit(errno);
			}
			fprintf(stderr, " %d",i);
			fflush(stderr);
			irqcount++;
		}

		/* Turn off update interrupts */
		retval = ioctl(fd, RTC_UIE_OFF, 0);
		if (retval == -1) {
			perror("RTC_UIE_OFF ioctl");
			exit(errno);
		}

	test_READ:
		/* Read the RTC time/date */
		retval = ioctl(fd, RTC_RD_TIME, &rtc_tm);
		if (retval == -1) {
			perror("RTC_RD_TIME ioctl");
			exit(errno);
		}

		fprintf(stderr, "\n\nCurrent RTC date/time is %d-%d-%d, %02d:%02d:%02d.\n",
			rtc_tm.tm_mday, rtc_tm.tm_mon + 1, rtc_tm.tm_year + 1900,
			rtc_tm.tm_hour, rtc_tm.tm_min, rtc_tm.tm_sec);

		/* Set the alarm to 5 sec in the future, and check for rollover */
		rtc_tm.tm_sec += 5;
		if (rtc_tm.tm_sec >= 60) {
			rtc_tm.tm_sec %= 60;
			rtc_tm.tm_min++;
		}
		if (rtc_tm.tm_min == 60) {
			rtc_tm.tm_min = 0;
			rtc_tm.tm_hour++;
		}
		if (rtc_tm.tm_hour == 24)
			rtc_tm.tm_hour = 0;

		retval = ioctl(fd, RTC_ALM_SET, &rtc_tm);
		if (retval == -1) {
			if (errno == ENOTTY) {
				fprintf(stderr,
					"\n...Alarm IRQs not supported.\n");
				goto test_PIE;
			}
			perror("RTC_ALM_SET ioctl");
			exit(errno);
		}

		/* Read the current alarm settings */
		retval = ioctl(fd, RTC_ALM_READ, &rtc_tm);
		if (retval == -1) {
			perror("RTC_ALM_READ ioctl");
			exit(errno);
		}

		fprintf(stderr, "Alarm time now set to %02d:%02d:%02d.\n",
			rtc_tm.tm_hour, rtc_tm.tm_min, rtc_tm.tm_sec);

		/* Enable alarm interrupts */
		retval = ioctl(fd, RTC_AIE_ON, 0);
		if (retval == -1) {
			perror("RTC_AIE_ON ioctl");
			exit(errno);
		}

		fprintf(stderr, "Waiting 5 seconds for alarm...");
		fflush(stderr);
		/* This blocks until the alarm ring causes an interrupt */
		retval = read(fd, &data, sizeof(unsigned long));
		if (retval == -1) {
			perror("read");
			exit(errno);
		}
		irqcount++;
		fprintf(stderr, " okay. Alarm rang.\n");

		/* Disable alarm interrupts */
		retval = ioctl(fd, RTC_AIE_OFF, 0);
		if (retval == -1) {
			perror("RTC_AIE_OFF ioctl");
			exit(errno);
		}

	test_PIE:
		/* Read periodic IRQ rate */
		retval = ioctl(fd, RTC_IRQP_READ, &tmp);
		if (retval == -1) {
			/* not all RTCs support periodic IRQs */
			if (errno == ENOTTY) {
				fprintf(stderr, "\nNo periodic IRQ support\n");
				goto done;
			}
			perror("RTC_IRQP_READ ioctl");
			exit(errno);
		}
		fprintf(stderr, "\nPeriodic IRQ rate is %ldHz.\n", tmp);

		fprintf(stderr, "Counting 20 interrupts at:");
		fflush(stderr);

		/* The frequencies 128Hz, 256Hz, ... 8192Hz are only allowed for root. */
		for (tmp=2; tmp<=64; tmp*=2) {

			retval = ioctl(fd, RTC_IRQP_SET, tmp);
			if (retval == -1) {
				/* not all RTCs can change their periodic IRQ rate */
				if (errno == ENOTTY) {
					fprintf(stderr,
						"\n...Periodic IRQ rate is fixed\n");
					goto done;
				}
				perror("RTC_IRQP_SET ioctl");
				exit(errno);
			}

			fprintf(stderr, "\n%ldHz:\t", tmp);
			fflush(stderr);

			/* Enable periodic interrupts */
			retval = ioctl(fd, RTC_PIE_ON, 0);
			if (retval == -1) {
				perror("RTC_PIE_ON ioctl");
				exit(errno);
			}

			for (i=1; i<21; i++) {
				/* This blocks */
				retval = read(fd, &data, sizeof(unsigned long));
				if (retval == -1) {
					perror("read");
					exit(errno);
				}
				fprintf(stderr, " %d",i);
				fflush(stderr);
				irqcount++;
			}

			/* Disable periodic interrupts */
			retval = ioctl(fd, RTC_PIE_OFF, 0);
			if (retval == -1) {
				perror("RTC_PIE_OFF ioctl");
				exit(errno);
			}
		}

	done:
		fprintf(stderr, "\n\n\t\t\t *** Test complete ***\n");

		close(fd);

		return 0;
	}
```

