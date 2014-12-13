---
layout: post
title: "Java 多次排序的方法"
date: 2009-12-11 19:24:00 +0800
comments: false
categories:
- 2009
- 2009~12
- language
- language~java
tags:
---
#### Java 多次排序的方法
```
	import java.util.*;

	class Node implements Comparable
	{
		int x,y;
		public int compareTo(Object obj){
			Node oo=(Node)obj;
			if(Main.u == 1) {
				if(oo.x < this.x || oo.x == this.x && oo.y <this.y)return 1;
				return -1;
			} else
			if(Main.u == 2) {
				if(oo.y < this.y || oo.y == this.y && oo.x <this.x)return 1;
				return -1;
			}
			return -1;
		}
	}

	public class Main {
		public static int u;

		public static void main(String[] args) throws Exception {
			Scanner cin = new Scanner(System.in);
			Node a[]=new Node[11];
			int i,j,k,l;
			for(i=1;i<=10;i++) {
				a[i]=new Node();
				a[i].x=Math.abs(5-i); a[i].y=10-Math.abs(7-i);
			}
			u = 1;
			Arrays.sort(a, 1, 11);
			System.out.println(" sort u = 1");
			for(i=1;i<=10;i++)System.out.println(a[i].x+" "+a[i].y);
			u = 2;
			Arrays.sort(a, 1, 11);
			System.out.println(" sort u = 2");
			for(i=1;i<=10;i++)System.out.println(a[i].x+" "+a[i].y);
		}
	}
```
