---
layout: post
title: "css 二级菜单"
date: 2014-11-13 14:52:00 +0800
comments: false
categories:
- 2014
- 2014~11
- language
- language~web
tags:
---
```
	<style type="text/css">

	.divclass
	{
		display:none;
		font-size:12px;
		position:relative;
		left:0px;
		top:0px;
		padding:5px 10px 0px 10px;
		width:320px;
	}
	</style>
	<script language="javascript" type="text/javascript">

	function showDiv(divName)
	{
		if (document.getElementById(divName).style.display == "block")
			document.getElementById(divName).style.display = "none"; //隐藏层
		else
			document.getElementById(divName).style.display = "block"; //显示层
	}
	</script>
	</head>
	<body>
	<div id="menu">
	<ul>
	<li><a href="#" onmousedown="showDiv('div1')">菜单一</a></li>
		<div id="div1" class=divclass>
		<a href="#" onmousedown="showDiv('div2')">子菜单一</a>
			<div id="div2" class=divclass>
			<ul>
			<li><a href="#">子菜单一</a></li>
			<li><a href="#">子菜单二</a></li>
			<ul>
			</div>
		</div>
	<li><a href="#" onmousedown="showDiv('div3')">菜单三</a></li>
	<div id="div3" class=divclass>
	<ul>
	<ul>
	</div>
	<li><a href="#" onmousedown="showDiv('div4')">菜单四</a></li>
	<div id="div4" class=divclass>
	<ul>
		<li><a href="#">子菜单一</a></li>
		<li><a href="#">子菜单二</a></li>
	<ul>
	</div>
	</ul>
	</div>
	</body>
	</html>
	<script language="javascript" type="text/javascript">
	showDiv('div1');
	</script>
```
