---
layout: post
title: "划分树--查询区间k-th number code"
date: 2011-03-23 23:14:00 +0800
comments: false
categories:
- 2011
- 2011~03
- algorithm
- algorithm~base
tags:
---
##### 一、pku_2104
```
	#include<stdio.h>
	#include<algorithm>

	#define N 100000+100
	#define M 21  // log(N)

	using namespace std;

	struct Node {
		int val,id;
	} a[N];

	int n,m,tr[M][N];

	int cmp(Node aa, Node bb) {
		if(aa.val < bb.val || (aa.val == bb.val && aa.id < bb.id)) return 1;
		return 0;
	}

	void build_tree(int dep, int s, int t)
	{
		if(s >= t) return;
		
		int i,j,k,mid = (s+t)/2;
		j = s; k = mid+1;
		
		for(i=s;i<=t;i++)
		{
		    if(tr[dep][i] <= mid)
		        tr[dep+1][j++] = tr[dep][i];
		    else
		        tr[dep+1][k++] = tr[dep][i];

		    tr[dep][i] = j-1;
		}
		
		build_tree(dep+1, s, mid);
		build_tree(dep+1, mid+1, t);
	}

	int find_tree(int dep, int s, int t, int i, int j, int k)
	{
		if(s == t) return s;
		int ci, mid = (s+t)/2;
		
		int v = tr[dep][j]-(s-1);
		if(i > s) v = tr[dep][j] - tr[dep][i-1];
		
		if(v >= k)
		{
		    ci = s; if(i > s) ci = tr[dep][i-1]+1;
		    return find_tree(dep+1, s, mid, ci, tr[dep][j], k);
		}
		else
		{
		    ci = mid+1; if(i > s) ci = mid+1 + (i-1)-tr[dep][i-1];
		    return find_tree(dep+1, mid+1, t, ci, mid+j-tr[dep][j], k-v);
		}
		return 0;
	}

	int main()
	{
		int i,j,k,ans;
		while(scanf("%d %d",&n,&m) != EOF)
		{
		    for(i=1;i<=n;i++) {
		        scanf("%d",&a[i].val); a[i].id = i;
		    }
		    
		    sort(a+1, a+1+n, cmp);
		    for(i=1;i<=n;i++) tr[0][a[i].id] = i;

		    build_tree(0, 1, n);
		    
		    while(m--)
		    {
		        scanf("%d %d %d",&i,&j,&k);
		        ans = find_tree(0, 1, n, i, j, k);
		        printf("%d\n",a[ans].val);
		    }
		}
		return 0;
	}
```

------------

##### 二、hdu_2665
```
	#include<stdio.h>
	#include<algorithm>

	#define N 100000+100
	#define M 21  // log(N)

	using namespace std;

	struct Node {
		int val,id;
	} a[N];

	int n,m,tr[M][N];

	int cmp(Node aa, Node bb) {
		if(aa.val < bb.val || (aa.val == bb.val && aa.id < bb.id)) return 1;
		return 0;
	}

	void build_tree(int dep, int s, int t)
	{
		if(s >= t) return;
	   
		int i,j,k,mid = (s+t)/2;
		j = s; k = mid+1;
	   
		for(i=s;i<=t;i++)
		{
		    if(tr[dep][i] <= mid)
		        tr[dep+1][j++] = tr[dep][i];
		    else
		        tr[dep+1][k++] = tr[dep][i];

		    tr[dep][i] = j-1;
		}
	   
		build_tree(dep+1, s, mid);
		build_tree(dep+1, mid+1, t);
	}

	int find_tree(int dep, int s, int t, int i, int j, int k)
	{
		if(s == t) return s;
		int ci, mid = (s+t)/2;
	   
		int v = tr[dep][j]-(s-1);
		if(i > s) v = tr[dep][j] - tr[dep][i-1];
	   
		if(v >= k)
		{
		    ci = s; if(i > s) ci = tr[dep][i-1]+1;
		    return find_tree(dep+1, s, mid, ci, tr[dep][j], k);
		}
		else
		{
		    ci = mid+1; if(i > s) ci = mid+1 + (i-1)-tr[dep][i-1];
		    return find_tree(dep+1, mid+1, t, ci, mid+j-tr[dep][j], k-v);
		}
		return 0;
	}

	int main()
	{
		int i,j,k,ans,T;
		scanf("%d",&T);
		while(T--)
		{
		    scanf("%d %d",&n,&m);
		    for(i=1;i<=n;i++) {
		        scanf("%d",&a[i].val); a[i].id = i;
		    }
		   
		    sort(a+1, a+1+n, cmp);
		    for(i=1;i<=n;i++) tr[0][a[i].id] = i;

		    build_tree(0, 1, n);
		   
		    while(m--)
		    {
		        scanf("%d %d %d",&i,&j,&k);
		        ans = find_tree(0, 1, n, i, j, k);
		        printf("%d\n",a[ans].val);
		    }
		}
		return 0;
	}
```

---------

##### 三、hdu_3727
```
	#include<stdio.h>
	#include<algorithm>

	#define N 100000+100
	#define M 21  // log(N)

	typedef long long LL;

	using namespace std;

	struct Input {
		int sta,s,t,k;
	} q[N+N+N];

	struct Node {
		int val,id;
	} a[N];

	int n,m,tr[M][N],C[N],b[N];

	int cmp(Node aa, Node bb) {
		if(aa.val < bb.val || (aa.val == bb.val && aa.id < bb.id)) return 1;
		return 0;
	}

	int lowbit(int x) {
		return x&(-x);
	}

	void change(int x, int y) {
		while(x <= n) {
		    C[x] += y; x += lowbit(x);
		}
	}

	int cal(int x) {
		int t=0;
		while(x > 0) {
		    t += C[x]; x -= lowbit(x);
		}
		return t;
	}

	void build_tree(int dep, int s, int t)
	{
		if(s >= t) return;
	   
		int i,j,k,mid = (s+t)/2;
		j = s; k = mid+1;
	   
		for(i=s;i<=t;i++)
		{
		    if(tr[dep][i] <= mid)
		        tr[dep+1][j++] = tr[dep][i];
		    else
		        tr[dep+1][k++] = tr[dep][i];

		    tr[dep][i] = j-1;
		}
	   
		build_tree(dep+1, s, mid);
		build_tree(dep+1, mid+1, t);
	}

	int find_tree(int dep, int s, int t, int i, int j, int k)
	{
		if(s == t) return s;
		int ci, mid = (s+t)/2;
	   
		int v = tr[dep][j]-(s-1);
		if(i > s) v = tr[dep][j] - tr[dep][i-1];
	   
		if(v >= k)
		{
		    ci = s; if(i > s) ci = tr[dep][i-1]+1;
		    return find_tree(dep+1, s, mid, ci, tr[dep][j], k);
		}
		else
		{
		    ci = mid+1; if(i > s) ci = mid+1 + (i-1)-tr[dep][i-1];
		    return find_tree(dep+1, mid+1, t, ci, mid+j-tr[dep][j], k-v);
		}
		return 0;
	}

	int main()
	{
		int i,k,T,low,up,mid,cas=0;
		LL ans[5];
		char ch[33];
	   
		while(scanf("%d",&T) != EOF)
		{
		   
		    n = 0; m = 0;
		    for(i=1;i<=T;i++)
		    {
		        scanf("%s", ch);
		        if(ch[0] == 'I')
		        {
		            q[i].sta = 0;
		            n++; scanf("%d", &a[n].val); a[n].id = n;
		        }
		        else
		        {
		            q[i].sta = ch[6] - 48;
		            if(ch[6] == '1') scanf("%d %d %d",&q[i].s,&q[i].t,&q[i].k);
		            else
		                scanf("%d",&q[i].k);
		        }
		    }
		   
		    sort(a+1, a+1+n, cmp);
		    for(i=1;i<=n;i++)
		    {
		        b[a[i].id] = tr[0][a[i].id] = i;
		        C[i] = 0;
		    }
		    C[0] = 0;

		    build_tree(0, 1, n);
		   
		    ans[1] = ans[2] = ans[3] = 0;
		   
		    m = 0;
		   
		    for(i=1;i<=T;i++)
		    {
		        if(q[i].sta == 0)
		        {
		            m++;
		            change(b[m], 1);
		        }
		        else
		        if(q[i].sta == 1)
		        {
		            k = find_tree(0, 1, n, q[i].s, q[i].t, q[i].k);
		            ans[1] += a[k].val;
		        }
		        else
		        if(q[i].sta == 2)
		        {
		            low = 1; up = n;
		            while(low < up) {
		                mid = (low + up)/2;
		                if(a[mid].val < q[i].k) low = mid+1; else up = mid;
		            }
		            mid = (low + up)/2;
		            ans[2] += cal(mid);
		        }
		        else
		        if(q[i].sta == 3)
		        {
		            low = 1; up = n;
		            while(low < up) {
		                mid = (low + up)/2;
		                if(cal(mid) < q[i].k) low = mid+1; else up = mid;
		            }
		            mid = (low + up)/2;
		            ans[3] += a[mid].val;
		        }
		    }
		    cas++;
		    printf("Case %d:\n%lld\n%lld\n%lld\n",cas,ans[1],ans[2],ans[3]);
		}
		return 0;
	}
```

------------

##### 四、hdu_3473
```
	#include<stdio.h>
	#include<algorithm>

	#define N 100000+100
	#define M 21  // log(N)

	typedef long long LL;

	using namespace std;

	struct Node {
		int val,id;
	} a[N];

	int n,m,pos,tr[M][N];
	LL less,more, sum[M][N];

	int cmp(Node aa, Node bb) {
		if(aa.val < bb.val || (aa.val == bb.val && aa.id < bb.id)) return 1;
		return 0;
	}

	void build_tree(int dep, int s, int t)
	{
		if(s >= t) return;
	   
		int i,j,k, mid = (s+t)/2;
		LL s1,s2;
	   
		j = s; k = mid+1;
		s1 = s2 = 0;
	   
		for(i=s;i<=t;i++)
		{
		    if(tr[dep][i] <= mid)
		    {
		        s1 += a[tr[dep][i]].val;
		        sum[dep][j] = s1;
		        tr[dep+1][j++] = tr[dep][i];
		    }
		    else
		    {
		        s2 += a[tr[dep][i]].val;
		        sum[dep][k] = s2;
		        tr[dep+1][k++] = tr[dep][i];
		    }

		    tr[dep][i] = j-1;
		}
	   
		build_tree(dep+1, s, mid);
		build_tree(dep+1, mid+1, t);
	}

	void find_tree(int dep, int s, int t, int i, int j, int k)
	{
		if(s == t) { pos = s; return ; }
		int ci,cj,  mid = (s+t)/2;
		LL s1,s2;
	   
		int v = tr[dep][j]-(s-1);
		if(i > s) v = tr[dep][j] - tr[dep][i-1];
	   
		if(v >= k)
		{
		    ci = s; if(i > s) ci = tr[dep][i-1]+1;
		    find_tree(dep+1, s, mid, ci, tr[dep][j], k);
		   
		   
		    if(i == s) ci = 0; else ci = (i-1)-tr[dep][i-1];
		    if(ci == 0) s1 = 0; else s1 = sum[dep][mid+ci];
		   
		    cj = j-tr[dep][j];
		    if(cj == 0) s2 = 0; else s2 = sum[dep][mid+cj];
		   
		    more += (s2-s1);
		}
		else
		{
		    ci = mid+1; if(i > s) ci = mid+1 + (i-1)-tr[dep][i-1];
		    find_tree(dep+1, mid+1, t, ci, mid+j-tr[dep][j], k-v);
		   
		   
		    if(i > s) ci = tr[dep][i-1]; else ci = s-1;
		    if(ci < s) s1 = 0; else s1 = sum[dep][ci];
		   
		    cj = tr[dep][j]; 
		    if(cj < s) s2 = 0; else s2 = sum[dep][cj];
		   
		    less += (s2-s1);
		}
	}

	int main()
	{
		int i,j,k,T,cas=0;
		scanf("%d",&T);
		while(T--)
		{
		    scanf("%d",&n);
		    for(i=1;i<=n;i++) {
		        scanf("%d",&a[i].val); a[i].id = i;
		    }
		   
		    sort(a+1, a+1+n, cmp);
		   
		    sum[0][0] = 0;
		    for(i=1;i<=n;i++)
		    {
		        tr[0][a[i].id] = i;
		        sum[0][i] = sum[0][i-1] + a[i].val;
		    }

		    build_tree(0, 1, n);
		   
		    cas++;
		    printf("Case #%d:\n", cas);
		   
		    scanf("%d",&m);
		    while(m--)
		    {
		        scanf("%d %d",&i,&j);
		        i++; j++; k = (j-i+2)/2;
		        less = 0; more = 0;
		        find_tree(0, 1, n, i, j, k);
		       
		        //printf("%d %lld %lld\n",a[pos].val,less,more);
		       
		        printf("%lld\n", (LL)(k-1)*(LL)a[pos].val-less + more-(LL)(j-i+1-k)*(LL)a[pos].val);
		    }
		    printf("\n");
		}
		return 0;
	}
```

