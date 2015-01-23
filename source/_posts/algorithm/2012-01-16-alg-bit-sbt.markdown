---
layout: post
title: "树套树 -- zju2112 - rujia Liu's Present 3 D"
date: 2012-01-16 21:42:00 +0800
comments: false
categories:
- 2012
- 2012~01
- algorithm
- algorithm~base
tags:
---
##### zju2112
树状数组每个点都是一个SBT
```
	#include <stdio.h>
	#include <algorithm>
	#include <iostream>

	#define N 2000005
	using namespace std;

	int tol=0;
	struct SBT
	{
		int left,right;
		int key;
		int size;
		void init()
		{
		    left=right=0;
		    size=1;
		}
	}T[N];
	void R_Rotate(int &t)//右旋
	{
		int k=T[t].left;
		T[t].left=T[k].right;
		T[k].right=t;
		T[k].size=T[t].size;
		T[t].size=T[T[t].left].size+T[T[t].right].size+1;
		t=k;
		return ;
	}
	void L_Rotate(int &t)//左旋
	{
		int k=T[t].right;
		T[t].right=T[k].left;
		T[k].left=t;
		T[k].size=T[t].size;
		T[t].size=T[T[t].left].size+T[T[t].right].size+1;
		t=k;
	}
	void Maintain(int &t,bool flag)//维护，SBT精华之所在
	{
		if(flag==false)
		{
		    if(T[T[T[t].left].left].size>T[T[t].right].size)
		        R_Rotate(t);
		    else if(T[T[T[t].left].right].size>T[T[t].right].size)
		    {
		        L_Rotate(T[t].left);
		        R_Rotate(t);
		    }
		    else
		        return ;
		}
		else
		{
		    if(T[T[T[t].right].right].size>T[T[t].left].size)
		        L_Rotate(t);
		    else if(T[T[T[t].right].left].size>T[T[t].left].size)
		    {
		        R_Rotate(T[t].right);
		        L_Rotate(t);
		    }
		    else
		        return ;
		}
		Maintain(T[t].left,false);
		Maintain(T[t].right,true);
		Maintain(t,false);
		Maintain(t,true);
	}
	void Insert(int &t,int v)//插入
	{
		if(t==0)
		{
		    t=++tol;
		    T[t].init();
		    T[t].key=v;
		}
		else
		{
		    T[t].size++;
		    if(v<T[t].key)
		        Insert(T[t].left,v);
		    else
		        Insert(T[t].right,v);
		    Maintain(t,v>=T[t].key);
		}
	}
	int Delete(int &t,int v)//删除
	{
		if(!t)
		    return 0;
		T[t].size--;
		if(v==T[t].key||v<T[t].key&&!T[t].left||v>T[t].key&&!T[t].right)
		{
		    if(T[t].left&&T[t].right)
		    {
		        int p=Delete(T[t].left,v+1);
		        T[t].key=T[p].key;
		        return p;
		    }
		    else
		    {
		        int p=t;
		        t=T[t].left+T[t].right;
		        return p;
		    }
		}
		else
		    return Delete(v<T[t].key?T[t].left:T[t].right,v);
	}
	int Find_k(int t,int k)//找出第k大数
	{
	   if(k<=T[T[t].left].size)
		    return Find_k(T[t].left,k);
		else if(k>T[T[t].left].size+1)
		    return Find_k(T[t].right,k-T[T[t].left].size-1);
		return T[t].key;
	}
	int Getmin(int t)//取最小值
	{
		while(T[t].left)
		    t=T[t].left;
		return t;
	}
	int Getmax(int t)//取最大值
	{
		while(T[t].right)
		    t=T[t].right;
		return t;
	}
	int Rank(int t,int key)//排名其实就是它的左子树的size+1
	{
		if(t==0)
		    return 0;
		if(key<T[t].key)
		    return Rank(T[t].left,key);
		else
		    return T[T[t].left].size+1+Rank(T[t].right,key);
	}
	int Exist(int t,int x)//判断这个节点是否存在
	{
		if(t==0)
		    return 0;
		if(x<T[t].key)
		    return Exist(T[t].left,x);
		else if(x==T[t].key)
		    return 1;
		else
		    return Exist(T[t].right,x);
	}
	int Count(int t,int x)//统计出现次数
	{
		if(!Exist(t,x))
		    return 0;
		else
		    return Rank(t,x+1)-Rank(t,x);
	}
	int Pred(int t,int v)//返回比v小的最大的数
	{
		if(t==0)
		    return v;
		else if(v>T[t].key)
		{
		    int ret=Pred(T[t].right,v);
		    if(ret==v)
		        return T[t].key;
		    return ret;
		}
		else
		    return Pred(T[t].left,v);
	}
	int Succ(int t,int v)//返回比v大的最小的数
	{
		if(t==0)
		    return v;
		else if(v<T[t].key)
		{
		    int ret=Succ(T[t].left,v);
		    if(ret==v)
		        return T[t].key;
		    return ret;
		}
		else
		    return Succ(T[t].right,v);
	}


	int n,m, C[100009], a[100009];

	void Myinsert(int x, int y)
	{
		while(x <= n) {
		    Insert(C[x], y);
		    x += x&(-x);
		}
	}

	void Mydelete(int x, int y)
	{
		while(x <= n) {
		    Delete(C[x], y);
		    x += x&(-x);
		}
	}

	int Myrank(int x, int y)
	{
		int t=0;
		while(x > 0) {
		    t += Rank(C[x], y);
		    x -= x&(-x);
		}
		return t;
	}

	int main()
	{
		int i,j,k;
		int low,mid,up;
		int T;
		scanf("%d", &T);
		while(T--)
		{
		    scanf("%d %d", &n, &m);
		    tol = 0;
		    for(i=0;i<=n;i++) C[i] = 0;
		    for(i=1;i<=n;i++)
		    {
		        scanf("%d", &a[i]);
		        Myinsert(i, a[i]);
		    }
		    while(m--)
		    {
		        char ch[5];
		        scanf("%s", ch);
		        if(ch[0] == 'Q')
		        {
		            scanf("%d %d %d", &i, &j, &k);
		            low = 0; up = 1000000000;
		            while(low < up)
		            {
		                mid = (low+up)>>1;
		                int s1 = Myrank(i-1, mid);
		                int s2 = Myrank(j, mid);
		                if(s2 - s1 < k)
		                    low = mid+1;
		                else
		                    up = mid;
		            }
		            printf("%d\n", (low+up)>>1);
		        }
		        else
		        {
		            scanf("%d %d", &i, &k);
		            Mydelete(i, a[i]);
		            Myinsert(i, k);
		            a[i] = k;
		        }
		    }
		}
		return 0;
	}
```

