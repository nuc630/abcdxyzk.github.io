---
layout: post
title: "octopress侧边栏添加内容"
date: 2014-11-13 23:21:52 +0800
comments: true
categories:
- 2014
- 2014~11
- blog
- blog~octopress
tags:
- blog
- octopress
---

<h4>1.添加about页面</h4>
rake new_page[about]</br>
会生成 source/about/index.markdown 文件。</br>
编辑该文件的内容。</br>
然后在头部导航菜单中添加页面的超链接。具体做法是编辑 /source/_includes/custom/navigation.html 文件。</br>
<h4>2.增加链接</h4>
在source/_includes/custom/asides创建blog_link.html，代码如下：</br>
```
<section>
<h1>link</h1>
<ul>
        <li>
                <a href=http://hi.baidu.com/abcdxyzk target=_blank>My</a>
        </li>
</ul>
</section>
```
然后修改_config.yml文件在default_asides中加入custom/asides/blog_link.html。</br>
<h4>3.支持评论</h4>
Octopress自身不支持评论功能，不过我们可以使用第三方的评论系统，国外的有Disqus。下面介绍怎样在Octopress中使用Disqus。</br>
首先需要在Disqus注册一个账号，登录后点击Add Disqus to your site，然后添加站点信息site name和url，记下右侧的name</br>
然后在_config.yml文件中进行下面设置</br>
```
	# Disqus Comments
	disqus_short_name: 为添加站点信息时的name
	disqus_show_comment_count: true
```
<h4>4.添加Categories侧边栏</h4>
增加category_list插件</br>
保存到 plugins/category_list_tag.rb：</br>
```
	# encoding: UTF-8
        module Jekyll
                class CategoryListTag < Liquid::Tag
                        def render(context)
                                html = ""
                                categories = context.registers[:site].categories.keys
                                categories.sort.each do |category|
                                        posts_in_category = context.registers[:site].categories[category].size
                                        category_dir = context.registers[:site].config['category_dir']
                                        html << "<li class='category'><a href='/#{category_dir}/#{category.to_url}/'>#{category} (#{posts_in_category})</a></li>\n"
                                end
                                html
                        end
                end
        end
	Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)
```
</br>
注意：一定要在文件的开始添加# encoding: UTF-8这一行，否则无法支持中文分类。</br>
增加aside</br>
保存到 source/_includes/asides/category_list.html：注意去掉'\'</br>
```
	<section>
		<h1>Categories</h1>
		<ul id="categories">
			{\% category_list \%}
		</ul>
	</section>
```
修改_config.yml文件</br>
将category_list添加到default_asides：</br>
   default_asides: [asides/category_list.html, asides/recent_posts.html]</br>
安装这个插件后直接可以支持中文分类，url中使用的是分类的拼音，如「数据库」对应「shu-ju-ku」。如果使用中文分类时遇到各种错误，请参考下面这两篇文章：</br>
</br>
    http://aiku.me/bar/10393365</br>
    http://blog.sprabbit.com/blog/2012/03/23/octopress/</br>
</br>
<h4>5.添加tag</h4>
首先到https://github.com/robbyedwards/octopress-tag-pages</br>
和https://github.com/robbyedwards/octopress-tag-cloudclone</br>
这两个项目的代码。这两个项目分别用于产生tag page和tag cloud。 针对这两个插件，需要手工复制一些文件到你的octopress目录。</br>
</br>
octopress-tag-pages</br>
复制tag_generator.rb到plugins目录；</br>
复制tag_index.html到source/_layouts目录。</br>
复制tag_feed.xml到source/_includes/custom/目录。tag_feed.xml文件中 layout: nil 改为 layout: null</br>
其他文件就不需要复制了，都是些例子。</br>
</br>
octopress-tag-cloud</br>
仅复制tag_cloud.rb到plugins目录即可。</br>
添加aside，复制以下代码到source/_includes/custom/asides/tags.html。注意去掉'\'</br>
```
	<section>
		<h1>Tags</h1>
		<ul class="tag-cloud">
			{\% tag_cloud font-size: 90-210%, limit: 100, style: para \%}
		</ul>
	</section>
```
tag_cloud的参数中，style :para指定不使用li来分割，limit限定100个tag，font-size指定tag的大小范围，具体参数参看官方文档。</br>
最后，当然是在_config.xml的default_asides 中添加这个tag cloud到导航栏：</br>
```
default_asides: [... custom/asides/tags.html, ...]
```
<h5>bug:</h5>
除0错误，tag_cloud.rb中</br>
weight = (Math.log(count) - Math.log(min))/(Math.log(max) - Math.log(min))</br>
当max==min时出错</br>
一下修复同时改成像Categories一样显示文章数</br>
```
--- a/plugins/tag_cloud.rb
+++ b/plugins/tag_cloud.rb
@@ -54,7 +54,7 @@ def initialize(name, params, tokens)
 # map: [[tag name, tag count]] -> [[tag name, tag weight]]
        weighted = count.map do |name, count|
 # logarithmic distribution
-       weight = (Math.log(count) - Math.log(min))/(Math.log(max) - Math.log(min))
+       weight = count
        [name, weight]
        end
 # get the top @limit tag pairs when a limit is given, unless the sort method is random
@@ -92,12 +92,17 @@ def initialize(name, params, tokens)
        html = ""
 # iterate over the weighted tag Array and create the tag items
        weighted.each_with_index do |tag, i|
-       name, weight = tag
+       name, weight_orig = tag
+        if min == max
+               weight = 0.5
+       else
+               weight = (Math.log(weight_orig) - Math.log(min))/(Math.log(max) - Math.log(min))
+       end
        size = size_min + ((size_max - size_min) * weight).to_f
        size = sprintf("%.#{@precision}f", size)
        slug = name.to_url
        @separator = "" if i == (weighted.size - 1)
-       html << "#{@tag_before}<a style=\"font-size: #{size}#{unit}\" href=\"/#{dir}/#{slug}/\">#{name}</a>#{@separator}#{@tag_after}\n"
+       html << "#{@tag_before}<a style=\"font-size: #{size}#{unit}\" href=\"/#{dir}/#{slug}/\">#{name}(#{weight_orig})</a>#{@separator}#
        end
        html
        end
```
<h6>如果会出现:</h6>
添加超过一个tags之后，rake generate就会开始报错了： Error :Liquid Exception: comparison of Array with Array failed in page</br>
只需要将1个tag重复2次以上使用就可以解决。</br>
1.第1个post加的tag是：tag1，第2个post加的tag是：tag1</br>
2.rake generate</br>
3.第2个post的tag随便改：tagXXX</br>
---</br>
<h4>6.近期评论</h4>
复制以下代码到source/_includes/custom/asides/recent_comments.html，名字改成自己的</br>
```
<section id="comment_sidebar">
<h1>近期评论</h1>
<script type="text/javascript" src="http://abcdxyzk.disqus.com/recent_comments_widget.js?num_items=10&hide_avatars=0&avatar_size=32&excerpt_length=20"></script><a href="http://disqus.com/">Powered by Disqus</a>
</section>
```
修改_config.yml</br>
最后，当然是在_config.xml的default_asides 中添加这个tag cloud到导航栏：</br>
```
default_asides: [... custom/asides/recent_comments.html, ...]
```

<h4>7.优化</h4>

删除</br>
 source/_includes/custom/head.html</br>
 source/_includes/head.html</br>
中googleapis</br>

<h4>8.BUG，最新octopress的已经修复</h4>
除了根目录，其他目录无法将右侧缩到底部。</br>
可以修改一下source/_includes/head.html文件，去掉src中的'.'，改成如下：</br>
```
  <script>!window.jQuery && document.write(unescape('%3Cscript src="/javascripts/libs/jquery.min.js"%3E%3C/script%3E'))</script>
```
