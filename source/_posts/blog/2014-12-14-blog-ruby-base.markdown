---
layout: post
title: "ruby基础"
date: 2014-12-14 14:55:00 +0800
comments: false
categories:
- 2014
- 2014~12
- blog
- blog~ruby
tags:
---
#### Find
http://ruby-doc.org/stdlib-1.9.3/libdoc/find/rdoc/Find.html

```
require 'find'
total_size = 0
Find.find(ENV["HOME"]) do |path|
  if FileTest.directory?(path)
    if File.basename(path)[0] == ?.
      Find.prune       # Don't look any further into this directory.
    else
      next
    end
  else
    total_size += FileTest.size(path)
  end
end
```

#### Time
```
p Time.parse(“2002-03-17”)       #=> Sun Mar 17 00:00:00 +0800[v2] 2002
p Time.now        # =>Mon Oct 20 06:02:10 JST 2003
p Time.now.to_a      # => [10, 2, 6, 20, 10, 2003, 1, 293,false, "JST"]
p Time.now.to_f      # => 1418540681.0154862
```


