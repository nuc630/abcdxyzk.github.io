---
layout: post
title: "js滚动标题"
date: 2013-01-14 18:56:00 +0800
comments: false
categories:
- 2013
- 2013~01
- language
- language~web
tags:
---
```
	<html>
	<head>
	<meta http-equiv="Content-Type" content="text/html; charset=utf-8">
	<title>滚动标题</title>
	<script language="javascript">
	var title_string = "让你的标题栏文字动起来，标题也动了";
	var title_length = title_string.length;
	var index_count = 0;
	var cmon;

	function scrollTheTitle()
	{
	    var doc_title = title_string.substring(index_count, title_length);
	    document.title = doc_title;
	    index_count++;
	}

	function loopTheScroll()
	{
	    scrollTheTitle();
	    if(index_count >= title_length)
	    {
		index_count = 0;
		//clearTimeout(cmon);
	    }
	    cmon = setTimeout("loopTheScroll();",300)
	}
	loopTheScroll();
	//-->
	</script>
	</head>
	</html>
```
