# encoding: UTF-8
	module Jekyll
		class CategoryListTag < Liquid::Tag
			def render(context)
				html = ""
				pre1 = ""
				pre2 = ""
				l1 = 0
				l2 = 0
				categories = context.registers[:site].categories.keys
				tmp = categories.sort
				sortby = ['language', 'compiler', 'assembly', 'tools', 'system', 'kernel', 'android', 'debug', '---', 'algorithm', 'blog']
				categories = []
				pre = ""
				sortby.each do |key|
					pre = ""
					categories = categories + [key]
					tmp.each do |category|
						cats = category.split(/~/)
						if cats[0] != key or cats.length == 1 or (cats[0] > "0000" and cats[0] < "3000")
							next
						end
						categories = categories + [category]
					end
				end
				tmp = tmp - categories
				categories = categories + tmp
				categories.each do |category|
					posts_in_category = context.registers[:site].categories[category].size
					category_dir = context.registers[:site].config['category_dir']
					cats = category.split(/~/)
					if cats[0] > "0000" and cats[0] < "3000"
						next
					end
					if cats.size == 3
						if l2 == 0
							html << "<div id='#{pre1}~#{pre2}' class='catsub2'>"
							l2 = 1
						end
						html << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}~#{pre2}'>#{cats[2]}</a>"

						html << "<span class='right_span'>#{posts_in_category}</span></li>\n"
					elsif cats.size == 2
						if l2 > 0
							html << "</div>"
						end
						if pre2 != ""
							html << "<script language='javascript' type='text/javascript'>\nif (!document.getElementById('#{pre1}~#{pre2}')) document.getElementById('aexp_#{pre1}~#{pre2}').style.visibility = 'hidden';\n</script>\n"
						end
						if l1 == 0
							html << "<div id='#{pre1}' class='catsub'>"
							l1 = 1
						end
						l2 = 0
						pre2 = cats[1]
						html << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}'>#{cats[1]}</a><a href='##' onmousedown=showDiv('#{pre1}~#{pre2}') id='aexp_#{pre1}~#{pre2}'><span class='exp_style' id='exp_#{pre1}~#{pre2}'>[+]</span></a>"
						html << "<span class='right_span'>#{posts_in_category}</span></li>\n"
					else
						if l2 > 0
							html << "</div>"
						end
						if l1 > 0
							html << "</div>"
						end
						if pre1 != ""
							# 如果一级、二级标签下面没有再分类则不展示'展开标签'
							html << "<script language='javascript' type='text/javascript'>\nif (!document.getElementById('#{pre1}')) document.getElementById('aexp_#{pre1}').style.visibility = 'hidden';\n"
							if pre2 != ""
								html << "if (!document.getElementById('#{pre1}~#{pre2}')) document.getElementById('aexp_#{pre1}~#{pre2}').style.visibility = 'hidden';\n"
							end
							html << "</script>\n"
						end
						l1 = 0
						l2 = 0
						pre1 = cats[0]
						pre2 = ""
						if cats[0] == '---'
							html << '<li><div style="background:#DDD; height:0.3em;"></div></li>'
							pre1 = ""
							next
						end
						html << "<li class='catclass'><a href='/#{category_dir}/#{category.to_url}/'>#{category}</a><a href='##' onmousedown=showDiv('#{pre1}') id='aexp_#{pre1}'><span class='exp_style' id='exp_#{pre1}'>[+]</span></a>"

						html << "<span class='right_span'>(#{posts_in_category})</span></li>\n"
					end
				end
				if l2 > 0
					html << "</div>"
				end
				if l1 > 0
					html << "</div>"
				end
				if pre1 != ""
					# 如果一级、二级标签下面没有再分类则不展示'展开标签'
					html << "<script language='javascript' type='text/javascript'>\nif (!document.getElementById('#{pre1}')) document.getElementById('aexp_#{pre1}').style.visibility = 'hidden';\n"
					if pre2 != ""
						html << "if (!document.getElementById('#{pre1}~#{pre2}')) document.getElementById('aexp_#{pre1}~#{pre2}').style.visibility = 'hidden';\n"
					end
					html << "</script>\n"
				end
				html
			end
		end
	end

Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)

