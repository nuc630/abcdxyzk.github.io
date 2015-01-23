---
layout: post
title: "插头 DP code5-6"
date: 2011-03-20 23:02:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 五、zju_3256
```
	#include<stdio.h>

	#define N 7000 // 3^(n+1)
	#define M 333  // all = 300+

	int n,m;
	int val[33],s[33],b[33],all,r[M],e[N];
	int p[M][13],kk,H[M][13];

	int A[M][M],B[M][M],tmp[M][M];

	void mul(int A[M][M], int B[M][M])
	{
		int i,j,k;
		long long w;
		for(i=0;i<all;i++)
		    for(j=0;j<all;j++)
		    {
		        w = 0;
		        for(k=0;k<all;k++) if(A[i][k] != 0 && B[k][j] != 0) w += (long long)A[i][k]*(long long)B[k][j];
		        if(w > 7777777) w = w-w/7777777*7777777;
		        tmp[i][j] = (int)(w);
		    }
		for(i=0;i<all;i++)
		    for(j=0;j<all;j++) A[i][j] = tmp[i][j];
	}

	int ok()
	{
		int i,l,c[33];
		l = 0;
		for(i=1;i<=n+1;i++)
		{
		    b[i] = -1;
		    if(s[i] == 1) c[++l] = i;
		    else
		    if(s[i] == 2) {
		        if(l == 0) return 0;
		        b[c[l]] = i; b[i] = c[l]; l--;
		    }
		}
		if(l != 0) return 0;
		return 1;
	}

	void init()
	{
		int i,j;
		val[1] = 1;
		for(i=2;i<=n+2;i++) val[i] = val[i-1]*3;

		for(i=0;i<=n+2;i++) s[i] = 0;

		all = 0;
		for(i=0;i<val[n+2];i++)
		{
		    e[i] = -1;
		    if(ok() == 1)
		    {
		        for(j=1;j<=n+1;j++) p[all][j] = b[j];
		        r[all] = i; e[i] = all;
		        all++;
		    }
		    s[1]++;
		    j = 1; while(s[j] > 2) { s[j] = 0; j++; s[j]++; }
		}
	}

	void abc()
	{
		int i,j,k,LL,UU,sta;
		for(i=0;i<all;i++) for(j=0;j<all;j++) A[i][j] = (i==j)?1:0;

		for(k=0;k<all;k++) for(i=1;i<=n+1;i++) H[k][i] = r[k]/val[i]%3;

		for(i=1;i<=n;i++)
		{
		    for(j=0;j<all;j++) for(k=0;k<all;k++) B[j][k] = 0;

		    for(k=0;k<all;k++)
		    {
		        LL = H[k][i]; UU = H[k][i+1];

		        if(LL == 0 && UU == 0)
		        {
		            sta = r[k] + val[i] + val[i+1]*2;
		            if(e[sta] != -1) B[e[sta]][k] += 1;
		        }
		        else
		        if(LL == 0)
		        {
		            sta = r[k];
		            if(e[sta] != -1) B[e[sta]][k] += 1;

		            sta = r[k] + UU*(val[i]-val[i+1]);
		            if(e[sta] != -1) B[e[sta]][k] += 1;
		        }
		        else
		        if(UU == 0)
		        {
		            sta = r[k];
		            if(e[sta] != -1) B[e[sta]][k] += 1;

		            sta = r[k] + LL*(val[i+1]-val[i]);
		            if(e[sta] != -1) B[e[sta]][k] += 1;
		        }
		        else
		        if(LL == 2 && UU == 1)
		        {
		            sta = r[k] - val[i]*2 - val[i+1];
		            if(e[sta] != -1) B[e[sta]][k] += 1;
		        }
		        else
		        if(LL == 1 && UU == 1)
		        {
		            if(p[k][i+1] != -1)
		            {
		                sta = r[k]-val[i]-val[i+1]-val[p[k][i+1]];
		                if(e[sta] != -1) B[e[sta]][k] += 1;
		            }
		        }
		        else
		        if(LL == 2 && UU == 2)
		        {
		            if(p[k][i] != -1)
		            {
		                sta = r[k]-val[i]*2-val[i+1]*2+val[p[k][i]];
		                if(e[sta] != -1) B[e[sta]][k] += 1;
		            }
		        }
		    }

		    mul(B, A);
		    for(j=0;j<all;j++) for(k=0;k<all;k++) A[j][k] = B[j][k];
		}
		// change
		for(i=0;i<all;i++) for(j=0;j<all;j++)
		{
		    B[i][j] = 0;
		    if(e[r[i]/3] != -1)
		        B[i][j] = A[e[r[i]/3]][j];
		}

		int q[M],al=0;
		for(i=0;i<all;i++) if(r[i]%3 == 0) q[al++] = r[i];

		for(i=0;i<al;i++) for(j=0;j<al;j++)
		{
		    A[i][j] = B[e[q[i]]][e[q[j]]];
		}
		all = al;
		for(kk=0;;kk++) if(q[kk] == 3+val[n+1]*2) break;

	}

	void solve()
	{
		int i,j;
		for(i=0;i<all;i++) for(j=0;j<all;j++) B[i][j]=(i==j)?1:0;
		while(m > 0)
		{
		    if(m%2 == 1) mul(B, A);
		    mul(A, A);
		    m /= 2;
		}

		if(B[kk][0] == 0)
		    printf("Impossible\n");
		else
		    printf("%d\n",B[kk][0]);
	}

	int main()
	{
		while(scanf("%d %d",&n,&m) != EOF)
		{
		    init();
		    abc();
		    solve();
		}
		return 0;
	}
```

---------

##### 六、hdu_1693
```
	#include<stdio.h>
	#include<string.h>

	#define N 5000 // 2^(m+1)

	long long dp[2][N];
	int H[N][15];

	class DP {

	public:
		int cas;
		DP() {
		    cas = 0;
		}

		int n,m,can[33][33];
		int val[33],LL,UU,sta,next;

		void input()
		{
		    int i,j;
		    scanf("%d %d",&n,&m);
		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++) scanf("%d", &can[i][j]);
		}

		void abc()
		{
		    int i,j,k,u,y;

		    input();

		    u = 0;
		    for(i=0;i<=(1<<(m+1));i++) dp[u][i] = 0;
		    dp[u][0] = 1;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++)
		        {
		            y = u; u = 1-u;
		            if(j == 1)
		            {
		                for(k=(1<<(m+1))-1;k>=0;k--)
		                {
		                    dp[y][k] = dp[y][k/2];
		                    if(k%2==1) dp[y][k] = 0;
		                }
		            }

		            for(k=0;k<(1<<(m+1));k++) dp[u][k] = 0;

		            for(k=0;k<(1<<(m+1));k++)
		            if(dp[y][k] > 0)
		            {
		                LL = H[k][j];
		                UU = H[k][j+1];

		                if(can[i][j] == 0)               // sta = 0
		                {
		                    if(LL == 0 && UU == 0)
		                    {
		                        dp[u][k] += dp[y][k];
		                    }
		                    continue;
		                }
		                                                 // sta = 1;
		                if(UU == 0 && LL == 0)
		                {
		                    sta = k+(1<<(j-1))+(1<<j);
		                    dp[u][sta] += dp[y][k];
		                }
		                else
		                if(LL == 0)
		                {
		                    sta = k;
		                    dp[u][sta] += dp[y][k];

		                    sta = k+((1<<(j-1)) - (1<<j));
		                    dp[u][sta] += dp[y][k];
		                }
		                else
		                if(UU == 0)
		                {
		                    sta = k;
		                    dp[u][sta] += dp[y][k];

		                    sta = k+(-(1<<(j-1))+(1<<j));
		                    dp[u][sta] += dp[y][k];
		                }
		                else
		                if(LL == 1 && UU == 1)
		                {
		                    sta = k-(1<<(j-1))-(1<<j);
		                    dp[u][sta] += dp[y][k];
		                }
		            }
		        }
		        cas++;
		        printf("Case %d: There are %lld ways to eat the trees.\n",cas,dp[u][0]);
		}

		void solve()
		{
		    int k,j,T;

		    for(k=0;k<(1<<(11+1));k++)
		        for(j=1;j<=11+1;j++)
		            H[k][j] = k/(1<<(j-1))%2;

		    scanf("%d",&T);
		    while(T-- > 0)
		        abc();
		}
	};

	int main()
	{
		    DP dp;
		    dp.solve();
	}
```

