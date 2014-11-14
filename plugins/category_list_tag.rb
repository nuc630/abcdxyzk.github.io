# encoding: UTF-8
	module Jekyll
		class CategoryListTag < Liquid::Tag
			def render(context)
				html = ""
				pre = ""
				divout = 0
				categories = context.registers[:site].categories.keys
				categories.sort.each do |category|
					posts_in_category = context.registers[:site].categories[category].size
					category_dir = context.registers[:site].config['category_dir']
					cats = category.split(/~/)
					if cats.size > 1 and cats[0] == pre
						if divout == 0
							html << "<div id='#{pre}' class='divclass'>"
							divout = 1
						end
						html << "<li><a href='/#{category_dir}/#{category.to_url}/?opendiv=#{pre}'>#{cats[1]} (#{posts_in_category})</a></li>\n"
					else
						pre = cats[0]
						if divout > 0
							html << "</div>"
							divout = 0
						end
						html << "<li class='category'><a href='##' onmousedown=showDiv('#{pre}')>#{category} </a><a href='/#{category_dir}/#{category.to_url}/'>(#{posts_in_category})</a></li>\n"
					end
				end
				if divout > 0
					html << "</div>"
					divout = 0
				end
				html
			end
		end
	end

Liquid::Template.register_tag('category_list', Jekyll::CategoryListTag)

