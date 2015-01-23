---
layout: post
title: "插头 DP code1-2"
date: 2011-03-20 23:00:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 一、hdu_1964
```
	#include<stdio.h>
	#include<string.h>
	#include<map>

	int n,m,up[33][33],le[33][33];
	int dp[200000],pre[200000],val[33],LL,UU,sta,next;
	int a[33],b[33],d[33],c[33];
	char p[200000][12];

	int ok()
	{
		int i,l;
		l = 0;
		for(i=1;i<=m+1;i++)
		{
		    b[i] = d[i] = -1;
		    if(a[i] == 1) c[++l] = i;
		    else
		    if(a[i] == 2)
		    {
		        if(l == 0) return 0;
		        b[c[l]] = i; d[i] = c[l];
		        l--;
		    }
		}
		if(l != 0) return 0;
		return 1;
	}

	void init()
	{
		int i,j,k;

		val[1] = 1;
		for(i=2;i<=12;i++) val[i] = val[i-1]*3;

		for(i=0;i<=12;i++) a[i] = 0;
		a[1] = -1;

		for(i=0;i<=val[m+2];i++)
		{
		    a[1]++;
		    k = 1; while(k <= m+1 && a[k]>2) { a[k]%=3; a[k+1]++; k++; }

		    if(ok() == 0) continue;

		    for(j=1;j<=m+1;j++) {
		        p[i][j] = -1;
		        if(b[j] != -1) p[i][j] = b[j];
		        if(d[j] != -1) p[i][j] = d[j];
		    }
		}
	}

	void abc()
	{
		int i,j,k,ans = 1000000;

		for(i=0;i<=val[m+2];i++) dp[i] = 1000000;

		dp[0] = 0;

		for(i=1;i<=n;i++)
		    for(j=1;j<=m;j++)
		    {
		        if(j == 1)
		        {
		            for(k=val[m+2]-1;k>=0;k--)
		            {
		                dp[k] = dp[k/3];
		                if(k%3 != 0) dp[k] = 1000000;
		            }
		        }

		        for(k=0;k<val[m+2];k++)
		        {
		            pre[k] = dp[k]; dp[k] = 1000000;
		        }

		        for(k=0;k<val[m+2];k++)
		        if(pre[k] < 1000000)
		        {
		            LL = k/val[j]%3;
		            UU = k/val[j+1]%3;

		            if(UU == 0 && LL == 0)
		            {
		                sta = k+val[j]+val[j+1]+val[j+1];
		                next = pre[k]+le[i][j+1]+up[i+1][j];
		                if(dp[sta] > next) dp[sta] = next;
		            }
		            else
		            if(LL == 0)
		            {
		                sta = k;
		                next = pre[k]+le[i][j+1];
		                if(dp[sta] > next) dp[sta] = next;

		                sta = k+k/val[j+1]%3*(val[j]-val[j+1]);
		                next = pre[k]+up[i+1][j];
		                if(dp[sta] > next) dp[sta] = next;
		            }
		            else
		            if(UU == 0)
		            {
		                sta = k;
		                next = pre[k]+up[i+1][j];
		                if(dp[sta] > next) dp[sta] = next;

		                sta = k+k/val[j]%3*(-val[j]+val[j+1]);
		                next = pre[k]+le[i][j+1];
		                if(dp[sta] > next) dp[sta] = next;
		            }
		            else
		            if(LL == 2 && UU == 1)
		            {
		                sta = k-val[j]-val[j]-val[j+1];
		                next = pre[k];
		                if(dp[sta] > next) dp[sta] = next;
		            }
		            else
		            if(LL == 1 && UU == 1)
		            {
		                if(p[k][j+1] > 0 && p[k][j+1] <= m+1)
		                {
		                    sta = k-val[j]-val[j+1]-val[p[k][j+1]];
		                    next = pre[k];
		                    if(dp[sta] > next) dp[sta] = next;
		                }
		            }
		            else
		            if(LL == 2 && UU == 2)
		            {
		                if(p[k][j] > 0)
		                {
		                    sta = k-val[j]-val[j]-val[j+1]-val[j+1]+val[p[k][j]];
		                    next = pre[k];
		                    if(dp[sta] > next) dp[sta] = next;
		                }
		            }
		            else
		            if(LL == 1 && UU == 2)
		            {
		                if(i == n && j == m)
		                {
		                    sta = k-val[j]-val[j+1]-val[j+1];
		                    next = pre[k];

		                    if(dp[sta] > next) dp[sta] = next;

		                    if(dp[sta] < ans) ans = dp[sta];
		                }
		            }

		        }
		    }

		printf("%d\n",ans);
	}

	int main()
	{
		int i,j,T;
		char ch[1111];

		scanf("%d",&T);
		while(T--)
		{
		    scanf("%d %d",&n,&m);
		    gets(ch);
		    gets(ch);

		    for(i=0;i<=n+1;i++) for(j=0;j<=m+1;j++) up[i][j] = le[i][j] = 1000000;

		    for(i=1;i<=n;i++)
		    {
		        gets(ch);
		        for(j=2;j<=m;j++) le[i][j] = ch[j+j-2]-48;
		        gets(ch);

		        if(i<n)
		        {
		            for(j=1;j<=m;j++) up[i+1][j] = ch[j+j-1]-48;
		        }
		    }
		    init();
		    abc();
		}
		return 0;
	}
```

---------

##### 二、timus_1519
```
	#include<stdio.h>

	long long dp[60000],pre[60000];
	int all,r[60000],e[1600000];
	int p[60000][13];

	class DP {

	public:
		int n,m,can[33][33],last;
		int val[33],LL,UU,sta,next;
		int a[33],b[33],d[33],c[33];

		void input()
		{
		    int i,j;
		    char ch[15];
		    last = 0;
		    for(i=1;i<=n;i++)
		    {
		        scanf("%s",ch);
		        for(j=1;j<=m;j++)
		        {
		            can[i][j] = ch[j-1]=='.'?(++last):-1;
		        }
		    }
		}

		int ok()
		{
		    int i,l;
		    l = 0;
		    for(i=1;i<=m+1;i++)
		    {
		        b[i] = d[i] = -1;
		        if(a[i] == 1) c[++l] = i;
		        else
		        if(a[i] == 2)
		        {
		            if(l == 0) return 0;
		            b[c[l]] = i; d[i] = c[l];
		            l--;
		        }
		    }
		    if(l != 0) return 0;
		    return 1;
		}

		void init()
		{
		    int i,j,k;

		    val[1] = 1;
		    for(i=2;i<=m+2;i++) val[i] = val[i-1]*3;;

		    for(i=0;i<=m+2;i++) a[i] = 0;
		    a[1] = -1;

		    all = 0;

		    for(i=0;i<=val[m+2];i++)
		    {
		        a[1]++;
		        k = 1; while(k <= m+1 && a[k]>2) { a[k]%=3; a[k+1]++; k++; }

		        e[i] = -1;

		        if(ok() == 0) continue;

		        r[all] = i; e[i] = all;

		        for(j=1;j<=m+1;j++) {
		            p[all][j] = -1;
		            if(b[j] != -1) p[all][j] = b[j];
		            if(d[j] != -1) p[all][j] = d[j];
		        }

		        all++;
		    }
		}

		void abc()
		{
		    int i,j,k,l;

		    input();
		    init();

		    for(i=0;i<all;i++) dp[i] = 0;

		    dp[r[0]] = 1;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++)
		        {
		            if(j == 1)
		            {
		                for(k=all-1;k>=0;k--)
		                {
		                    l = r[k]; l = l/3; l = e[l];

		                    if(l != -1)
		                    {
		                        dp[k] = dp[l];
		                        if(r[k]%3 != 0) dp[k] = 0;
		                    }
		                    else
		                        dp[k] = 0;
		                }
		            }

		            for(k=0;k<all;k++)
		            {
		                pre[k] = dp[k]; dp[k] = 0;
		            }

		            for(k=0;k<all;k++)
		            if(pre[k] > 0)
		            {
		                LL = r[k]/val[j]%3;
		                UU = r[k]/val[j+1]%3;

		                if(can[i][j] == -1)
		                {
		                    if(LL == 0 && UU == 0)
		                    {
		                        dp[k] += pre[k];
		                    }
		                    continue;
		                }

		                if(UU == 0 && LL == 0)
		                {
		                    sta = r[k]+val[j]+val[j+1]+val[j+1];

		                    dp[e[sta]] += pre[k];
		                }
		                else
		                if(LL == 0)
		                {
		                    sta = r[k];
		                    dp[e[sta]] += pre[k];

		                    sta = r[k]+r[k]/val[j+1]%3*(val[j]-val[j+1]);
		                    dp[e[sta]] += pre[k];
		                }
		                else
		                if(UU == 0)
		                {
		                    sta = r[k];
		                    dp[e[sta]] += pre[k];

		                    sta = r[k]+r[k]/val[j]%3*(-val[j]+val[j+1]);
		                    dp[e[sta]] += pre[k];
		                }
		                else
		                if(LL == 2 && UU == 1)
		                {
		                    sta = r[k]-val[j]-val[j]-val[j+1];
		                    dp[e[sta]] += pre[k];
		                }
		                else
		                if(LL == 1 && UU == 1)
		                {
		                    if(p[k][j+1] > 0 && p[k][j+1] <= m+1)
		                    {
		                        sta = r[k]-val[j]-val[j+1]-val[p[k][j+1]];
		                        dp[e[sta]] += pre[k];
		                    }
		                }
		                else
		                if(LL == 2 && UU == 2)
		                {
		                    if(p[k][j] > 0)
		                    {
		                        sta = r[k]-val[j]-val[j]-val[j+1]-val[j+1]+val[p[k][j]];
		                        dp[e[sta]] += pre[k];
		                    }
		                }
		                else
		                if(LL == 1 && UU == 2)
		                {
		                    if(can[i][j] == last)
		                    {
		                        sta = r[k]-val[j]-val[j+1]-val[j+1];
		                        dp[e[sta]] += pre[k];
		                    }
		                }
		            }
		        }
		    printf("%lld\n",dp[r[0]]);
		}

		void solve()
		{
		    while(scanf("%d %d",&n,&m) != EOF)
		    {
		        abc();
		    }
		}
	};

	int main() {
		    DP dp;
		    dp.solve();
		    return 0;
	}
```

