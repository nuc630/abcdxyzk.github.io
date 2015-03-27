---
layout: post
title: "内核网络设备的注册与初始化(eth0...)"
date: 2015-03-27 17:56:00 +0800
comments: false
categories:
- 2015
- 2015~03
- kernel
- kernel~net
tags:
---

#### 找到eth0...之类的设备的数据结构
```
	# crash vmlinux

	p init_net
	找到：
	  dev_base_head = {
		next = 0xffff88003e48b070, 
		prev = 0xffff880037582070
	  },
	next 就是 struct net_device *dev; 中 dev->dev_list;
	算算 dev_list 在 dev 中的偏移为0x50（可能会不同）

	struct net_device 0xffff88003e48b020
	然后根据 dev中的dev_list.next取下一个net_device
	  dev_list = {
		next = 0xffff880037582070, 
		prev = 0xffffffff81b185b0
	  },
```

-----------

http://blog.csdn.net/sfrysh/article/details/5736752

首先来看如何分配内存给一个网络设备。

内核通过alloc_netdev来分配内存给一个指定的网络设备: 

```
    #define alloc_netdev(sizeof_priv, name, setup) /   
        alloc_netdev_mq(sizeof_priv, name, setup, 1)   
      
    struct net_device *alloc_netdev_mq(int sizeof_priv, const char *name,   
            void (*setup)(struct net_device *), unsigned int queue_count)  
```

其中alloc_netdev_mq中的第一个元素是每个网络设备的私有数据(主要是包含一些硬件参数，比如中断之类的)的大小，也就是net_device结构中的priv的大小。第二个参数是设备名，我们传递进来一般都是一个待format的字符串，比如"eth%d",到时多个相同类型网卡设备就会依次为eth0,1(内核会通过dev_alloc_name来进行设置)... 第三个参数setup是一个初始化net_device结构的回调函数。

可是一般我们不需要直接调用alloc_netdev的，内核提供了一些包装好的函数：

这里我们只看alloc_etherdev： 

```
    #define alloc_etherdev(sizeof_priv) alloc_etherdev_mq(sizeof_priv, 1)   
    struct net_device *alloc_etherdev_mq(int sizeof_priv, unsigned int queue_count)   
    {   
        return alloc_netdev_mq(sizeof_priv, "eth%d", ether_setup, queue_count);   
    }  
```

这里实际是根据网卡的类型进行包装，也就类似于oo中的基类，ether_setup初始化一些所有相同类型的网络设备的一些相同配置的域： 

```
    void ether_setup(struct net_device *dev)   
    {   
        dev->header_ops      = &eth_header_ops;   
      
        dev->change_mtu      = eth_change_mtu;   
        dev->set_mac_address     = eth_mac_addr;   
        dev->validate_addr   = eth_validate_addr;   
      
        dev->type        = ARPHRD_ETHER;   
        dev->hard_header_len     = ETH_HLEN;   
        dev->mtu     = ETH_DATA_LEN;   
        dev->addr_len        = ETH_ALEN;   
        dev->tx_queue_len    = 1000; /* Ethernet wants good queues */  
        dev->flags       = IFF_BROADCAST|IFF_MULTICAST;   
      
        memset(dev->broadcast, 0xFF, ETH_ALEN);   
      
    }  
```

接下来我们来看注册网络设备的一些细节。 

```
    int register_netdev(struct net_device *dev)   
    {   
        int err;   
      
        rtnl_lock();   
      
        /*  
         * If the name is a format string the caller wants us to do a  
         * name allocation.  
         */  
        if (strchr(dev->name, '%')) {   
    ///这里通过dev_alloc_name函数来对设备名进行设置。   
            err = dev_alloc_name(dev, dev->name);   
            if (err < 0)   
                goto out;   
        }   
    ///注册当前的网络设备到全局的网络设备链表中.下面会详细看这个函数.   
        err = register_netdevice(dev);   
    out:   
        rtnl_unlock();   
        return err;   
    }  
```

整个网络设备就是一个链表，他需要很方便的遍历所有设备，以及很快的定位某个指定的设备。为此net_device包含了下面3个链表(有关内核中数据结构的介绍，可以去自己google下)： 

```
    ///可以根据index来定位设备   
    struct hlist_node   index_hlist;   
    ///可以根据name来定位设备   
    struct hlist_node   name_hlist;   
    ///通过dev_list，将此设备插入到全局的dev_base_head中，我们下面会介绍这个。   
    struct list_head    dev_list;  
```

当设备注册成功后，还需要通知内核的其他组件，这里通过netdev_chain类型的notifier chain来通知其他组件。事件是NETDEV_REGISTER..其他设备通过register_netdevice_notifier来注册自己感兴趣的事件到此notifier chain上。

网络设备(比如打开或关闭一个设备)，与用户空间的通信通过rtmsg_ifinfo函数，也就是RTMGRP_LINK的netlink。

每个设备还包含两个状态，一个是state字段，表示排队策略状态(用位图表示)，一个是注册状态。

包的排队策略也就是qos了。。 

```
    int register_netdevice(struct net_device *dev)   
    {   
        struct hlist_head *head;   
        struct hlist_node *p;   
        int ret;   
        struct net *net;   
      
        BUG_ON(dev_boot_phase);   
        ASSERT_RTNL();   
      
        might_sleep();   
      
        /* When net_device's are persistent, this will be fatal. */  
        BUG_ON(dev->reg_state != NETREG_UNINITIALIZED);   
        BUG_ON(!dev_net(dev));   
        net = dev_net(dev);   
      
    ///初始化相关的锁   
        spin_lock_init(&dev->addr_list_lock);   
        netdev_set_addr_lockdep_class(dev);   
        netdev_init_queue_locks(dev);   
      
        dev->iflink = -1;   
      
        /* Init, if this function is available */  
        if (dev->init) {   
            ret = dev->init(dev);   
            if (ret) {   
                if (ret > 0)   
                    ret = -EIO;   
                goto out;   
            }   
        }   
      
        if (!dev_valid_name(dev->name)) {   
            ret = -EINVAL;   
            goto err_uninit;   
        }   
    ///给设备分配一个唯一的identifier.   
        dev->ifindex = dev_new_index(net);   
        if (dev->iflink == -1)   
            dev->iflink = dev->ifindex;   
      
    ///在全局的链表中检测是否有重复的名字   
        head = dev_name_hash(net, dev->name);   
        hlist_for_each(p, head) {   
            struct net_device *d   
                = hlist_entry(p, struct net_device, name_hlist);   
            if (!strncmp(d->name, dev->name, IFNAMSIZ)) {   
                ret = -EEXIST;   
                goto err_uninit;   
            }   
        }   
    ///下面是检测一些特性的组合是否合法。   
        /* Fix illegal checksum combinations */  
        if ((dev->features & NETIF_F_HW_CSUM) &&   
            (dev->features & (NETIF_F_IP_CSUM|NETIF_F_IPV6_CSUM))) {   
            printk(KERN_NOTICE "%s: mixed HW and IP checksum settings./n",   
                   dev->name);   
            dev->features &= ~(NETIF_F_IP_CSUM|NETIF_F_IPV6_CSUM);   
        }   
      
        if ((dev->features & NETIF_F_NO_CSUM) &&   
            (dev->features & (NETIF_F_HW_CSUM|NETIF_F_IP_CSUM|NETIF_F_IPV6_CSUM))) {   
            printk(KERN_NOTICE "%s: mixed no checksumming and other settings./n",   
                   dev->name);   
            dev->features &= ~(NETIF_F_IP_CSUM|NETIF_F_IPV6_CSUM|NETIF_F_HW_CSUM);   
        }   
      
      
        /* Fix illegal SG+CSUM combinations. */  
        if ((dev->features & NETIF_F_SG) &&   
            !(dev->features & NETIF_F_ALL_CSUM)) {   
            printk(KERN_NOTICE "%s: Dropping NETIF_F_SG since no checksum feature./n",   
                   dev->name);   
            dev->features &= ~NETIF_F_SG;   
        }   
      
        /* TSO requires that SG is present as well. */  
        if ((dev->features & NETIF_F_TSO) &&   
            !(dev->features & NETIF_F_SG)) {   
            printk(KERN_NOTICE "%s: Dropping NETIF_F_TSO since no SG feature./n",   
                   dev->name);   
            dev->features &= ~NETIF_F_TSO;   
        }   
        if (dev->features & NETIF_F_UFO) {   
            if (!(dev->features & NETIF_F_HW_CSUM)) {   
                printk(KERN_ERR "%s: Dropping NETIF_F_UFO since no "  
                        "NETIF_F_HW_CSUM feature./n",   
                                dev->name);   
                dev->features &= ~NETIF_F_UFO;   
            }   
            if (!(dev->features & NETIF_F_SG)) {   
                printk(KERN_ERR "%s: Dropping NETIF_F_UFO since no "  
                        "NETIF_F_SG feature./n",   
                        dev->name);   
                dev->features &= ~NETIF_F_UFO;   
            }   
        }   
      
        /* Enable software GSO if SG is supported. */  
        if (dev->features & NETIF_F_SG)   
            dev->features |= NETIF_F_GSO;   
      
    ///初始化设备驱动的kobject并创建相关的sysfs   
        netdev_initialize_kobject(dev);   
        ret = netdev_register_kobject(dev);   
        if (ret)   
            goto err_uninit;   
    ///设置注册状态。   
        dev->reg_state = NETREG_REGISTERED;   
      
        /*  
         *  Default initial state at registry is that the  
         *  device is present.  
         */  
      
    ///设置排队策略状态。   
        set_bit(__LINK_STATE_PRESENT, &dev->state);   
    ///初始化排队规则   
        dev_init_scheduler(dev);   
        dev_hold(dev);   
    ///将相应的链表插入到全局的链表中。紧接着会介绍这个函数   
        list_netdevice(dev);   
      
        /* Notify protocols, that a new device appeared. */  
    ///调用netdev_chain通知内核其他子系统。   
        ret = call_netdevice_notifiers(NETDEV_REGISTER, dev);   
        ret = notifier_to_errno(ret);   
        if (ret) {   
            rollback_registered(dev);   
            dev->reg_state = NETREG_UNREGISTERED;   
        }   
      
    out:   
        return ret;   
      
    err_uninit:   
        if (dev->uninit)   
            dev->uninit(dev);   
        goto out;   
    }  
```

这里要注意有一个全局的struct net init_net;变量，这个变量保存了全局的name,index  hlist以及全局的网络设备链表。

net结构我们这里所需要的也就三个链表： 

```
    ///设备链表   
    struct list_head    dev_base_head;   
    ///名字为索引的hlist   
    struct hlist_head   *dev_name_head;   
    ///index为索引的hlist   
    struct hlist_head   *dev_index_head;  
```

```
    static int list_netdevice(struct net_device *dev)   
    {   
        struct net *net = dev_net(dev);   
      
        ASSERT_RTNL();   
      
        write_lock_bh(&dev_base_lock);   
    ///插入全局的list   
        list_add_tail(&dev->dev_list, &net->dev_base_head);   
    插入全局的name_list以及index_hlist   
        hlist_add_head(&dev->name_hlist, dev_name_hash(net, dev->name));   
        hlist_add_head(&dev->index_hlist, dev_index_hash(net, dev->ifindex));   
        write_unlock_bh(&dev_base_lock);   
        return 0;   
    }  
```

最终执行完之后，注册函数将会执行rtnl_unlock函数，而此函数则会执行netdev_run_todo方法。也就是完成最终的注册。(要注意，当取消注册这个设备时也会调用这个函数来完成最终的取消注册)

这里有一个全局的net_todo_list的链表： 

```
    static LIST_HEAD(net_todo_list);  
```

而在取消注册的函数中会调用这个函数： 
```
    static void net_set_todo(struct net_device *dev)   
    {   
        list_add_tail(&dev->todo_list, &net_todo_list);   
    }  
```

也就是把当前将要取消注册的函数加入到todo_list链表中。 

```
    void netdev_run_todo(void)   
    {   
        struct list_head list;   
      
        /* Snapshot list, allow later requests */  
    ///replace掉net_todo_list用list代替。   
        list_replace_init(&net_todo_list, &list);   
      
        __rtnl_unlock();   
    ///当注册设备时没有调用net_set_todo函数来设置net_todo_list，因此list为空，所以就会直接跳过。   
        while (!list_empty(&list)) {   
    ///通过todo_list得到当前的device对象。   
            struct net_device *dev   
                = list_entry(list.next, struct net_device, todo_list);   
    ///删除此todo_list;   
            list_del(&dev->todo_list);   
      
      
            if (unlikely(dev->reg_state != NETREG_UNREGISTERING)) {   
                printk(KERN_ERR "network todo '%s' but state %d/n",   
                       dev->name, dev->reg_state);   
                dump_stack();   
                continue;   
            }   
    ///设置注册状态为NETREG_UNREGISTERED.   
            dev->reg_state = NETREG_UNREGISTERED;   
    ///在每个cpu上调用刷新函数。   
            on_each_cpu(flush_backlog, dev, 1);   
      
    ///等待引用此设备的所有系统释放资源，也就是引用计数清0.   
            netdev_wait_allrefs(dev);   
      
            /* paranoia */  
            BUG_ON(atomic_read(&dev->refcnt));   
            WARN_ON(dev->ip_ptr);   
            WARN_ON(dev->ip6_ptr);   
            WARN_ON(dev->dn_ptr);   
      
            if (dev->destructor)   
                dev->destructor(dev);   
      
            /* Free network device */  
            kobject_put(&dev->dev.kobj);   
        }   
    }  
```

下面来看netdev_wait_allrefs函数，我们先看它的调用流程:

```
    static void netdev_wait_allrefs(struct net_device *dev)   
    {   
        unsigned long rebroadcast_time, warning_time;   
      
        rebroadcast_time = warning_time = jiffies;   
        while (atomic_read(&dev->refcnt) != 0) {   
            if (time_after(jiffies, rebroadcast_time + 1 * HZ)) {   
                rtnl_lock();   
      
    ///给netdev_chain发送NETDEV_UNREGISTER事件，通知各个子模块释放资源   
                /* Rebroadcast unregister notification */  
                call_netdevice_notifiers(NETDEV_UNREGISTER, dev);   
      
                if (test_bit(__LINK_STATE_LINKWATCH_PENDING,   
                         &dev->state)) {   
                    /* We must not have linkwatch events  
                     * pending on unregister. If this  
                     * happens, we simply run the queue  
                     * unscheduled, resulting in a noop  
                     * for this device.  
                     */  
                    linkwatch_run_queue();   
                }   
      
                __rtnl_unlock();   
      
                rebroadcast_time = jiffies;   
            }   
      
            msleep(250);   
      
            if (time_after(jiffies, warning_time + 10 * HZ)) {   
                printk(KERN_EMERG "unregister_netdevice: "  
                       "waiting for %s to become free. Usage "  
                       "count = %d/n",   
                       dev->name, atomic_read(&dev->refcnt));   
                warning_time = jiffies;   
            }   
        }   
    }  
```


