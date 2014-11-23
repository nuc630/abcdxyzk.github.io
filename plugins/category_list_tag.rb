# encoding: UTF-8
	module Jekyll
		class CategoryListTag < Liquid::Tag
			def render(context)
				htmltime = ""
				html = ""
				pre1 = ""
				pre2 = ""
				pret1 = ""
				l1 = 0
				l2 = 0
				lt1 = 0
				categories = context.registers[:site].categories.keys
				categories.sort.each do |category|
					posts_in_category = context.registers[:site].categories[category].size
					category_dir = context.registers[:site].config['category_dir']
					cats = category.split(/~/)
					if cats[0] > "0000" and cats[0] < "3000" # 如果是年，则单列
						if cats.size == 2
							if lt1 == 0
								htmltime << "<div id='#{pret1}' class='catsub'>"
								lt1 = 1
							end
							htmltime << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pret1}'>#{cats[0]}-#{cats[1]}</a>"
							htmltime << "<span class='right_span'>#{posts_in_category}</span></li>\n"
						else
							if lt1 > 0
								htmltime << "</div>"
								lt1 = 0
							end
							pret1 = cats[0]
							htmltime << "<li class='catclass'><a href='/#{category_dir}/#{category.to_url}/'>#{category}</a><a href='##' onmousedown=showDiv('#{pret1}')><span class='exp_style' id='exp_#{pret1}'>[+]</span></a>"

							htmltime << "<span class='right_span'>(#{posts_in_category})</span></li>\n"
						end
					elsif cats.size == 3
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
				if lt1 > 0
					htmltime << "</div>"
				end
				html << "<h1>Date Categories</h1>"
				html << htmltime
				html
			end
		end
	end

Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)

