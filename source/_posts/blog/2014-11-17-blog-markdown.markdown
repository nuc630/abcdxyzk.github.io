---
layout: post
title: "markdown部分语法"
date: 2014-11-17 00:00:00 +0800
comments: false
categories:
- 2014
- 2014~11
- blog
- blog~markdown
tags:
---
[贴自http://wowubuntu.com/markdown/index.html](http://wowubuntu.com/markdown/index.html)
#### 段落和换行
一个 Markdown 段落是由一个或多个连续的文本行组成，它的前后要有一个以上的空行。普通段落不该用空格或制表符来缩进。  
如果你确实想要依赖 Markdown 来插入 `<br />` 标签的话，在插入处先按入两个以上的空格然后回车。  

#### 标题
Markdown 支持两种标题的语法，类 Setext 和类 atx 形式。  
类 Setext 形式是用底线的形式，利用 = （最高阶标题）和 - （第二阶标题），例如：
```
	This is an H1
	=============
	This is an H2
	-------------
```
任何数量的 = 和 - 都可以有效果。  
类 Atx 形式则是在行首插入 1 到 6 个 # ，对应到标题 1 到 6 阶，例如：
```
	# 这是 H1
	## 这是 H2
	###### 这是 H6
```
你可以选择性地「闭合」类 atx 样式的标题，这纯粹只是美观用的，若是觉得这样看起来比较舒适，你就可以在行尾加上 #，而行尾的 # 数量也不用和开头一样（行首的井字符数量决定标题的阶数）：
```
	# 这是 H1 #
	## 这是 H2 ##
	### 这是 H3 ######
```
<!--more-->
#### 列表
Markdown 支持有序列表和无序列表。  
无序列表使用星号、加号或是减号作为列表标记：
```
	*   R
	*   Gr
	*   B
```
有序列表则使用数字接着一个英文句点：
```
	1.Bird
	2.McHale
	3.Parish
```
#### 代码区块
和程序相关的写作或是标签语言原始码通常会有已经排版好的代码区块，通常这些区块我们并不希望它以一般段落文件的方式去排版，而是照原来的样子显示，Markdown 会用 `<pre>` 和 `<code>` 标签来把代码区块包起来。  
要在 Markdown 中建立代码区块很简单，只要简单地缩进 4 个空格或是 1 个制表符就可以，例如，下面的输入：
```
	这是一个普通段落：
		这是一个代码区块。
```
Markdown 会转换成：
```
	<p>这是一个普通段落：</p>
	<pre><code>这是一个代码区块。
	</code></pre>
```

#### 分隔线
你可以在一行中用三个以上的星号、减号、底线来建立一个分隔线，行内不能有其他东西。你也可以在星号或是减号中间插入空格。下面每种写法都可以建立分隔线：
```
	* * *
	***
	*****
	- - -
	---------------------------------------
```

#### 链接
Markdown 支持两种形式的链接语法： 行内式和参考式两种形式。  
不管是哪一种，链接文字都是用 [方括号] 来标记。  
要建立一个行内式的链接，只要在方块括号后面紧接着圆括号并插入网址链接即可，如果你还想要加上链接的 title 文字，只要在网址后面，用双引号把 title 文字包起来即可，例如：
```
	This is [an example](http://example.com/ "Title") inline link.
	[This link](http://example.net/) has no title attribute.
```
会产生：
```
	<p>This is <a href="http://example.com/" title="Title">
	an example</a> inline link.</p>
	<p><a href="http://example.net/">This link</a> has no
	title attribute.</p>
```
如果你是要链接到同样主机的资源，你可以使用相对路径：
```
	See my [About](/about/) page for details.
```

#### 图片
很明显地，要在纯文字应用中设计一个「自然」的语法来插入图片是有一定难度的。 
Markdown 使用一种和链接很相似的语法来标记图片，同样也允许两种样式： 行内式和参考式。  
行内式的图片语法看起来像是：
```
	![Alt text](/path/to/img.jpg)
	![Alt text](/path/to/img.jpg "Optional title")
```
详细叙述如下：  
   一个惊叹号 !  
   接着一个方括号，里面放上图片的替代文字  
   接着一个普通括号，里面放上图片的网址，最后还可以用引号包住并加上 选择性的 'title' 文字。  
参考式的图片语法则长得像这样：
```
	![Alt text][id]
```
「id」是图片参考的名称，图片参考的定义方式则和连结参考一样：  
```
	[id]: url/to/image  "Optional title attribute"
```
到目前为止， Markdown 还没有办法指定图片的宽高，如果你需要的话，你可以使用普通的 `<img>` 标签。


