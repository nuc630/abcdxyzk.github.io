---
layout: post
title: "haproxy log"
date: 2015-07-24 16:39:00 +0800
comments: false
categories:
- 2015
- 2015~07
- tools
- tools~haproxy
tags:
---
http://sharadchhetri.com/2013/10/16/how-to-enable-logging-of-haproxy-in-rsyslog/

  After installing the HAproxy 1.4 in CentOS 6.4 bydefault logging of haproxy was not enable.To enable the logging of HAProxy you have to enable it in rsyslog(In CentOS 6.4 minimal installation,rsyslog version 5.2 is shipped).
To setup logging in HAproxy,follow the given below steps

#### Step 1: 
In Global Section of haproxy.cfg put the value log 127.0.0.1 local0 .Like given below
```
	global
		log 127.0.0.1   local0
```

#### Step 2: 
Create new haproxy configuration file in /etc/rsyslog.d . Here we are keeping the log in localhost or in other words we should say HAproxy server

#### Note:
local0.=info -/var/log/haproxy.log defines the http log will be saved in haproxy.log

local0.notice -/var/log/haproxy-status.log defines the Server status like start,stop,restart,down,up etc. will be saved in haproxy-status.log

UDPServerRun 514 means opening UDP port no. 514 to listen haproxy messages

```
	vi /etc/rsyslog.d/haproxy.conf

	$ModLoad imudp
	$UDPServerRun 514 
	$template Haproxy,"%msg%\n"
	local0.=info -/var/log/haproxy.log;Haproxy
	local0.notice -/var/log/haproxy-status.log;Haproxy
	### keep logs in localhost ##
	local0.* ~ 
```

#### Step 3: 
Now restart the HAproxy service
```
	/etc/init.d/haproxy restart
```
After restarting the haproxy service two logs will be created itself i.e haproxy.log and haproxy-status.log

#### Step 4: 
Check your logrotae file for haproxy also so that logs keep on rotating and compress itself. If bydefault it is not present in /etc/logrotate.d directory then create a new file called haproxy and paste the given below code.

Here I am keeping the logs upto 120 days hence rotate 120 and daily is written in file.
```
	cat /etc/logrotate.d/haproxy

	/var/log/haproxy.log {
		missingok
		notifempty
		sharedscripts
		rotate 120
		daily
		compress
		postrotate
			reload rsyslog >/dev/null 2>&1 || true
		endscript
	}
```

