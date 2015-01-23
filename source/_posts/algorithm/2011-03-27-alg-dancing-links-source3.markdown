---
layout: post
title: "dancing links code 6-7"
date: 2011-03-27 14:22:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 六、pku 3074
```
	#include<stdio.h>
	#include<algorithm>
	#include<math.h>
	#include<string.h>

	using namespace std;

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
		int i,j,k,l,n,m,T,boo,row,col,a[33][33],low,ok1[13][13],ok2[13][13],ok3[13][13],x1,y1,ii,jj;
		int id1[13][13],id2[13][13],id3[13][13],ok[13][13][13];
	 
		char ch[999];
		while(scanf("%s",ch) != EOF && strcmp(ch,"end") != 0)
		{
			k = 0;
			for(i=1;i<=9;i++)
				for(j=1;j<=9;j++)
				{
					if(ch[k] != '.') a[i][j] = ch[k] - '0'; else a[i][j] = -1; k++;
				}
	  
	  
			for(i=1;i<=9;i++)
				for(j=1;j<=9;j++)
				if(a[i][j] == -1)
					for(k=1;k<=9;k++)
					{
						boo = 1;
						for(l=1;l<=9;l++)if(a[l][j] == k)boo = 0;
						for(l=1;l<=9;l++)if(a[i][l] == k)boo = 0;
						x1 = (i-1)/3*3+1; y1 = (j-1)/3*3+1;
		 
						for(ii=x1;ii<x1+3;ii++)
							for(jj=y1;jj<y1+3;jj++)
							if(a[ii][jj] == k)boo = 0;
		 
						ok[i][j][k] = boo;
					}
	  
			row = 0; col = 0;
			for(j=1;j<=9;j++)
				for(k=1;k<=9;k++)
				{
					boo = 1;
					for(i=1;i<=9;i++)if(a[i][j] == k)boo = 0;
					if(boo == 1)
					{
						col++; id1[j][k] = col;
					}
					else
						id1[j][k] = -1;
				}
	  
			for(i=1;i<=9;i++)
				for(k=1;k<=9;k++)
				{
					boo = 1;
					for(j=1;j<=9;j++)if(a[i][j] == k)boo = 0;
					if(boo == 1)
					{
						col++; id2[i][k] = col;
					}
					else
						id2[i][k] = -1;
				}
	   
			for(i=1;i<=9;i++)
			{
				x1 = (i-1)/3*3+1; y1 = (i-1)%3*3+1;
				for(k=1;k<=9;k++)
				{
					boo = 1;
					for(ii=x1;ii<x1+3;ii++)
						for(jj=y1;jj<y1+3;jj++)
						if(a[ii][jj] == k)boo = 0;
					if(boo == 1)
					{
						col++; id3[i][k] = col;
					}
					else id3[i][k] = -1;
				}
			}
	  
			for(i=1;i<=9;i++)
				for(j=1;j<=9;j++)
				if(a[i][j] == -1)
					for(k=1;k<=9;k++)
					if(ok[i][j][k] == 1)
					{
						row++; x[row] = i-1; y[row] = j-1; z[row] = k;
						for(ii=1;ii<=col;ii++)mark[row][ii] = 0;
		 
						mark[row][id1[j][k]] = 1;
						mark[row][id2[i][k]] = 1;
						mark[row][id3[(i-1)/3*3+(j-1)/3+1][k]] = 1;
					}
	  
			int rr=0;
			for(i=1;i<=9;i++)
				for(j=1;j<=9;j++)
				if(a[i][j] == -1)
				{
					col++; for(k=1;k<=row;k++)mark[k][col] = 0;
					for(k=1;k<=9;k++)
					if(ok[i][j][k] == 1)
					{
						rr++; mark[rr][col] = 1;
					}
				}
	 
			ans = 0;
			k = solve(row, col, mark);
	   
			for(i=0;i<ans;i++)
			{
				ch[x[Ans[i]]*9+y[Ans[i]]] = z[Ans[i]] + 48;
			}
			printf("%s\n",ch);
	  
		}
		return 0;
	}
```

----------

##### 七、pku 3076
```
	#include<stdio.h>
	#include<algorithm>
	#include<math.h>
	#include<string.h>

	using namespace std;

	const int MAXN = 2005;
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
		// printf("ddd = %d  R0 = %d\n",depth,R[0]);
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
	int id1[33][33],id2[33][33],id3[33][33],ok[33][33][33];

	int main()
	{
		int i,j,k,l,n,m,T,boo,row,col,a[33][33],low,ok1[33][33],ok2[33][33],ok3[33][33],x1,y1,ii,jj;
	 
		char ch[999],cas=0;
		while(scanf("%s",ch) != EOF)
		{
			cas++; if(cas > 1)printf("\n");
			k = 16;
			for(i=1;i<16;i++)
			{
				scanf("%s",ch+k);
				k += 16;
			}//printf("safdsadfsdf\n");

			k = 0;
			for(i=1;i<=16;i++)
				for(j=1;j<=16;j++)
				{
					if(ch[k] != '-') a[i][j] = ch[k] - 'A'+1; else a[i][j] = -1; k++;
				}
	  
			for(i=1;i<=16;i++)
				for(j=1;j<=16;j++)
				if(a[i][j] == -1)
					for(k=1;k<=16;k++)
					{
						boo = 1;
						for(l=1;l<=16;l++)if(a[l][j] == k)boo = 0;
						for(l=1;l<=16;l++)if(a[i][l] == k)boo = 0;
						x1 = (i-1)/4*4+1; y1 = (j-1)/4*4+1;
		 
						for(ii=x1;ii<x1+4;ii++)
							for(jj=y1;jj<y1+4;jj++)
							if(a[ii][jj] == k)boo = 0;
		 
						ok[i][j][k] = boo;
					}
	  
			row = 0; col = 0;
			for(j=1;j<=16;j++)
				for(k=1;k<=16;k++)
				{
					boo = 1;
					for(i=1;i<=16;i++)if(a[i][j] == k)boo = 0;
					if(boo == 1)
					{
						col++; id1[j][k] = col;
					}
					else
						id1[j][k] = -1;
				}
	 
			for(i=1;i<=16;i++)
				for(k=1;k<=16;k++)
				{
					boo = 1;
					for(j=1;j<=16;j++)if(a[i][j] == k)boo = 0;
					if(boo == 1)
					{
						col++; id2[i][k] = col;
					}
					else
						id2[i][k] = -1;
				}
	   
			for(i=1;i<=16;i++)
			{
				x1 = (i-1)/4*4+1; y1 = (i-1)%4*4+1;
				for(k=1;k<=16;k++)
				{
					boo = 1;
					for(ii=x1;ii<x1+4;ii++)
						for(jj=y1;jj<y1+4;jj++)
						if(a[ii][jj] == k)boo = 0;
					if(boo == 1)
					{
						col++; id3[i][k] = col;
					}
					else id3[i][k] = -1;
				}
			}
	  
			for(i=1;i<=16;i++)
				for(j=1;j<=16;j++)
			if(a[i][j] == -1)
				for(k=1;k<=16;k++)
			if(ok[i][j][k] == 1)
			{
				row++; x[row] = i-1; y[row] = j-1; z[row] = k;
				//if(i == 1 && j == 7 && k == 4)printf("row ===== %d\n",row);
				for(ii=1;ii<=col;ii++)mark[row][ii] = 0;
		 
				mark[row][id1[j][k]] = 1;
				mark[row][id2[i][k]] = 1;
				mark[row][id3[(i-1)/4*4+(j-1)/4+1][k]] = 1;
			}
	  
			int rr=0;
			for(i=1;i<=16;i++)
				for(j=1;j<=16;j++)
				if(a[i][j] == -1)
				{
					col++; for(k=1;k<=row;k++)mark[k][col] = 0;
					for(k=1;k<=16;k++)
					if(ok[i][j][k] == 1)
					{
						rr++; mark[rr][col] = 1;
					}
				}
	  
	  
			//printf("%d %d\n",row,col);
			//freopen("out.txt","w",stdout);
	  
		/* for(i=1;i<=row;i++)
			{
				printf("%d %d %d   ",x[i],y[i],z[i]);
				for(j=1;j<=col;j++)
				printf("%d ",mark[i][j]);
				printf("\n");
			}*/
			//fclose(stdout);
	  
			ans = 0;
			k = solve(row, col, mark);
	 
		// printf("%d k = %d %d %d\n",ans,id1[7][4],id2[1][4],id3[3][4]);
	  
			for(i=0;i<ans;i++)
			{
			// printf("%d   %d %d %d\n",Ans[i],x[Ans[i]],y[Ans[i]],z[Ans[i]]);
				ch[x[Ans[i]]*16+y[Ans[i]]] = z[Ans[i]] + 'A'-1;
			}
			//printf("\n");*/
	  
			for(i=0;i<16*16;i++)
			{
				printf("%c",ch[i]);
				if(i!=0 && (i+1)%16 == 0)printf("\n");
			}
		}
		return 0;
	}
```

