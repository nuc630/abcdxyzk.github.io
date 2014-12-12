# encoding: UTF-8
require 'find'
module Jekyll
	class DownloadList < Liquid::Tag
		def render(context)
			html = "<ul>"
			Find.find('./source/download') do |path|
				if path == "./source/download" or path.index('index.markdown')
					next
				end
				if FileTest.directory?(path)
					next
					#p "ddd #{path}"
					url = path[8..-1]
					name = path[path.rindex('/')+1..-1]
					html << "<li><a href=#{url}>#{name}</a></li>\n"
				else
					#p path
					url = path[8..-1]
					name = path[path.rindex('/')+1..-1]
					html << "<li><a href=#{url} target='_blank'>#{name}</a></li>\n"
				end
			end
			html << "</ul>"
			html
		end
	end
end

Liquid::Template.register_tag('download_list', Jekyll::DownloadList)

