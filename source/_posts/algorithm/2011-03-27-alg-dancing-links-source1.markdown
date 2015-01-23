---
layout: post
title: "dancing links code 1-3"
date: 2011-03-27 14:20:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 一、fzu 1686
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

---------- 

##### 二、zju 3209
```
	#include<stdio.h>
	#include<algorithm>
	#include<math.h>
	#include<string.h>

	using namespace std;

	const int MAXN = 1005;
	int L[MAXN*MAXN], R[MAXN*MAXN], U[MAXN*MAXN], D[MAXN*MAXN];
	int S[MAXN];
	int Col[MAXN*MAXN], Row[MAXN*MAXN],ans,limit,up;


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
		if (depth >= ans) return true;
	 
		if(R[0] == 0) { if(depth < ans)ans = depth;  return true; }
	 
		int i, j, c, minnum = 2000000000, flag = 0;
		for (i = R[0]; i != 0; i = R[i]) {
			if (S[i] < minnum) {
				minnum = S[i];
				c = i;
			}
		}
		Remove(c);
		for (i = U[c]; i != c; i = U[i]) {
			//如果需要的话，在这里记录一组解(Ans[depth] = Row[i])
			for (j = R[i]; j != i; j = R[j]) Remove(Col[j]);
			if (dfs(depth + 1)) flag = 1; //return true;
			for (j = L[i]; j != i; j = L[j]) Resume(Col[j]);
		}
		Resume(c);
		return flag;//false;
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

	int mark[MAXN][MAXN];

	int main()
	{
		int i,j,k,l,n,m,T,row,col,x1,x2,y1,y2,id[33][33],low;
		scanf("%d",&T);
		while(T--)
		{
			scanf("%d %d %d",&n,&m,&row);
			col = 0;
			for(i=1;i<=n;i++)
				for(j=1;j<=m;j++)
				{
					col++; id[i][j] = col;
				}
	 
			for(i=1;i<=row;i++)
				for(j=1;j<=col;j++)mark[i][j] = 0;

			for(i=1;i<=row;i++)
			{
				scanf("%d %d %d %d",&x1,&y1,&x2,&y2);
				x1++; y1++;
				for(k=x1;k<=x2;k++)
					for(l=y1;l<=y2;l++)
					mark[i][id[k][l]] = 1;
			}

			ans = 1000000000;
			if(!solve(row, col, mark))ans = -1;

			printf("%d\n",ans);
		}
		return 0;
	}
```
 
----------

##### 三、hdu 3529
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
			while (best <= worst) {
			limit = (worst + best) >> 1;
			if (dfs(0)) worst = limit - 1;
			else best = limit + 1;
		}
		return best;
	}

	int n,m,M[MAXN][MAXN];

	int main()
	{
		int i,j,k,l,row,col,idr[33][33],idc[33][33];
	   
		char ch[33][33];
		while(scanf("%d %d",&n,&m) != EOF)
		{
			for(i=1;i<=n;i++) scanf("%s",ch[i]+1);
		   
			row = col = 0;
		   
			for(i=1;i<=n;i++)
				for(j=1;j<=m;j++)
				if(ch[i][j] == '.') idr[i][j] = ++row;
				else
				if(ch[i][j] == '#') idc[i][j] = ++col;
			   
			for(i=0;i<=row;i++) for(j=0;j<=col;j++) M[i][j] = 0;
		   
			for(i=1;i<=n;i++)
				for(j=1;j<=m;j++)
				if(ch[i][j] == '.')
				{
					k = i-1; l = j; while(k > 0 && ch[k][l] == '.') k--;
					if(k > 0 && ch[k][l] == '#') M[idr[i][j]][idc[k][l]] = 1;
				   
					k = i+1; l = j; while(k <= n && ch[k][l] == '.') k++;
					if(k <= n && ch[k][l] == '#') M[idr[i][j]][idc[k][l]] = 1;
				   
					k = i; l = j-1; while(l > 0 && ch[k][l] == '.') l--;
					if(l > 0 && ch[k][l] == '#') M[idr[i][j]][idc[k][l]] = 1;
				   
					k = i; l = j+1; while(l <= m && ch[k][l] == '.') l++;
					if(l <= m && ch[k][l] == '#') M[idr[i][j]][idc[k][l]] = 1;
				}
			   
			int ans = solve(row, col, M, col);
			printf("%d\n",ans);
		}
		return 0;  
	}
```

