---
layout: post
title: "PHP排序函数详解"
date: 2012-04-10 17:05:00 +0800
comments: false
categories:
- 2012
- 2012~04
- language
- language~php
tags:
---

在PHP中，对数组排序的函数有以下几个：

1. sort(array &$array[, int $sort_flags ])函数，该函数只对数组值进行排序，数组索引将随排序后自动分配。可选的第二个参数分别是SORT_REGULAR,SORT_NUMERIC,SORT_STRING,SORT_LOCAL_STRING。在对含有混合类型值的数组排序时要小心，因为 sort() 可能会产生不可预知的结果。
2. rsort(array &$array[, int $sort_flags ])，与sort()相同，只不过排序顺序相反，rsort()从高到低。
3. asort(array &$array[, int $sort_flags ])，键值排序，对于要求保持数组索引和键值不变，可以使用该函数。
4. ksort(array &$array[, int $sort_flags ])，对数组索引排序，主要运用于关联数组。
5. krsort(&array[, int $sort_flags ])，与ksort相同，只是排序顺序相反，从高到低排序。
6. arsort(array &$array[, int $sort_flags ])，与asort()相同，只是排序顺序相反，从高到低排序。
7. natsort(array &$array)，用自然排序算法对数组排序。本函数实现了一个和人们通常对字母数字字符串进行排序的方法一样的排序算法并保持原有键／值的关联，这被称为“自然排序”。
8. natcasesort(array &$array)，和natsort()相同，只不过在排序时不区分大小写。
9. usort( array &$array , callback $cmp_function )，本函数将用用户自定义的比较函数对一个数组中的值进行排序。如果要排序的数组需要用一种不寻常的标准进行排序，那么应该使用此函数。 比较函数必须在第一个参数被认为小于，等于或大于第二个参数时分别返回一个小于，等于或大于零的整数。此函数为 array 中的元素赋与新的键名。这将删除原有的键名，而不是仅仅将键名重新排序。
当usort()用于多维数组排序时，自定义排序函数的参数包含到数组第一个索引的引用。
对于CI框架usort($file_list, 'cmp_func');  更改为usort($file_list, array($this, 'cmp_func'));
10. uksort(array &$array , callback $cmp_function )，与usort相同，只不过对数组索引排序。
11. uasort ( array &$array , callback $cmp_function )，与sort相同，在排序时保持索引关联

