---
layout: post
title: "二分图匹配, 二分图的最大独立集"
date: 2012-10-11 11:35:00 +0800
comments: false
categories:
- 2012
- 2012~10
- algorithm
- algorithm~base
tags:
---
##### POJ 3692 Kindergarten（二分图匹配）
```
Kindergarten
Time Limit: 2000MS		   Memory Limit: 65536K
Total Submissions: 3866		   Accepted: 1832

Description

In a kindergarten, there are a lot of kids. All girls of the kids know each other and all boys also know each other. In addition to that, some girls and boys know each other. Now the teachers want to pick some kids to play a game, which need that all players know each other. You are to help to find maximum number of kids the teacher can pick.

Input

The input consists of multiple test cases. Each test case starts with a line containing three integers
G, B (1 ≤ G, B ≤ 200) and M (0 ≤ M ≤ G × B), which is the number of girls, the number of boys and
the number of pairs of girl and boy who know each other, respectively.
Each of the following M lines contains two integers X and Y (1 ≤ X≤ G,1 ≤ Y ≤ B), which indicates that girl X and boy Y know each other.
The girls are numbered from 1 to G and the boys are numbered from 1 to B.

The last test case is followed by a line containing three zeros.

Output

For each test case, print a line containing the test case number( beginning with 1) followed by a integer which is the maximum number of kids the teacher can pick.

Sample Input

2 3 3
1 1
1 2
2 3
2 3 5
1 1
1 2
2 1
2 2
2 3
0 0 0

Sample Output

Case 1: 3
Case 2: 4

Source
2008 Asia Hefei Regional Contest Online by USTC
```

幼儿园有g个女孩和b个男孩，同性之间互相认识，而且男孩和女孩之间有的也互相认识。现在要选出来最多的孩子，他们之间都互相认识。

一道基础的二分图最大独立集问题。  
二分图的最大独立集 = n-最小覆盖集 = n-完美匹配数。  

所以就转化成了二分图匹配，用匈牙利算法实现即可。
 
```
	/*
	POJ 3692
	反过来建图，建立不认识的图，就变成求最大独立集了。
	*/
	#include<stdio.h>
	#include<iostream>
	#include<string.h>
	#include<algorithm>
	using namespace std;

	/* **************************************************************************
	//二分图匹配（匈牙利算法的DFS实现）
	//初始化：g[][]两边顶点的划分情况
	//建立g[i][j]表示i->j的有向边就可以了，是左边向右边的匹配
	//g没有边相连则初始化为0
	//uN是匹配左边的顶点数，vN是匹配右边的顶点数
	//调用：res=hungary();输出最大匹配数
	//优点：适用于稠密图，DFS找增广路，实现简洁易于理解
	//时间复杂度:O(VE)
	//***************************************************************************/
	//顶点编号从0开始的
	const int MAXN=510;
	int uN,vN;//u,v数目
	int g[MAXN][MAXN];
	int linker[MAXN];
	bool used[MAXN];
	bool dfs(int u)//从左边开始找增广路径
	{
		int v;
		for(v=0;v<vN;v++)//这个顶点编号从0开始，若要从1开始需要修改
			if(g[u][v]&&!used[v])
			{
				used[v]=true;
				if(linker[v]==-1||dfs(linker[v]))
				{//找增广路，反向
					linker[v]=u;
					return true;
				}
			}
		return false;//这个不要忘了，经常忘记这句
	}
	int hungary()
	{
		int res=0;
		int u;
		memset(linker,-1,sizeof(linker));
		for(u=0;u<uN;u++)
		{
			memset(used,0,sizeof(used));
			if(dfs(u)) res++;
		}
		return res;
	}

	int main()
	{
		int m;
		int u,v;
		int iCase=0;
		while(scanf("%d%d%d",&uN,&vN,&m)!=EOF)
		{
			iCase++;
			if(uN==0&&vN==0&&m==0)break;
			for(int i=0;i<uN;i++)
				for(int j=0;j<vN;j++)
					g[i][j]=1;
			while(m--)
			{
				scanf("%d%d",&u,&v);
				u--;
				v--;
				g[u][v]=0;
			}
			printf("Case %d: %d\n",iCase,uN+vN-hungary());
		}
		return 0;
	}
```

