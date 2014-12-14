---
layout: post
title: "dancing links"
date: 2011-03-24 23:12:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
Knuth Dancing_Links 中文版 http://www.docin.com/p-31928825.html

http://acm.fzu.edu.cn/problem.php?pid=1686

http://acm.zju.edu.cn/onlinejudge/showProblem.do?problemCode=3209

http://acm.hdu.edu.cn/showproblem.php?pid=3529

http://acm.hdu.edu.cn/showproblem.php?pid=3663

http://acm.hdu.edu.cn/showproblem.php?pid=2295

http://poj.org/problem?id=3074

http://poj.org/problem?id=3076

##### // fzu 1686
```
	#include<stdio.h>
	#include<algorithm>

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
		int i, j, c, minnum = INT_MAX;
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
		while (best <= worst) {
			limit = (worst + best) >> 1;
			if (dfs(0)) worst = limit - 1;
			else best = limit + 1;
		}
		return best;
	}

	int main()
	{
		int i,j,k,l,row,col,n,m,n1,m1,mark[MAXN][MAXN],a[33][33],id[33][33];
	
		while(scanf("%d %d",&n,&m) != EOF)
		{
			col = 0;
			for(i=1;i<=n;i++)
				for(j=1;j<=m;j++)
				{
					scanf("%d",&a[i][j]);
					id[i][j] = -1;
					if(a[i][j] == 1) { col++; id[i][j] = col; }
				}
			scanf("%d %d",&n1,&m1);

			row = 0;
			for(i=1;i<=n-n1+1;i++)
				for(j=1;j<=m-m1+1;j++)
				{
					row++;
					for(k=1;k<=col;k++)mark[row][k] = 0;
				
					for(k=i;k<i+n1;k++)
						for(l=j;l<j+m1;l++)
						if(id[k][l] > 0)
							mark[row][id[k][l]] = 1;
				}
			
			printf("%d\n",solve(row, col, mark, row));
		}
		return 0;
	}
```

##### // hdu 2295
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

