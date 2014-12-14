---
layout: post
title: "ruby字符串处理函数"
date: 2014-12-14 15:15:00 +0800
comments: false
categories:
- 2014
- 2014~12
- blog
- blog~ruby
tags:
---
##### 1.返回字符串的长度
```
str.length => integer
```

##### 2.字符串索引index
```
str.index(substring [, offset])   => fixnum or nil
str.index(fixnum [, offset])      => fixnum or nil
str.index(regexp [, offset])      => fixnum or nil

Returns the index of the first occurrence of the given substring, character (fixnum), 
or pattern (regexp) in str. Returns nil if not found. If the second parameter is present, 
it specifies the position in the string to begin the search.

   "hello".index('e')             #=> 1
   "hello".index('lo')            #=> 3
   "hello".index('a')             #=> nil
   "hello".index(101)             #=> 1
   "hello".index(/[aeiou]/, -3)   #=> 4
```
###### 从尾到头rindex
```
str.rindex(substring [, fixnum])   => fixnum or nil
str.rindex(fixnum [, fixnum])   => fixnum or nil
str.rindex(regexp [, fixnum])   => fixnum or nil

Returns the index of the last occurrence of the given substring, character (fixnum), 
or pattern (regexp) in str. Returns nil if not found. If the second parameter is present, 
it specifies the position in the string to end the search---characters beyond this point will not be considered.

   "hello".rindex('e')             #=> 1
   "hello".rindex('l')             #=> 3
   "hello".rindex('a')             #=> nil
   "hello".rindex(101)             #=> 1
   "hello".rindex(/[aeiou]/, -2)   #=> 1
```

##### 3.判断字符串中是否包含另一个串
```
str.include? other_str => true or false
"hello".include? "lo"   #=> true
"hello".include? "ol"   #=> false
"hello".include? ?h     #=> true
```

##### 4.字符串插入
```
str.insert(index, other_str) => str
"abcd".insert(0, 'X')    #=> "Xabcd"
"abcd".insert(3, 'X')    #=> "abcXd"
"abcd".insert(4, 'X')    #=> "abcdX"
"abcd".insert(-3, 'X')
-3, 'X')   #=> "abXcd"
"abcd".insert(-1, 'X')   #=> "abcdX"
```

##### 5.字符串分隔,默认分隔符为空格
```
str.split(pattern=$;, [limit]) => anArray
" now's the time".split        #=> ["now's", "the", "time"]
"1, 2.34,56, 7".split(%r{,\s*}) #=> ["1", "2.34", "56", "7"]
"hello".split(//)               #=> ["h", "e", "l", "l", "o"]
"hello".split(//, 3)            #=> ["h", "e", "llo"]
"hi mom".split(%r{\s*})         #=> ["h", "i", "m", "o", "m"]
"mellow yellow".split("ello")   #=> ["m", "w y", "w"]
"1,2,,3,4,,".split(',')         #=> ["1", "2", "", "3", "4"]
"1,2,,3,4,,".split(',', 4)      #=> ["1", "2", "", "3,4,,"]
```

##### 6.字符串替换
```
str.gsub(pattern, replacement) => new_str
str.gsub(pattern) {|match| block } => new_str
"hello".gsub(/[aeiou]/, '*')              #=> "h*ll*"     #将元音替换成*号
"hello".gsub(/([aeiou])/, '<\1>')         #=> "h<e>ll<o>"   #将元音加上尖括号,\1表示保留原有字符???
"hello".gsub(/./) {|s| s[0].to_s + ' '}   #=> "104 101 108 108 111 "
```
ruby中带“!"和不带"!"的方法的最大的区别就是带”!"的会改变调用对象本身了。比方说str.gsub(/a/, 'b')，不会改变str本身，只会返回一个新的str。而str.gsub!(/a/, 'b')就会把str本身给改了。  
但是gsub和gsub!还有另外一个不同点就是，gsub不管怎么样都会返回一个新的字符串，而gsub!只有在有字符被替换的情况下才会返回一个新的字符串，假如说没有任何字符被替换，gsub!只会返回nil.

###### 字符串替换二:
```
str.replace(other_str) => str
s = "hello"         #=> "hello"
s.replace "world"   #=> "world"
```

##### 7.字符串删除:
```
str.delete([other_str]+) => new_str
"hello".delete "l","lo"        #=> "heo"
"hello".delete "lo"            #=> "he"
"hello".delete "aeiou", "^e"   #=> "hell"
"hello".delete "ej-m"          #=> "ho"
```

##### 8.去掉前和后的空格
```
str.lstrip => new_str
" hello ".lstrip   #=> "hello "
"hello".lstrip       #=> "hello"
```

##### 9.字符串匹配
```
str.match(pattern) => matchdata or nil
```

##### 10.字符串反转
```
str.reverse => new_str
"stressed".reverse   #=> "desserts"
```

##### 11.去掉重复的字符
```
str.squeeze([other_str]*) => new_str
"yellow moon".squeeze                  #=> "yelow mon" #默认去掉串中所有重复的字符
" now   is the".squeeze(" ")         #=> " now is the" #去掉串中重复的空格
"putters shoot balls".squeeze("m-z")   #=> "puters shot balls" #去掉指定范围内的重复字符
```

##### 12.转化成数字
```
str.to_i=> str
"12345".to_i             #=> 12345
```

