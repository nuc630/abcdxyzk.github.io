# encoding: UTF-8
	module Jekyll
		class CategoryListTag < Liquid::Tag
			def render(context)
				htmltime = ""
				html = ""
				pre1 = ""
				pre2 = ""
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
								htmltime << "<div id='#{pre1}' class='divclasssub'>"
								lt1 = 1
							end
							htmltime << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}'>#{cats[0]}-#{cats[1]}<span class='right_span'>(#{posts_in_category})</span></a></li>\n"
						else
							pre1 = cats[0]
							if lt1 > 0
								htmltime << "</div>"
								lt1 = 0
							end
							htmltime << "<li class='categoryclass'><a href='##' onmousedown=showDiv('#{pre1}')><span class='exp_style' id='exp_#{pre1}'>[+] </span></a><a href='/#{category_dir}/#{category.to_url}/'>#{category}<span class='right_span'>[#{posts_in_category}]</span></a></li>\n"
						end
					elsif cats.size == 3
						if l2 == 0
							html << "<div id='#{pre1}~#{pre2}' class='divclasssub'>"
							l2 = 1
						end
						html << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}~#{pre2}'>#{cats[2]}<span class='right_span'><#{posts_in_category}></span></a></li>\n"
					elsif cats.size == 2
						pre2 = cats[1]
						if l2 > 0
							html << "</div>"
							l2 = 0
						end
						if l1 == 0
							html << "<div id='#{pre1}' class='divclass'>"
							l1 = 1
						end
						html << "<li><a href='##' onmousedown=showDiv('#{pre1}~#{pre2}')><span class='exp_style' id='exp_#{pre1}~#{pre2}'>[+] </span></a><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre1}'>#{cats[1]}<span class='right_span'>(#{posts_in_category})</span></a></li>\n"
					else
						if l2 > 0
							html << "</div>"
							l2 = 0
						end
						if l1 > 0
							html << "</div>"
							l1 = 0
							html << "<script language='javascript' type='text/javascript'>\nif (!document.getElementById('#{pre1}~#{pre2}')) document.getElementById('exp_#{pre1}~#{pre2}').style.visibility = 'hidden';\n</script>\n"
						end
						pre1 = cats[0]
						html << "<li class='categoryclass'><a href='##' onmousedown=showDiv('#{pre1}')><span class='exp_style' id='exp_#{pre1}'>[+] </span></a><a href='/#{category_dir}/#{category.to_url}/'>#{category}<span class='right_span'>[#{posts_in_category}]</span></a></li>\n"
					end
				end
				if l2 > 0
					html << "</div>"
					l2 = 0
				end
				if l1 > 0
					html << "</div>"
					l1 = 0
				end
				if lt1 > 0
					htmltime << "</div>"
					lt1 = 0
				end
				html << "<h1>Date Categories</h1>"
				html << htmltime
				html
			end
		end
	end

Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)

