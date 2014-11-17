# encoding: UTF-8
	module Jekyll
		class CategoryListTag < Liquid::Tag
			def render(context)
				showArticle = context.registers[:site].config['showArticle']
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
								htmltime << "<div id='#{pret1}' class='divclassdate'>"
								lt1 = 1
							end
							htmltime << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pret1}'>#{cats[0]}-#{cats[1]}</a>"
							if showArticle
								htmltime << "<a href='##' onmousedown=showDiv('#{pret1}~list_#{cats[1]}')><span class='right_span' id='exp_#{pret1}~list_#{cats[1]}'>+#{posts_in_category}</span></a></li>\n"
								htmltime << "<div id='#{pret1}~list_#{cats[1]}' class='div_list_2'>"
								for post in context.registers[:site].categories[category]
									htmltime << "<li><a href=#{post.url}?opendiv=#{pret1}~list_#{cats[1]}><span class='div_list_123'>#{post.title}</span></a></li>"
								end
								htmltime << "</div>"
							else
								htmltime << "<span class='right_span' id='exp_#{pret1}~list_#{cats[1]}'>#{posts_in_category}</span></li>\n"
							end
						else
							if lt1 > 0
								htmltime << "</div>"
								lt1 = 0
							end
							pret1 = cats[0]
							htmltime << "<li class='categoryclass'><a href='##' onmousedown=showDiv('#{pret1}')><span class='exp_style' id='exp_#{pret1}'>[+]</span></a><a href='/#{category_dir}/#{category.to_url}/'>#{category}</a>"

							if showArticle
								htmltime << "<a href='##' onmousedown=showDiv('list_#{pret1}')><span class='right_span' id='exp_list_#{pret1}'>+#{posts_in_category}</span></a></li>\n"
								htmltime << "<div id='list_#{pret1}' class='div_list_1'>"
								for post in context.registers[:site].categories[category]
									htmltime << "<li><a href=#{post.url}?opendiv=list_#{pret1}><span class='div_list_123'>#{post.title}</span></a></li>"
								end
								htmltime << "</div>"
							else
								htmltime << "<span class='right_span' id='exp_list_#{pret1}'>(#{posts_in_category})</span></li>\n"
							end
						end
					elsif cats.size == 3
						if l2 == 0
							html << "<div id='#{pre1}~#{pre2}' class='divclasssub'>"
							l2 = 1
						end
						html << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}~#{pre2}'>#{cats[2]}</a>"

						if showArticle
							html << "<a href='##' onmousedown=showDiv('#{pre1}~#{pre2}~list_#{cats[2]}')><span class='right_span' id='exp_#{pre1}~#{pre2}~list_#{cats[2]}'>+#{posts_in_category}</span></a></li>\n"

							html << "<div id='#{pre1}~#{pre2}~list_#{cats[2]}' class='div_list_3'>"
							for post in context.registers[:site].categories[category]
								html << "<li><a href=#{post.url}?opendiv=#{pre1}~#{pre2}~list_#{cats[2]}><span class='div_list_123'>#{post.title}</span></a></li>"
							end
							html << "</div>"
						else
							html << "<span class='right_span' id='exp_#{pre1}~#{pre2}~list_#{cats[2]}'>#{posts_in_category}</span></li>\n"
						end
					elsif cats.size == 2
						if l2 > 0
							html << "</div>"
						end
						if l1 == 0
							html << "<div id='#{pre1}' class='divclass'>"
							l1 = 1
						end
						l2 = 0
						pre2 = cats[1]
						html << "<li><a href='##' onmousedown=showDiv('#{pre1}~#{pre2}') id='aexp_#{pre1}~#{pre2}'><span class='exp_style' id='exp_#{pre1}~#{pre2}'>[+]</span></a><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}'>#{cats[1]}</a>"
						if showArticle
							html << "<a href='##' onmousedown=showDiv('#{pre1}~list_#{pre2}')><span class='right_span' id='exp_#{pre1}~list_#{pre2}'>+#{posts_in_category}</span></a></li>\n"
							html << "<div id='#{pre1}~list_#{pre2}' class='div_list_2'>"
							for post in context.registers[:site].categories[category]
								html << "<li><a href=#{post.url}?opendiv=#{pre1}~list_#{pre2}><span class='div_list_123'>#{post.title}</span></a></li>"
							end
							html << "</div>"
						else
							html << "<span class='right_span' id='exp_#{pre1}~list_#{pre2}'>#{posts_in_category}</span></li>\n"
						end
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
						html << "<li class='categoryclass'><a href='##' onmousedown=showDiv('#{pre1}') id='aexp_#{pre1}'><span class='exp_style' id='exp_#{pre1}'>[+]</span></a><a href='/#{category_dir}/#{category.to_url}/'>#{category}</a>"

						if showArticle
							html << "<a href='##' onmousedown=showDiv('list_#{pre1}')><span class='right_span' id='exp_list_#{pre1}'>+#{posts_in_category}</span></a></li>\n"
							html << "<div id='list_#{pre1}' class='div_list_1'>"
							for post in context.registers[:site].categories[category]
								html << "<li><a href=#{post.url}?opendiv=list_#{pre1}><span class='div_list_123'>#{post.title}</span></a></li>"
							end
							html << "</div>"
						else
							html << "<span class='right_span' id='exp_list_#{pre1}'>(#{posts_in_category})</span></li>\n"
						end
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

