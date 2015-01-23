---
layout: post
title: "插头 DP code3-4"
date: 2011-03-20 23:01:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 三、pku_1739
```
	#include<stdio.h>

	class DP {

	public:
		int n,m,can[33][33];
		int dp[200000],pre[200000],val[33],LL,UU,sta,next;
		int a[33],b[33],d[33],c[33];
		char p[200000][12];

		void input()
		{
		    int i,j;
		    char ch[13];

		    for(i=1;i<=n;i++)
		    {
		        scanf("%s",ch);
		        for(j=1;j<=m;j++) can[i][j] = ch[j-1]=='.'?1:0;
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
		    for(i=2;i<=m+2;i++) val[i] = val[i-1]*3;

		    for(i=0;i<=m+2;i++) a[i] = 0;
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
		    int i,j,k;

		    input();
		    init();

		    for(i=0;i<=val[m+2];i++) dp[i] = 0;

		    dp[0] = 1;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++)
		        {
		            if(j == 1)
		            {
		                for(k=val[m+2]-1;k>=0;k--)
		                {
		                    dp[k] = dp[k/3];
		                    if(k%3 != 0) dp[k] = 0;
		                }
		            }

		            for(k=0;k<val[m+2];k++)
		            {
		                pre[k] = dp[k];
		                dp[k] = 0;
		            }

		            for(k=0;k<val[m+2];k++)
		            if(pre[k] > 0)
		            {
		                LL = k/val[j]%3;
		                UU = k/val[j+1]%3;

		                if(can[i][j] == 0)
		                {
		                    if(LL == 0 && UU == 0)
		                    {
		                        dp[k] += pre[k];
		                    }
		                    continue;
		                }


		                if(UU == 0 && LL == 0)
		                {
		                    sta = k+val[j]+val[j+1]+val[j+1];

		                    dp[sta] += pre[k];
		                }
		                else
		                if(LL == 0)
		                {
		                    sta = k;
		                    dp[sta] += pre[k];

		                    sta = k+k/val[j+1]%3*(val[j]-val[j+1]);
		                    dp[sta] += pre[k];
		                }
		                else
		                if(UU == 0)
		                {
		                    sta = k;
		                    dp[sta] += pre[k];

		                    sta = k+k/val[j]%3*(-val[j]+val[j+1]);
		                    dp[sta] += pre[k];
		                }
		                else
		                if(LL == 2 && UU == 1)
		                {
		                    sta = k-val[j]-val[j]-val[j+1];
		                    dp[sta] += pre[k];
		                }
		                else
		                if(LL == 1 && UU == 1)
		                {
		                    if(p[k][j+1] > 0 && p[k][j+1] <= m+1)
		                    {
		                        sta = k-val[j]-val[j+1]-val[p[k][j+1]];
		                        dp[sta] += pre[k];
		                    }
		                }
		                else
		                if(LL == 2 && UU == 2)
		                {
		                    if(p[k][j] > 0)
		                    {
		                        sta = k-val[j]-val[j]-val[j+1]-val[j+1]+val[p[k][j]];
		                        dp[sta] += pre[k];
		                    }
		                }
		            }
		        }
		    printf("%d\n",dp[1+val[m]*2]);
		}

		void solve()
		{
		    while(true)
		    {
		        scanf("%d %d",&n,&m);
		        if(n == 0 && m == 0) break;
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

---------

##### 四、hdu_3377
```
	#include<stdio.h>

	int n,m,can[33][33];
	int dp[200000],pre[200000],val[33],LL,UU,sta,next;
	int a[33],b[33],d[33],c[33],cas=0;
	char p[200000][12];


	class DP {

	public:
		void input()
		{
		    int i,j;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++) scanf("%d",&can[i][j]);
		}

		int ok()
		{
		    int i,l;
		    l = 0;
		    for(i=1+m;i>=1;i--)
		    {
		        b[i] = d[i] = -1;
		        if(a[i] == 2) c[++l] = i;
		        else
		        if(a[i] == 1)
		        {
		            if(l == 0) return 0;
		            d[c[l]] = i; b[i] = c[l];
		            l--;
		        }
		    }
		    if(l != 1) return 0;
		    return 1;
		}

		void init()
		{
		    int i,j,k;

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
		    int i,j,k,ans=-1000000000;

		    val[1] = 1;
		    for(i=2;i<=12;i++) val[i] = val[i-1]*3;

		    input();
		    init();

		    for(i=0;i<=val[m+2];i++) dp[i] = -1000000000;

		    //dp[0] = 0;

		    for(i=1;i<=n;i++)
		        for(j=1;j<=m;j++)
		        {
		            if(j == 1)
		            {
		                for(k=val[m+2]-1;k>=0;k--)
		                {
		                    dp[k] = dp[k/3];
		                    if(k%3 != 0) dp[k] = -1000000000;
		                }
		            }

		            for(k=0;k<val[m+2];k++)
		            {
		                pre[k] = dp[k];
		                dp[k] = -1000000000;
		            }

		            if(i == 1 && j == 1)
		            {
		                dp[2] = dp[6] = can[1][1];
		                continue;
		            }

		            if(i == n && j == m)
		            {
		                k = val[m]*2;
		                if(ans < pre[k]+can[n][m])
		                        ans = pre[k]+can[n][m];

		                k = val[m+1]*2;
		                if(ans < pre[k]+can[n][m])
		                        ans = pre[k]+can[n][m];
		                continue;
		            }

		            for(k=0;k<val[m+2];k++)
		            if(pre[k] > -1000000000)
		            {
		                LL = k/val[j]%3;
		                UU = k/val[j+1]%3;

		                if(UU == 0 && LL == 0)
		                {
		                    sta = k+val[j]+val[j+1]+val[j+1];

		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];

		                    if(dp[k] < pre[k]) dp[k] = pre[k];
		                }
		                else
		                if(LL == 0)
		                {
		                    sta = k;
		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];

		                    sta = k+k/val[j+1]%3*(val[j]-val[j+1]);
		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];
		                }
		                else
		                if(UU == 0)
		                {
		                    sta = k;
		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];

		                    sta = k+k/val[j]%3*(-val[j]+val[j+1]);
		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];
		                }
		                else
		                if(LL == 2 && UU == 1)
		                {
		                    sta = k-val[j]-val[j]-val[j+1];
		                    if(pre[k] + can[i][j] > dp[sta])
		                        dp[sta] = pre[k] + can[i][j];
		                }
		                else
		                if(LL == 1 && UU == 1)
		                {
		                    if(p[k][j+1] > 0 && p[k][j+1] <= m+1)
		                    {
		                        sta = k-val[j]-val[j+1]-val[p[k][j+1]];
		                        if(pre[k] + can[i][j] > dp[sta])
		                          dp[sta] = pre[k] + can[i][j];
		                    }
		                }
		                else
		                if(LL == 2 && UU == 2)
		                {
		                    if(p[k][j] > 0)
		                    {
		                        sta = k-val[j]-val[j]-val[j+1]-val[j+1]+val[p[k][j]];
		                        if(pre[k] + can[i][j] > dp[sta])
		                            dp[sta] = pre[k] + can[i][j];
		                    }
		                }
		            }
		        }
		    if(n == 1 && m == 1) ans = can[1][1];

		    printf("Case %d: %d\n",++cas,ans);
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
