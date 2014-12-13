---
layout: post
title: "异或值最大"
date: 2012-10-11 11:43:00 +0800
comments: false
categories:
- 2012
- 2012~10
- algorithm
- algorithm~top
tags:
---
http://acm.hust.edu.cn:8080/judge/problem/viewProblem.action?id=18669

http://acm.sgu.ru/problem.php?contest=0&problem=275

####  275. To xor or not to xor

time limit per test: 0.5 sec.  
memory limit per test: 65536 KB

input: standard  
output: standard

The sequence of non-negative integers  A1, A2, ..., AN is given. You are to find some subsequence Ai1, Ai2, ..., Aik(1 <= i1< i2< ... < ik<= N) such, that Ai1XOR Ai2XOR ... XOR Aikhas a maximum value. 

##### Input  
The first line of the input file contains the integer number N (1 <= N <= 100). The second line contains the sequence A1, A2, ..., AN (0 <= Ai <= 10^18).

##### Output
Write to the output file a single integer number -- the maximum possible value of Ai1XOR Ai2XOR ... XOR Aik.

##### Sample test(s)
##### Input
3
11 9 5

##### Output
14 

从n个数中选出若干个使得异或的值最大

```
	#include<stdio.h>
	#include<iostream>
	#include<queue>
	using namespace std;
	priority_queue<__int64> q;
	int main() {
		int n;
		__int64 ans, pre, i;
		while (scanf("%d", &n) != EOF) {
		    while (n--) {
		        scanf("%I64d", &i);
		        q.push(i);
		    }
		    ans = 0;
		    pre = 0;
		    while (!q.empty()) {
		        i = q.top();
		        q.pop();
		        if ((pre ^ i) != 0 && (pre ^ i) < pre && (pre ^ i) < i) {
		            q.push(pre ^ i);
		        } else {
		            if ((ans ^ i) > ans) {
		                ans ^= i;
		            }
		            pre = i;
		        }
		    }
		    printf("%I64d\n", ans);
		}
	}
```

