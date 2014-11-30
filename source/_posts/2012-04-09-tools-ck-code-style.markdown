---
layout: post
title: "在网页中嵌入CKeditor编辑器"
date: 2012-04-09 17:57:00 +0800
comments: false
categories:
- 2012
- 2012~04
- system
- system~tools
tags:
- oj
---
#### 1. 
在 http://ckeditor.com/download 上下载最新版本的CKeditor。将下载的文件解压，然后将4M多的文件减肥：可以删掉_samples、_source、_tests这三个无用的文件夹；打开lang文件夹，删掉除_languages.js、en.js、zh-cn.js以外的所有文件；如果你不用office2003和v2两种皮肤，可以把skin目录下的这两个目录也都删掉。这样就做的了准备工作。  
将ckeditor压缩包解压放在网站根目录下的“ckeditor”文件夹里：
引入ckeditor.js文件：
```
<script type="text/javascript" src="ckeditor/ckeditor.js"></script>
```
你也可以将这些文件放在你网站的其他任何一个地方，默认为“ckeditor”。
 
#### 2. 在要使用ckeditor编辑器的地方插入脚本：
```
	<script type="text/javascript">CKEDITOR.replace( '多行文本的name',{skin : "kama",width:520} );</script>
	如：
	<textarea cols="80" rows="10" name="message">Please input the content in here</textarea>
	<script type="text/javascript">CKEDITOR.replace( 'message',{skin : "kama",width:520} );</script>
```
这样就将name为message的多行文本替换成了ckeditor编辑器形式的输入框
 
#### 3.获取内容：
```
	<?php
	$message=$_POST['message'];
	?>
``` 
#### 4.自定义ckeditor
##### 4-1.设置编辑器皮肤、宽高
如：
```
	<textarea  cols="90" rows="10" id="content" name="content">cftea</textarea>
	<script type="text/javascript" src="ckeditor/ckeditor.js"></script>
	<script type="text/javascript">
	<!--
	CKEDITOR.replace("content",
	  {
	      skin: "kama", width:700, height:300
	  });
	//-->
	</script>
```

