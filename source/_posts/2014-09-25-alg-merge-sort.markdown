---
layout: post
title: "1.5倍空间归并排序--Knuth"
date: 2014-09-25 11:42:00 +0800
comments: false
categories:
- 2014
- 2014~09
- algorithm
- algorithm~base
tags:
- sort
---
divide-and-conquer algorithm, in the style
suggested by Knuth volume 3 (2nd edition),
```
   |-------------I-------------|-------------|

         p1            p2            ex

p1+p2原数组，p1前半部分，p2后半部分，ex额外空间
1、将p2用ex额外空间排到p2
2、将p1排到ex
3、将p2、ex合并到原数组
```
