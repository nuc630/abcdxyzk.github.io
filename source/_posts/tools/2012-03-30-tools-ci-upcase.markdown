---
layout: post
title: "CI 处理 URL 的“大小写敏感”问题"
date: 2012-03-30 21:02:00 +0800
comments: false
categories:
- 2012
- 2012~03
- tools
- tools~ci
tags:
- oj
---
#### CI 处理 URL 的“大小写敏感”问题

找到system/core里的Router.php文件，修文件：
```
	<?php
	//找到 function _validate_request
	function_validate_request($segments)
	{
		// 增加下面这一句，其实就是强制将控制器名字转化为小写
		$segments[0] = strtolower($segments[0]);
		// Does the requested controller exist in the root folder?
		if(file_exists(APPPATH.'controllers/'.$segments[0].EXT))
		{
		    return $segments;
		}
	}
	?>
```

