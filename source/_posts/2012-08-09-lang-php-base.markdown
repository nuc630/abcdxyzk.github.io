---
layout: post
title: "php基础"
date: 2012-08-09 14:27:00 +0800
comments: false
categories:
- 2012
- 2012~08
- language
- language~web
tags:
---
#### php读取标准输入的方式
```
	<?php
	$fp = fopen("/dev/stdin", "r");
	while($input = fgets($fp)) {
	   echo $input;
	}
	?>
```

#### php 'all'==0
```
	<?php
	    var_dump('all'==0);
	?>
```
输出 bool(true)

