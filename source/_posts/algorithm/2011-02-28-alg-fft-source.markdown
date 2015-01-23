---
layout: post
title: "快速傅里叶变换计算大整数乘法 code"
date: 2011-02-28 19:10:00 +0800
comments: false
categories:
- 2011
- 2011~02
- algorithm
- algorithm~base
tags:
---
```
	// a->A, b->B C->c  用三次快速傅立叶变换。

	#include <stdio.h>
	#include <string.h>
	#include <math.h>

	#define N 50009

	char s[N];
	int La,Lb,a[N+N],b[N+N];

	double pi = acos(-1.0);

	struct Num {
		double a,b;
	}
	A[N+N],B[N+N],C[N+N];

	Num operator+ (Num aa, Num bb) {
		Num ret;
		ret.a = aa.a+bb.a; ret.b = aa.b+bb.b;
		return ret;
	}
	Num operator- (Num aa, Num bb) {
		Num ret;
		ret.a = aa.a-bb.a; ret.b = aa.b-bb.b;
		return ret;
	}
	Num operator* (Num aa, Num bb) {
		Num ret;
		ret.a = aa.a*bb.a - aa.b*bb.b;
		ret.b = aa.a*bb.b + aa.b*bb.a;
		return ret;
	}

	Num W(int n, int k) {
		Num ret;
		ret.a = cos(-pi*k*2/n);
		ret.b = sin(-pi*k*2/n);
		return ret;
	}

	void DFT(int L, int R, Num from[], Num X[])
	{
		if(L+1 == R)
		{
			X[L] = from[L];
			return;
		}

		int i,j,k;
		Num T;

		for(i=L;i<R;i++) X[i] = from[i];
		j = L; k = (L+R)/2;
		for(i=L;i<R;i+=2)
		{
			from[j++] = X[i];	from[k++] = X[i+1];
		}

		DFT(L, (L+R)/2, from, X);
		DFT((L+R)/2, R, from, X);

		for(i=L;i<(L+R)/2;i++)
		{
			T = X[i];
			X[i] = T + W(R-L, i-L)*X[i+(R-L)/2];
			X[i+(R-L)/2] = T - W(R-L, i-L)*X[i+(R-L)/2];
		}
	}

	int main()
	{
		int i;
		while(scanf("%s",s) != EOF)
		{
			La = strlen(s);
			for(i=0;i<La;i++) a[i] = s[La-i-1]-48;
			scanf("%s",s);
			Lb = strlen(s);
			for(i=0;i<Lb;i++) b[i] = s[Lb-i-1]-48;

			i=1; while(i<La+Lb-1) i = i*2;
			for(;La<i;La++) a[La] = 0;
			for(;Lb<i;Lb++) b[Lb] = 0;

			for(i=0;i<La;i++) {
				A[i].a = a[i]; A[i].b = 0;
				B[i].a = b[i]; B[i].b = 0;
			}

			DFT(0, La, B, C);
			DFT(0, Lb, A, B);

			for(i=0;i<La;i++) B[i] = B[i]*C[i];
			DFT(0, La, B, C);

			C[La] = C[0]; b[0] = 0;
			for(i=1;i<=La;i++)
			b[i] = (int)(C[i].a/La + 0.5);

			for(i=La;i>0;i--)
			{
				b[i-1] += b[i]/10; b[i] %= 10;
			}

			i = 0; while(i < La && b[i] == 0) i++;
			for(;i<=La;i++) printf("%d",b[i]); printf("\n");
		}
		return 0;
	}
```

