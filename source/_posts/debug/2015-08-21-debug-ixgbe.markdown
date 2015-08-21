---
layout: post
title: "ixgbe两个合并包功能"
date: 2015-08-21 15:29:00 +0800
comments: false
categories:
- 2015
- 2015~08
- debug
- debug~mark
tags:
---

http://downloadmirror.intel.com/22919/eng/README.txt

http://www.360doc.com/content/12/1101/17/9008018_245137867.shtml

```
	  LRO
	  ---
	  Large Receive Offload (LRO) is a technique for increasing inbound throughput
	  of high-bandwidth network connections by reducing CPU overhead. It works by
	  aggregating multiple incoming packets from a single stream into a larger 
	  buffer before they are passed higher up the networking stack, thus reducing
	  the number of packets that have to be processed. LRO combines multiple 
	  Ethernet frames into a single receive in the stack, thereby potentially 
	  decreasing CPU utilization for receives. 

	  IXGBE_NO_LRO is a compile time flag. The user can enable it at compile
	  time to remove support for LRO from the driver. The flag is used by adding 
	  CFLAGS_EXTRA="-DIXGBE_NO_LRO" to the make file when it's being compiled. 

		 make CFLAGS_EXTRA="-DIXGBE_NO_LRO" install

	  You can verify that the driver is using LRO by looking at these counters in 
	  ethtool:

	  lro_flushed - the total number of receives using LRO.
	  lro_aggregated - counts the total number of Ethernet packets that were combined.

	  NOTE: IPv6 and UDP are not supported by LRO.

	  HW RSC
	  ------
	  82599 and X540-based adapters support HW based receive side coalescing (RSC) 
	  which can merge multiple frames from the same IPv4 TCP/IP flow into a single
	  structure that can span one or more descriptors. It works similarly to SW
	  Large receive offload technique. By default HW RSC is enabled and SW LRO 
	  cannot be used for 82599 or X540-based adapters unless HW RSC is disabled.
	 
	  IXGBE_NO_HW_RSC is a compile time flag. The user can enable it at compile 
	  time to remove support for HW RSC from the driver. The flag is used by adding 
	  CFLAGS_EXTRA="-DIXGBE_NO_HW_RSC" to the make file when it's being compiled.
	  
		 make CFLAGS_EXTRA="-DIXGBE_NO_HW_RSC" install
	 
	  You can verify that the driver is using HW RSC by looking at the counter in 
	  ethtool:
	 
		 hw_rsc_count - counts the total number of Ethernet packets that were being
		 combined.

		...

	max_vfs
	-------
	Valid Range:   1-63
	Default Value: 0

	  If the value is greater than 0 it will also force the VMDq parameter to be 1
	  or more.

	  This parameter adds support for SR-IOV.  It causes the driver to spawn up to 
	  max_vfs worth of virtual function.  

	  NOTE: When either SR-IOV mode or VMDq mode is enabled, hardware VLAN 
	  filtering and VLAN tag stripping/insertion will remain enabled.
	  Please remove the old VLAN filter before the new VLAN filter is added.
	  For example, 
	  
		ip link set eth0 vf 0 vlan 100     // set vlan 100 for VF 0
		ip link set eth0 vf 0 vlan 0       // Delete vlan 100 
		ip link set eth0 vf 0 vlan 200     // set a new vlan 200 for VF 0
	  
	The parameters for the driver are referenced by position.  So, if you have a 
	dual port 82599 or X540-based adapter and you want N virtual functions per 
	port, you must specify a number for each port with each parameter separated by
	a comma.

	For example:
	  modprobe ixgbe max_vfs=63,63

	NOTE: If both 82598 and 82599 or X540-based adapters are installed on the same 
	machine, you must be careful in loading the driver with the parameters. 
	Depending on system configuration, number of slots, etc. it's impossible to 
	predict in all cases where the positions would be on the command line and the 
	user will have to specify zero in those positions occupied by an 82598 port.

	With kernel 3.6, the driver supports the simultaneous usage of max_vfs and DCB 
	features, subject to the constraints described below. Prior to kernel 3.6, the 
	driver did not support the simultaneous operation of max_vfs > 0 and the DCB 
	features (multiple traffic classes utilizing Priority Flow Control and Extended 
	Transmission Selection).

	When DCB is enabled, network traffic is transmitted and received through multiple 
	traffic classes (packet buffers in the NIC). The traffic is associated with a 
	specific class based on priority, which has a value of 0 through 7 used in the 
	VLAN tag. When SR-IOV is not enabled, each traffic class is associated with a set 
	of RX/TX descriptor queue pairs. The number of queue pairs for a given traffic 
	class depends on the hardware configuration. When SR-IOV is enabled, the descriptor 
	queue pairs are grouped into pools. The Physical Function (PF) and each Virtual 
	Function (VF) is allocated a pool of RX/TX descriptor queue pairs. When multiple 
	traffic classes are configured (for example, DCB is enabled), each pool contains a 
	queue pair from each traffic class. When a single traffic class is configured in 
	the hardware, the pools contain multiple queue pairs from the single traffic class.

	The number of VFs that can be allocated depends on the number of traffic classes 
	that can be enabled. The configurable number of traffic classes for each enabled 
	VF is as follows:

	  0 - 15 VFs = Up to 8 traffic classes, depending on device support

	  16 - 31 VFs = Up to 4 traffic classes

	  32 - 63 = 1 traffic class 

	When VFs are configured, the PF is allocated one pool as well. The PF supports 
	the DCB features with the constraint that each traffic class will only use a 
	single queue pair. When zero VFs are configured, the PF can support multiple 
	queue pairs per traffic class.

```

---------------

如果编译时disable了LRO，但没有disable RSC，可以用 ethtool -C eth2 rx-usecs 0 临时解决，或用 max_vfs=1 ？？？

https://bugzilla.redhat.com/show_bug.cgi?id=680998

```

	Chris Wright has this board in hands, here the comment from him:
	> OK, disabling hw RSC with 'ethtool -C eth2 rx-usecs 0' (thanks
	> Herbert!) is bringing this back for me (something like ~1800 Mb/s).
	> This is roughly what booting with max_vfs=1 should have done, so I'm not
	> sure why that didn't work.

	Note that disabling coalescing with ethtool results in better, 
	though still poor performance as would be expected since we're disabling coalescing. 
	The "max_vfs=1" parameter disables RSC as a side-effect and 
	doesn't have the performance hit that disabling interrupt coalescing on the NIC does. 
	In internal testing, "max_vfs=1" results in ~2.5x better performance than using ethtool.

```


