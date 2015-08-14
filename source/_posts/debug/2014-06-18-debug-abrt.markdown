---
layout: post
title: "abrt 应用程序core dump"
date: 2014-06-18 16:26:00 +0800
comments: false
categories:
- 2014
- 2014~06
- debug
- debug~base
tags:
---
#### 一、安装
```
yum install abrt
```
#### 二、设置
```
ulimit -c
ulimit -c unlimited
```
#### 三、常见错误
```
1、ERROR
$ tail -f /var/log/message
abrtd: Package 'XXX' isn't signed with proper key

$ vim /etc/abrt/abrt.conf
OR
$ vim /etc/abrt/abrt-action-save-package-data.conf
OpenGPGCheck = no

2、ERROR
tail -f /var/log/message
abrtd: Duplicate: UUID

Whenever a problem is detected, ABRT compares it with all 
existing problem data and determines whether that same problem 
has been recorded. If it has been, the existing problem data 
is updated and the most recent (duplicate) problem is not recorded again.

3、
ProcessUnpackaged = <yes/no>
This directive tells ABRT whether to process crashes 
in executables that do not belong to any package.	
```

----------------
#### abrt  
http://docs.fedoraproject.org/en-US/Fedora/14/html/Deployment_Guide/configuring.html  
https://fedorahosted.org/releases/a/b/abrt/Deployment_Guide.html  

```
21.6. Configuring ABRT

ABRT's main configuration file is /etc/abrt/abrt.conf. 
ABRT plugins can be configured through their config files, 
located in the /etc/abrt/plugins/ directory.

After changing and saving the abrt.conf configuration file, 
you must restart the abrtd daemon—as root—for the new settings to take effect:

~]# service abrtd restart

The following configuration directives are currently supported in /etc/abrt/abrt.conf.

[ Common ] Section DirectivesOpenGPGCheck = <yes/no>

Setting the OpenGPGCheck directive to yes (the default setting) tells 
ABRT to only analyze and handle crashes in applications provided by 
packages which are signed by the GPG keys whose locations are listed 
in the /etc/abrt/gpg_keys file. Setting OpenGPGCheck to no tells 
ABRT to catch crashes in all programs.

BlackList = nspluginwrapper, valgrind, strace, avant-window-navigator, [<additional_packages> ]

Crashes in packages and binaries listed after the BlackList directive 
will not be handled by ABRT. If you want ABRT to ignore other packages 
and binaries, list them here separated by commas.

ProcessUnpackaged = <yes/no>

This directive tells ABRT whether to process crashes in executables 
that do not belong to any package.	

BlackListedPaths = /usr/share/doc/*, */example*

Crashes in executables in these paths will be ignored by ABRT.

Database = SQLite3

This directive instructs ABRT to store its crash data in the SQLite3 database. 
Other databases are not currently supported. However, 
ABRT's plugin architecture allows for future support for alternative databases.

#WatchCrashdumpArchiveDir = /var/spool/abrt-upload/

This directive is commented out by default. 
Enable (uncomment) it if you want abrtd to auto-unpack crashdump tarballs 
which appear in the specified directory — in this case /var/spool/abrt-upload/ — 
(for example, uploaded via ftp, scp, etc.). You must ensure that whatever 
directory you specify in this directive exists and is writable for abrtd. 
abrtd will not create it automatically.

MaxCrashReportsSize = <size_in_megabytes>

This option sets the amount of storage space, in megabytes, 
used by ABRT to store all crash information from all users. 
The default setting is 1000 MB. Once the quota specified here has been met, 
ABRT will continue catching crashes, and in order to make room for the new crash dumps, 
it will delete the oldest and largest ones.

ActionsAndReporters = SOSreport, [<additional_plugins> ]

This option tells ABRT to run the specified plugin(s) immediately 
after a crash is detected and saved. For example, the SOSreport plugin runs 
the sosreport tool which adds the data collected by it to the created crash dump. 
You can turn this behavior off by commenting out this line. For further fine-tuning,
 you can add SOSreport (or any other specified plugin) to either the CCpp or 
Python options to make ABRT run sosreport (or any other specified plugin) after 
any C and C++ or Python applications crash, respectively. For more information 
on various Action and Reporter plugins, refer to Section 21.3, “ ABRT Plugins”

[ AnalyzerActionsAndReporters ] Section Directives

This section allows you to associate certain analyzer actions and reporter 
actions to run when ABRT catches kernel oopses or crashes in C, C++ or Python programs. 
The actions and reporters specified in any of the directives below will run only 
if you run abrt-gui or abrt-cli and report the crash that occurred. 
If you do not specify any actions and reporters in these directives, 
you will not be able to report a crash via abrt-gui or abrt-cli. 
The order of actions and reporters is important. Commenting out a directive, 
will cause ABRT not to catch the crashes associated with that directive. 
For example, commenting out the Kerneloops line will cause ABRT not to catch kernel oopses.

Kerneloops = RHTSupport, Logger

This directive specifies that, for kernel oopses, 
both the RHTSupport and Logger reporters will be run.

CCpp = RHTSupport, Logger

This directive specifies that, when C or C++ program crashes occur, 
both the RHTSupport and Logger reporters will be run.

Python = RHTSupport, Logger

This directive specifies that, when Python program crashes occur, 
both the RHTSupport and Logger reporters will be run.

Each of these destinations' details can be specified in the corresponding 
plugins/*.conf file. For example, plugins/RHTSupport.conf specifies 
which RHTSupport URL to use (set to https://api.access.redhat.com/rs by default), 
the user's login name, password for logging in to the RHTSupport site, 
etc. All these options can also be configured through the abrt-gui application
 (for more information on plugin configuration refer to Section 21.3, “ ABRT Plugins”).

[ Cron ] Section Directives <time> = <action_to_run>

The [ Cron ] section of abrt.conf allows you to specify the exact time, 
or elapsed amount of time between, when ABRT should run a certain action, 
such as scanning for kernel oopses or performing file transfers. 
You can list further actions to run by appending them to the end of this section.

Example 21.1. [ Cron ] section of /etc/abrt/abrt.conf

# Which Action plugins to run repeatedly
[ Cron ]
# h:m - at h:m
# s - every s seconds
120 = KerneloopsScanner
#02:00 = FileTransfer


The format for an entry is either 
<time_in_seconds> = <action_to_run> or <hh:mm> = <action_to_run> , 
where hh (hour) is in the range 00-23 
(all hours less than 10 should be zero-filled, i.e. preceded by a 0), 
and mm (minute) is 00-59, zero-filled likewise. 
```
