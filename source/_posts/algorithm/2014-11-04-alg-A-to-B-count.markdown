---
layout: post
title: "数A到数B之间的统计"
date: 2014-11-03 18:18:00 +0800
comments: false
categories:
- 2014
- 2014~11
- algorithm
- algorithm~base
tags:
---
[Problem 1896 神奇的魔法数](http://acm.fzu.edu.cn/problem.php?pid=1896)
```
Accept: 98    Submit: 307
Time Limit: 1000 mSec    Memory Limit : 32768 KB


Problem Description


John定义了一种“神奇的魔法数”。 不含前导零且相邻两个数字之差至少为m的正整数被称为“神奇的魔法数”。特别的，对于任意的m，数字1..9都是“神奇的魔法数”。
John想知道，对于给定的m，在正整数a和b之间，包括a和b，总共有多少个“神奇的魔法数”？

Input


第一行一个数字T（1<=T<=100），表示测试数据组数。
接下来T行，每行代表一组测试数据，包括三个整数a,b,m。（1<=a<=b<=2,000,000,000, 0<=m<=9）

Output


对于每组测试数据，输出一行表示“神奇的魔法数”的个数。

Sample Input

7 1 10 2 1 20 3 1 100 0 10 20 4 20 30 5 1 10 9 11 100 9

Sample Output

9 15 100 5 3 9 1

Source福州大学第七届程序设计竞赛
```

```
	#include <stdio.h>

	int n,m,d,dp[13][13],sum[13],dn[13],dm[13];


	// DFS的时候这两个地方根据不同要求写。
	int dfs(int da[], int dep, int all)
	{
		int i,j,ret=0;
		if (dep == 0) return 1;
		for (i=0;i<da[dep];i++)
		{
			if (all > 0 || i > 0) {
				if (all == 0 || i-da[dep+1]>=d || i-da[dep+1]<=-d)
					ret += dp[dep][i];
			} else
				ret += sum[dep-1];
		}
		if (all == 0 || da[dep]-da[dep+1]>=d || da[dep]-da[dep+1]<=-d)
			ret += dfs(da, dep-1, all+da[dep]);
		return ret;
	}

	int main()
	{
		int i,j,k,l,T;
		scanf("%d", &T);
		while (T--)
		{
			scanf("%d %d %d", &m, &n, &d);
			for (i=0;i<13;i++)
				for (j=0;j<13;j++) dp[i][j] = 0;
			sum[0] = 0; sum[1] = 9;
			for (i=0;i<10;i++) dp[1][i] = 1;
			for (i=2;i<13;i++) {
				sum[i] = sum[i-1];
				for (j=0;j<10;j++) {
					for (k=0;k<10;k++)
						if (j-k>=d || j-k<=-d)
							dp[i][j] += dp[i-1][k];
					if (j > 0)
						sum[i] += dp[i][j];
				}
			}
	//		for (i=0;i<=2;i++)
	//			for (j=0;j<10;j++) printf("%d %d %d\n", i, j, dp[i][j]);
			i = 1; k = n;
			while (i < 13) {
				dn[i] = k % 10; k /= 10;
				i++;
			}
			i = 1; k = m-1;
			while (i < 13) {
				dm[i] = k % 10; k /= 10;
				i++;
			}
			n = dfs(dn, 11, 0);
			if (m == 1)
				m = 0;
			else
				m = dfs(dm, 11, 0);
			printf("%d\n", n-m);
		}
		return 0;
	}
```

#### [How many 0's?](http://poj.org/problem?id=3286)
```
Time Limit: 1000MS
Memory Limit: 65536KTotal Submissions: 2997
Accepted: 1603

Description

A Benedict monk No.16 writes down the decimal representations of all natural numbers between and including m and n, m ≤ n. How many 0's will he write down?

Input

Input consists of a sequence of lines. Each line contains two unsigned 32-bit integers m and n, m ≤ n. The last line of input has the value of m negative and this line should not be processed.

Output

For each line of input print one line of output with one integer number giving the number of 0's written down by the monk.

Sample Input

10 11
100 200
0 500
1234567890 2345678901
0 4294967295
-1 -1

Sample Output

1
22
92
987654304
3825876150

Source

Waterloo Local Contest, 2006.5.27
```

```
	import java.util.*;
	import java.math.*;
	import java.io.*;

	public class Main {
		static long val,n,m,dp[][]=new long[13][13],a[]=new long[13],dn[]=new long[13], dm[]=new long[13], sum[]=new long[13];
		static long dfs(long dnm[], int dep, long all)
		{
			int i, j, k;
			long ret=0;
			if (dep == 0) return 0;
			for (i=0;i<dnm[dep];i++) {
				if (all > 0 || i > 0)
					ret += dp[dep][i]; // 需要计算前导0
				else
					ret += sum[dep-1]; // 不需要计算前导0
			}
			if (all > 0 && dnm[dep] == 0)
				ret += val % a[dep] + 1;
			ret += dfs(dnm, dep-1, all+dnm[dep]);
			return ret;
		}

		public static void main(String[] args) {
			int i,j,k,l;
			Scanner cin = new Scanner(System.in);
			a[1] = 10;
			for (i=2;i<13;i++) a[i] = a[i-1]*10;
			for (i=0;i<13;i++)
				for (j=0;j<13;j++) dp[i][j] = 0;
			dp[1][0] = 1;
			sum[0] = sum[1] = 0;
			for (i=2;i<13;i++) {
				sum[i] = sum[i-1];
				for (j=0;j<10;j++) {
					for (k=0;k<10;k++)
						dp[i][j] += dp[i-1][k];
					dp[i][j] += j==0 ? a[i-1] : 0;
					if (j > 0)
						sum[i] += dp[i][j];
				}
			}
			while (true) {
				m = cin.nextLong();
				n = cin.nextLong();
				if (m == -1 || n == -1) break;
				for (i=0;i<13;i++) dn[i] = dm[i] = 0;
				i = 1;
				val = n;
				while (val > 0) {
					dn[i] = val % 10;
					val /= 10;
					i++;
				}
				i = 1;
				val = m-1;
				while (val > 0) {
					dm[i] = val % 10;
					val /= 10;
					i++;
				}
				val = n;
				n = dfs(dn, 12, 0) + 1; // 0 还有一个0
				val = m-1;
				m = dfs(dm, 12, 0) + 1;
				if (val < 0) m = 0;
				System.out.println(n-m);
			}
		}
	}
```
