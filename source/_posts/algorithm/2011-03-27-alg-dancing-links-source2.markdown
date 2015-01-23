---
layout: post
title: "dancing links code 4-5"
date: 2011-03-27 14:21:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 四、hdu 3663
```
	#include<stdio.h>
	#include<algorithm>
	#include<math.h>
	#include<string.h>

	using namespace std;

	int n,m,DD,a[66][66],s[66],f[66],id[66][6];

	const int MAXN = 1005;

	int L[MAXN*MAXN], R[MAXN*MAXN], U[MAXN*MAXN], D[MAXN*MAXN];
	int S[MAXN];
	int Col[MAXN*MAXN], Row[MAXN*MAXN],Ans[MAXN],ans,limit,up;


	void Remove(int c) {
		L[R[c]] = L[c];
		R[L[c]] = R[c];
		for (int i = D[c]; i != c; i = D[i])
		for (int j = R[i]; j != i; j = R[j]) {
		    U[D[j]] = U[j];
		    D[U[j]] = D[j];
		    -- S[Col[j]];
		}
	}
	void Resume(int c) {
		for (int i = U[c]; i != c; i = U[i])
		for (int j = L[i]; j != i; j = L[j]) {
		    U[D[j]] = j;
		    D[U[j]] = j;
		    ++ S[Col[j]];
		}
		L[R[c]] = c;
		R[L[c]] = c;
	}

	bool dfs(int depth) {
	//    printf("ddd = %d  R0 = %d\n",depth,R[0]);
		if(R[0] == 0) { if(depth > ans)ans = depth; return true; }
		int i, j, c, minnum = 1000000000;
		for (i = R[0]; i != 0; i = R[i]) {
		    if (S[i] < minnum) {
		        minnum = S[i];
		        c = i;
		    }
		}
		Remove(c);
		for (i = U[c]; i != c; i = U[i]) {
		    Ans[depth] = Row[i];
		    for (j = R[i]; j != i; j = R[j]) Remove(Col[j]);
		    if (dfs(depth + 1)) return true;
		    for (j = L[i]; j != i; j = L[j]) Resume(Col[j]);
		}
		Resume(c);
		return false;
	}
	int solve(int n, int m, int DL[][MAXN]) {
		for (int i = 0; i <= m; i ++) {
		    L[i] = i - 1;
		    R[i] = i + 1;
		    U[i] = D[i] = i;
		}
		L[0] = m;
		R[m] = 0;
		int cnt = m + 1;
		memset(S, 0, sizeof (S));
		for (int i = 1; i <= n; i ++) {
		    int head = cnt, tail = cnt;
		    for (int c = 1; c <= m; c ++) if (DL[i][c]) {
		        S[c] ++;
		        Row[cnt] = i;
		        Col[cnt] = c;
		        U[D[c]] = cnt;
		        D[cnt] = D[c];
		        U[cnt] = c;
		        D[c] = cnt;
		        L[cnt] = tail;
		        R[tail] = cnt;
		        R[cnt] = head;
		        L[head] = cnt;
		        tail = cnt;
		        cnt ++;
		    }
		}
		if (dfs(0)) return true;
		return false;
	}


	int mark[MAXN][MAXN],x[MAXN],y[MAXN],z[MAXN];

	int main()
	{
		int i,j,k,l,row,col,g;
		while(scanf("%d %d %d",&n,&m,&DD) != EOF)
		{
		    for(i=1;i<=n;i++)
		        for(j=1;j<=n;j++)
		        {
		            a[i][j] = 0;
		            if(i == j)a[i][j] = 1;
		        }
		    while(m--) {
		        scanf("%d %d",&j,&k);
		        a[j][k] = a[k][j] = 1;
		    }
		    for(i=1;i<=n;i++)scanf("%d %d",&s[i],&f[i]);
		   
		    col = 0;
		    for(i=1;i<=n;i++)
		        for(j=1;j<=DD;j++)
		            id[i][j] = ++col;
		   
		    row = 0;
		    for(i=1;i<=n;i++)
		    {
		        for(j=s[i];j<=f[i];j++)
		            for(k=j;k<=f[i];k++)
		            {
		                row++; x[row] = j; y[row] = k; z[row] = i;
		                for(l=1;l<=col;l++)mark[row][l] = 0;
		               
		                for(l=1;l<=n;l++)if(a[i][l] == 1)
		                {
		                    for(g=j;g<=k;g++) mark[row][id[l][g]] = 1;
		                }
		            }
		    }
		   
		    int rr=0;
		   
		    for(i=1;i<=n;i++)
		    {
		        col++;
		        for(j=1;j<=row;j++)mark[j][col] = 0;
		       
		        for(j=s[i];j<=f[i];j++)
		            for(k=j;k<=f[i];k++)
		            {
		                rr++;
		                mark[rr][col] = 1;
		            }
		    }
		   
		    int TT = row;
		    for(i=1;i<=n;i++)
		    {
		        row++;
		        for(j=1;j<=col;j++)mark[row][j] = 0;
		        mark[row][col-n+i] = 1;
		    }
		   
		    ans = 0;
		   
		    k = solve(row, col, mark);
		   
		    if(k == 0)
		        printf("No solution\n");
		    else
		    {
		        for(i=1;i<=n;i++)s[i] = f[i] = 0;
		        for(i=0;i<ans;i++)
		        if(Ans[i] <= TT)
		        {
		            s[z[Ans[i]]] = x[Ans[i]];
		            f[z[Ans[i]]] = y[Ans[i]];
		        }
		        for(i=1;i<=n;i++)printf("%d %d\n",s[i],f[i]);
		    }
		    printf("\n");
		}
		return 0;
	}
```

##### 五、hdu 2995
```
	#include<stdio.h>
	#include<algorithm>
	#include<math.h>
	#include<string.h>

	using namespace std;

	const int MAXN = 225;
	int L[MAXN*MAXN], R[MAXN*MAXN], U[MAXN*MAXN], D[MAXN*MAXN];
	int S[MAXN];
	int Col[MAXN*MAXN];
	int limit;

	void Remove(int x) {
		for (int i = D[x]; i != x; i = D[i]) {
			L[R[i]] = L[i];
			R[L[i]] = R[i];
		}
	}
	void Resume(int x) {
		for (int i = U[x]; i != x; i = U[i]) {
			L[R[i]] = R[L[i]] = i;
		}
	}
	int Hash() {
		int ans = 0;
		bool hash[MAXN] = {0};
		for (int c = R[0]; c != 0; c = R[c])
		if (! hash[c]) {
			hash[c] = true;
			ans ++;
			for (int i = D[c]; i != c; i = D[i])
				for (int j = R[i]; j != i; j = R[j])
					hash[Col[j]] = true;
		}
		return ans;
	}

	bool dfs(int depth) {
		if (depth + Hash() > limit) return false;
		if (R[0] == 0) return true;
		int i, j, c, minnum = 2000000000;
		for (i = R[0]; i != 0; i = R[i]) {
			if (S[i] < minnum) {
				minnum = S[i];
				c = i;
			}
		}
		for (i = U[c]; i != c; i = U[i]) {
			Remove(i);
			for (j = R[i]; j != i; j = R[j]) Remove(j);
			if (dfs(depth + 1)) {
				for (j = L[i]; j != i; j = L[j]) Resume(j);
				Resume(i);
				return true;
			}
			for (j = L[i]; j != i; j = L[j]) Resume(j);
			Resume(i);
		}
		return false;
	}

	int solve(int n, int m, int DL[][MAXN], int maxdepth) {
		if (maxdepth > n) maxdepth = n;
		for (int i = 0; i <= m; i ++) {
			L[i] = i - 1;
			R[i] = i + 1;
			U[i] = D[i] = i;
		}
		L[0] = m;
		R[m] = 0;
		int cnt = m + 1;
		memset(S, 0, sizeof (S));
		for (int i = 1; i <= n; i ++) {
			int head = cnt, tail = cnt;
			for (int c = 1; c <= m; c ++) if (DL[i][c]) {
				S[c] ++;
				Col[cnt] = c;
				U[D[c]] = cnt;
				D[cnt] = D[c];
				U[cnt] = c;
				D[c] = cnt;
				L[cnt] = tail;
				R[tail] = cnt;
				R[cnt] = head;
				L[head] = cnt;
				tail = cnt;
				cnt ++;
			}
		}
		int best = 0, worst = maxdepth;
		/*while (best <= worst) {
			limit = (worst + best) >> 1;
			if (dfs(0)) worst = limit - 1;
			else best = limit + 1;
		}*/
		limit = maxdepth;
		if(dfs(0))best = maxdepth;
		else
			best = maxdepth+1;
		return best;
	}

	int x[155],y[155];

	int dij(int i, int j)
	{
		int d1 = (x[i]-x[j])*(x[i]-x[j]);
		int d2 = (y[i]-y[j])*(y[i]-y[j]);
		return d1+d2;
	}

	int main()
	{
		int i,j,k,l,row,col,n,m,low,up,mid,mark[MAXN][MAXN],d[55][55],T,b[3000],top;
	 
		scanf("%d",&T);
		while(T--)
		{
			scanf("%d %d %d",&n,&row,&m);

			for(i=1;i<=n+row;i++)
				scanf("%d %d",&x[i],&y[i]);
	 
			low = 1; up = 1000000000;

			while(low < up)
			{
				for(i=1;i<=row;i++)
					for(j=1;j<=n;j++)mark[i][j] = 0;
	   
				mid = (low + up)>>1;
				for(i=1;i<=row;i++)
					for(j=1;j<=n;j++)if(dij(i+n,j) <= mid)mark[i][j] = 1;
		
				if(solve(row, n, mark, m) > m)low = mid+1; else up = mid;
			}
			mid = (low + up)>>1;
			printf("%.6lf\n",sqrt(1.0*mid));
		}
		return 0;
	}
```

