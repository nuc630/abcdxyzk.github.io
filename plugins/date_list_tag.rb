# encoding: UTF-8
	module Jekyll
		class DateCategoryListTag < Liquid::Tag
			def render(context)
				htmltime = ""
				pret1 = ""
				lt1 = 0
				categories = context.registers[:site].categories.keys
				tmp = categories.sort { |a,b| b <=> a }
				categories = []
				pre = ""
				tmp.each do |category|
					cats = category.split(/~/)
					if cats.length == 1 or cats[0] < "0000" or cats[0] > "3000"
						next
					end
					if cats[0] != pre
						categories = categories + [cats[0]]
						pre = cats[0]
					end
					categories = categories + [category]
				end
				categories.each do |category|
					posts_in_category = context.registers[:site].categories[category].size
					category_dir = context.registers[:site].config['category_dir']
					cats = category.split(/~/)
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
				end
				if lt1 > 0
					htmltime << "</div>"
				end
				htmltime
			end
		end
	end

Liquid::Template.register_tag('date_list', Jekyll::DateCategoryListTag)

