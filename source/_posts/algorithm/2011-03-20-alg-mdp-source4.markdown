---
layout: post
title: "插头 DP code7-8"
date: 2011-03-20 23:03:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 七、fzu_1977
```
	#include<stdio.h>

	#define N 50000   // N = all
	#define M 1600000  // M = 3^m

	int n,m,can[33][33],last[33][33];

	int all,val[33],r[N],e[M],p[N][13],b[33],w[33],cas=0;

	long long dp[2][N];

	int H[N][15];

	void change()
	{
		int i,j,tmp[33][33];
		for(i=1;i<=n;i++) for(j=1;j<=m;j++) tmp[m-j+1][i] = can[i][j];
		j = n; n = m; m = j;
		for(i=1;i<=n;i++)
		    for(j=1;j<=m;j++) can[i][j] = tmp[i][j];
	}

	void input()
	{
		int i,j;
		char ch[33];

		scanf("%d %d",&n,&m);
		for(i=1;i<=n;i++)
		{
		    scanf("%s",ch);
		    for(j=1;j<=m;j++)
		        if(ch[j-1] == 'O') can[i][j] = 1;
		        else
		        if(ch[j-1] == '*') can[i][j] = 2;
		        else
		            can[i][j] = 0;
		}

		if(n < m) change();

		int k=0;
		for(i=1;i<=n;i++) for(j=1;j<=m;j++)
		{
		    if(can[i][j] == 1) k++;
		    last[i][j] = k;
		}
	}

	int ok(int kk)
	{
		int i,l,a[15],c[15];
		for(i=1;i<=m+1;i++) { a[i] = kk%3; kk /= 3; b[i] = -1; }
		l = 0;
		for(i=1;i<=m+1;i++)
		    if(a[i] == 1) c[++l] = i;
		    else
		    if(a[i] == 2)
		    {
		        if(l == 0) return 0;
		        b[c[l]] = i; b[i] = c[l];
		        l--;
		    }
		if(l > 0) return 0;
		return 1;
	}

	void init()
	{
		int i,j;
		val[1] = 1;
		for(i=2;i<=m+2;i++) val[i] = val[i-1]*3;

		all=0;
		for(i=0;i<val[m+2];i++)
		{
		    e[i] = -1;
		    if(ok(i) == 1)
		    {
		        e[i] = all; r[all] = i;
		        for(j=1;j<=m+1;j++) p[all][j] = b[j];
		        all++;
		    }
		}

		for(i=0;i<all;i++)
		    for(j=1;j<=m+1;j++)
		    {
		        H[i][j] = r[i]/val[j]%3;
		    }
	}

	void solve()
	{
		int i,j,k,LL,UU,sta,u,y;

		long long ans = 0;

		u = 0;
		for(i=0;i<all;i++) dp[u][i] = 0; dp[u][0] = 1;

		for(i=1;i<=n;i++)
		    for(j=1;j<=m;j++)
		    {
		        y = u; u = 1-u;
		        if(j == 1)
		        {
		            for(k=all-1;k>=0;k--)
		            {
		                if(e[r[k]/3] >= 0) dp[y][k] = dp[y][e[r[k]/3]];
		                if(r[k]%3 != 0) dp[y][k] = 0;
		            }
		        }

		        for(k=0;k<all;k++) dp[u][k] = 0;

		        for(k=0;k<all;k++)
		        {
		            LL = H[k][j]; UU = H[k][j+1];

		            if(can[i][j] == 0)
		            {
		                if(LL == 0 && UU == 0)
		                {
		                    dp[u][k] = dp[y][k];
		                }
		                continue;
		            }

		            if(can[i][j] == 2)
		            {
		                if(LL == 0 && UU == 0)
		                    dp[u][k] += dp[y][k];
		            }

		            if(LL == 0 && UU == 0)
		            {
		                sta = r[k] + val[j] + val[j+1]*2;
		                dp[u][e[sta]] += dp[y][k];
		            }
		            else
		            if(LL == 0)
		            {
		                dp[u][k] += dp[y][k];

		                sta = r[k] - UU*val[j+1] + UU*val[j];
		                dp[u][e[sta]] += dp[y][k];
		            }
		            else
		            if(UU == 0)
		            {
		                dp[u][k] += dp[y][k];

		                sta = r[k] - LL*val[j] + LL*val[j+1];
		                dp[u][e[sta]] += dp[y][k];
		            }
		            else
		            if(LL == 1 && UU == 1)
		            {
		                if(p[k][j+1] > 0)
		                {
		                    sta = r[k]-val[j]-val[j+1]-val[p[k][j+1]];
		                    dp[u][e[sta]] += dp[y][k];
		                }
		            }
		            else
		            if(LL == 2 && UU == 2)
		            {
		                if(p[k][j] > 0)
		                {
		                    sta = r[k]-val[j]*2-val[j+1]*2+val[p[k][j]];
		                    dp[u][e[sta]] += dp[y][k];
		                }
		            }
		            else
		            if(LL == 2 && UU == 1)
		            {
		                sta = r[k] - 2*val[j]-val[j+1];
		                dp[u][e[sta]] += dp[y][k];
		            }
		            else
		            if(LL == 1 && UU == 2)
		            {
		                if(r[k]-val[j]-val[j+1]*2 == 0 && last[i][j] == last[n][m])
		                {
		                    ans += dp[y][k];
		                }
		            }
		        }
		    }
		cas++;
		printf("Case %d: %lld\n",cas,ans);
	}

	int main()
	{
		int i,T;
		scanf("%d",&T);

		m = 12;
		init(); r[all] = 1000000000;

		while(T-- > 0)
		{
		    input();
		    for(i=0;r[i]<val[m+2];i++); all = i;
		    solve();
		}
		return 0;
	}
```

---------

##### 八、pku_3133
```
	#include<stdio.h>

	#define N 60000+100 // 3^(m+1)

	int n,m,can[33][33];

	int dp[2][N],H[N][13],val[33];

	void solve()
	{
		int i,j,k,LL,UU,all,sta,u,y;

		all = val[m+2]; u = 0;
		for(i=0;i<all;i++) dp[u][i] = 1000000;
		dp[u][0] = 0;

		for(i=1;i<=n;i++)
		    for(j=1;j<=m;j++)
		    {
		        y = u; u = 1-u;
		        if(j == 1)
		        {
		            for(k=all-1;k>=0;k--)
		            {
		                dp[y][k] = dp[y][k/3];
		                if(k%3 != 0) dp[y][k] = 1000000;
		            }
		        }

		        for(k=0;k<all;k++) dp[u][k] = 1000000;

		        for(k=0;k<all;k++)
		        {
		            LL = H[k][j]; UU = H[k][j+1];

		            if(can[i][j] == 1)
		            {
		                if(LL == 0 && UU == 0)
		                {
		                    dp[u][k] = dp[y][k];
		                }
		                continue;
		            }

		            if(can[i][j] == 0)
		            {
		                if(LL == 0 && UU == 0)
		                {
		                    if(dp[u][k] > dp[y][k]) dp[u][k] = dp[y][k];

		                    sta = k+val[j]+val[j+1];
		                    if(dp[u][sta] > dp[y][k] + 2) dp[u][sta] = dp[y][k]+2;

		                    sta = k+(val[j]+val[j+1])*2;
		                    if(dp[u][sta] > dp[y][k] + 2) dp[u][sta] = dp[y][k]+2;
		                }
		                else
		                if(LL == 0)
		                {
		                    if(dp[u][k] > dp[y][k]+1) dp[u][k] = dp[y][k]+1;

		                    sta = k-val[j+1]*UU+val[j]*UU;
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;
		                }
		                else
		                if(UU == 0)
		                {
		                    if(dp[u][k] > dp[y][k]+1) dp[u][k] = dp[y][k]+1;

		                    sta = k-val[j]*LL+val[j+1]*LL;
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;
		                }
		                else
		                if(LL == 1 && UU == 1)
		                {
		                    sta = k-val[j]-val[j+1];
		                    if(dp[u][sta] > dp[y][k]) dp[u][sta] = dp[y][k];
		                }
		                else
		                if(LL == 2 && UU == 2)
		                {
		                    sta = k-(val[j]+val[j+1])*2;
		                    if(dp[u][sta] > dp[y][k]) dp[u][sta] = dp[y][k];
		                }
		            }
		            else
		            if(can[i][j] == 2)
		            {
		                if(LL == 0 && UU == 0)
		                {
		                    sta = k+val[j];
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;

		                    sta = k+val[j+1];
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;
		                }
		                else
		                if((LL == 1 && UU == 0) || (LL == 0 && UU == 1))
		                {
		                    sta = k-LL*val[j]-UU*val[j+1];
		                    if(dp[u][sta] > dp[y][k]) dp[u][sta] = dp[y][k];
		                }
		            }
		            else
		            if(can[i][j] == 3)
		            {
		                if(LL == 0 && UU == 0)
		                {
		                    sta = k+val[j]*2;
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;

		                    sta = k+val[j+1]*2;
		                    if(dp[u][sta] > dp[y][k] + 1) dp[u][sta] = dp[y][k]+1;
		                }
		                else
		                if((LL == 2 && UU == 0) || (LL == 0 && UU == 2))
		                {
		                    sta = k-LL*val[j]-UU*val[j+1];
		                    if(dp[u][sta] > dp[y][k]) dp[u][sta] = dp[y][k];
		                }
		            }
		        }
		    }
		if(dp[u][0] == 1000000) dp[u][0] = 0;
		printf("%d\n",dp[u][0]);
	}

	int main()
	{
		int i,j;

		val[1] = 1;
		for(i=2;i<=9+2;i++) val[i] = val[i-1]*3;
		for(i=0;i<val[9+2];i++) for(j=1;j<=9+1;j++) H[i][j] = i/val[j]%3;

		while(scanf("%d %d",&n,&m) != EOF)
		{
		    if(n == 0 && m == 0)break;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++) scanf("%d",&can[i][j]);

		    solve();
		}
		return 0;
	}
```

