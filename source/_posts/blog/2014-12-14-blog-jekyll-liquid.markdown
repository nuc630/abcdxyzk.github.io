---
layout: post
title: "liquid用法笔记"
date: 2014-12-14 14:54:00 +0800
comments: false
categories:
- 2014
- 2014~12
- blog
- blog~jekyll
tags:
---
[原文](http://blog.csdn.net/dont27/article/details/38097581)

* 注意本文代码中的 `{ {`,`{ %`,`% }`,`} }`,`{ { {`,`} } }` 中间的空格都要去掉才能执行

在折腾github上博客的时候, 遇到一些jekyll, 正确来说应该是Liquid用法的问题。
于是一系列搜索之后终于找到了比较容易理解的[文档>>](https://github.com/Shopify/liquid/wiki/Liquid-for-Designers)

关于Liquid的语法使用，看完一遍，就能愉快的在github上继续折腾博客了。有些看不大懂，没翻译，都是自己的见解，有些根本用不上就不解释了。

##### Liquid有两种标记类型： Output 和 Tag.
  Output标记，用于输出文本，格式采用 `{ { 两个尖括号包围 } }`  
  Tag标记，用于执行命令或者处理 格式: `{ % 一对尖括号内一对百分号 % }`  

我的见解是: 类比jsp格式, Output相当于 <%=variable>，即输出变量值;  
Tag相当于<% int i=2 ;%>,一种数据处理,但不做输出效果.

#### Output
例子:
```
Hello { {name} }
Hello { {user.name} }
Hello { { 'tobi' } }
```
##### 高级Output: Filters//过滤器
Filters过滤器,数据处理的操作方法.  
过滤器的第一个参数，往往是过滤器运算符'|'左边的Output，而过滤器的返回值，是通过过滤运算符右边的操作所得到的，过滤器可以叠加操作，最终得到该Output所要输出的值。(这段我见解，翻译不过来 = =)  
如下：  
```
Hello { { 'tobi' | upcase } }
Hello tobi has { { 'tobi' | size } } letters!
Hello { { 'now' | date: "%Y %h" } }
```
##### 标准过滤器
```
	date - 格式化时间
	capitalize - 输出字符串，字符串（句子）首字母大写 e.g. 假设tb为"hello world"{ { tb|capitalize } } #=> 'Hello world'
	downcase - 转换小写
	upcase - 转换大写
	first - 获取数组的第一个元素
	last - 获取数组的最后一个元素
	join - 用指定的字符拼接数组元素
	sort - 排序数组
	map - map/collect an array on a given property
	size - 返回数组大小
	escape - 转移字符串
	escape_once - returns an escaped version of html without affecting existing escaped entities
	strip_html - 除去字符串中的html标签?
	strip_newlines - 除去字符串中的回车?
	newline_to_br - 将所有的回车"\n" 转换成"<br />"?
	replace - 替换所有匹配内容 e.g.{ { 'forfor' | replace:'for', 'bar' } } #=> 'barbar'
	replace_first - 替换第一个匹配内容 e.g.{ { 'forfor' | replace_first:'for', 'bar' } } #=> 'barfor'
	remove - 移除所有匹配内容 e.g.{ { 'forbarforbar' | remove:'for'} } #=> 'barbar'
	remove_first - 移除第一个匹配内容 e.g.{ { 'forbarforbar' | remove_first:'for'} } #=> 'barforbar'
	truncate - truncate a string down to x characters
	truncatewords - truncate a string down to x words
	prepend - 在字符串前面加上内容 e.g.{ {'bar'|prepend:'far'} } #=> 'farbar'
	append - 字符串后面加上内容 e.g.{ {'bar'|append: 'foo'} }#=> 'barfoo'
	minus - 减法 e.g. { {4|minus:2} } #=>2
	plus - 加法 e.g. { { 4|plus:2} } #=> 6
	times - 乘法 e.g. { {10|times:2} } #=> 20
	divided_by - 除法 e.g. { { 10 | divided_by:2} } #=> 5
	split - 分割字符串 e.g.{ { "a~b" | split:'~'} } #=> ['a','b']
	modulo - 取余 e.g. { { 3 | modulo:2 } } #=> 1
```

#### Tags
Tag在模板中起到处理逻辑的作用。  
下面是目前支持的Tag:
```
	assign - 定义变量 e.g. { % assign tt = 1 % } 定义了变量tt数值为1
	capture - Block tag为变量赋值 e.g.{ % capture dont % }{ { tt } }{ % endcapture % } 将tt的值赋给 dont
	case - Block tag its the standard case...when block
	comment - Block tag 注释
	cycle - Cycle is usually used within a loop to alternate between values, like colors or DOM classes.
	for - for循环block
	if - 判断block
	include - 引入模板
	raw - 转义内容tag e.g.{ % raw % }{ { this } }{ % endraw% } #=> '{ { this } }'
	unless - Mirror of if statement
```

##### Comments
注释隐藏
```
We made 1 million dollars { % comment % } in losses { % endcomment % } this year
Raw
```
当包裹内容出现冲突语法时，不会执行其处理。
```
	{ % raw % }
	  In Handlebars, { { this } } will be HTML-escaped, but { { { that } } } will not.
	{ % endraw % }
```

##### if/else
e.g.
```
	{ % if user % }
	  Hello { { user.name } }
	{ % endif % }
```
```
	# Same as above
	{ % if user != null % }
	  Hello { { user.name } }
	{ % endif % }
```

```
	{ % if user.name != 'tobi' % }
	  Hello non-tobi
	{ % endif % }
```
```
	# Same as above
	{ % unless user.name == 'tobi' % }
	  Hello non-tobi
	{ % endunless % }
```
```
	{ % if user.payments.size > 0  % }
	   you paid !
	{ % endif % }
```

##### Case Statement
多条件
```
	{ % case condition % }
	{ % when 1 % }
	hit 1
	{ % when 2 or 3 % }
	hit 2 or 3
	{ % else % }
	... else ...
	{ % endcase % }
```
```
	{ % case template % }

	{ % when 'label' % }
		 // { { label.title } }
	{ % when 'product' % }
		 // { { product.vendor | link_to_vendor } } / { { product.title } }
	{ % else % }
		 // { {page_title} }
	{ % endcase % }
```

##### Cycle
循环列举
```
	{ % cycle 'one', 'two', 'three' % }
	{ % cycle 'one', 'two', 'three' % }
	{ % cycle 'one', 'two', 'three' % }
	{ % cycle 'one', 'two', 'three' % }
```
结果：
```
one
two
three
one
```
可以通过命名分组：
```
	{ % cycle 'group 1': 'one', 'two', 'three' % }
	{ % cycle 'group 1': 'one', 'two', 'three' % }
	{ % cycle 'group 2': 'one', 'two', 'three' % }
	{ % cycle 'group 2': 'one', 'two', 'three' % }
```
结果：
```
one
two
one
two
```

##### for 循环
循环集合：
```
	{ % for item in array % }
	  { { item } }
	{ % endfor % }
```
遍历hash时：item[0]包含键，item[1]包含值
```
	{ % for item in hash % }
	  { { item[0] } }: { { item[1] } }
	{ % endfor % }
```
for循环时，下列变量可以辅助使用：
```
forloop.length      # => length of the entire for loop
forloop.index       # => index of the current iteration
forloop.index0      # => index of the current iteration (zero based)
forloop.rindex      # => how many items are still left?
forloop.rindex0     # => how many items are still left? (zero based)
forloop.first       # => is this the first iteration?
forloop.last        # => is this the last iteration?
```
还有一些变量可以用来处理循环时选择性处理：  
limit:int - 限制遍历个数  
offset:int - 从第n个数开始遍历
```
	# array = [1,2,3,4,5,6]
	{ % for item in array limit:2 offset:2 % }
	  { { item } }
	{ % endfor % }
	# results in 3,4
```
反序遍历：
```
	{ % for item in collection reversed % } 
	{ {item} } 
	{ % endfor % }
```
除了遍历集合，还可以定义一个范围的数字来遍历：
```
	# if item.quantity is 4...
	{ % for i in (1..item.quantity) % }
	  { { i } }
	{ % endfor % }
	# results in 1,2,3,4
```

##### 变量赋值
赋值变量：
```
	{ % assign name = 'freestyle' % }

	{ % for t in collections.tags % }{ % if t == name % }
	  <p>Freestyle!</p>
	{ % endif % }{ % endfor % }
```
还可以赋值布尔值：
```
	{ % assign freestyle = false % }

	{ % for t in collections.tags % }{ % if t == 'freestyle' % }
	  { % assign freestyle = true % }
	{ % endif % }{ % endfor % }

	{ % if freestyle % }
	  <p>Freestyle!</p>
	{ % endif % }
```
赋值处理过的数据：可以用capture
```
	{ % capture attribute_name % }{ { item.title | handleize } }-{ { i } }-color{ % endcapture % }

	  <label for="{ { attribute_name } }">Color:</label>
	  <select name="attributes[{ { attribute_name } }]" id="{ { attribute_name } }">
		<option value="red">Red</option>
		<option value="green">Green</option>
		<option value="blue">Blue</option>
	  </select>
```

