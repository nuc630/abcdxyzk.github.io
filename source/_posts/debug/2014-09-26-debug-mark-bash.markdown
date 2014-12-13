---
layout: post
title: "Bash软件安全漏洞检测及解决方案"
date: 2014-09-26 10:16:00 +0800
comments: false
categories:
- 2014
- 2014~09
- debug
- debug~mark
tags:
---

http://www.techweb.com.cn/ucweb/news/id/2079505

#### redhat官方提供漏洞详情

A flaw was found in the way Bash evaluated certain specially crafted environment variables. An attacker could use this flaw to override or bypass environment restrictions to execute shell commands. Certain services and applications allow remote unauthenticated attackers to provide environment variables, allowing them to exploit this issue.

#### redhat官方提供检测方式

运行命令：  
```
  $ env x='() { :;}; echo vulnerable'  bash -c "echo this is a test"
```
如果返回以下内容：则请尽快升级。
```
 vulnerable
this is a test
```

------------

http://seclists.org/oss-sec/2014/q3/650

The technical details of the vulnerability follow.

Bash supports exporting not just shell variables, but also shell
functions to other bash instances, via the process environment to
(indirect) child processes.  Current bash versions use an environment
variable named by the function name, and a function definition
starting with “() {” in the variable value to propagate function
definitions through the environment.  The vulnerability occurs because
bash does not stop after processing the function definition; it
continues to parse and execute shell commands following the function
definition.  For example, an environment variable setting of
```
  VAR=() { ignored; }; /bin/id
```
will execute /bin/id when the environment is imported into the bash
process.  (The process is in a slightly undefined state at this point.
The PATH variable may not have been set up yet, and bash could crash
after executing /bin/id, but the damage has already happened at this
point.)

The fact that an environment variable with an arbitrary name can be
used as a carrier for a malicious function definition containing
trailing commands makes this vulnerability particularly severe; it
enables network-based exploitation.

So far, HTTP requests to CGI scripts have been identified as the major
attack vector.

A typical HTTP request looks like this:
```
GET /path?query-param-name=query-param-value HTTP/1.1  
Host: www.example.com  
Custom: custom-header-value  
```
The CGI specification maps all parts to environment variables.  With
Apache httpd, the magic string “() {” can appear in these places:

* Host (“www.example.com”, as REMOTE_HOST)  
* Header value (“custom-header-value”, as HTTP_CUSTOM in this example)  
* Server protocol (“HTTP/1.1”, as SERVER_PROTOCOL)  

The user name embedded in an Authorization header could be a vector as
well, but the corresponding REMOTE_USER variable is only set if the
user name corresponds to a known account according to the
authentication configuration, and a configuration which accepts the
magic string appears somewhat unlikely.

In addition, with other CGI implementations, the request method
(“GET”), path (“/path”) and query string
(“query-param-name=query-param-value”) may be vectors, and it is
conceivable for “query-param-value” as well, and perhaps even
“query-param-name”.

The other vector is OpenSSH, either through AcceptEnv variables, TERM
or SSH_ORIGINAL_COMMAND.

Other vectors involving different environment variable set by
additional programs are expected.

