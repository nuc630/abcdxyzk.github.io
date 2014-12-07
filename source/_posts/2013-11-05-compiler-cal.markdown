---
layout: post
title: "编译期间求值"
date: 2013-11-05 14:26:00 +0800
comments: false
categories:
- 2013
- 2013~11
- compiler
- compiler~base
tags:
---
编译期求阶乘
#### c++ 中的模板可以用来计算一些值，在编译的时候就是实现计算，而不是运行的时候。
求阶乘 n!，一般 me 们会写个这样的程序：
```
	#include <iostream>
	long Factorial(long n)
	{
		return n == 0 ? 1 : n*Factorial(n-1);
	}

	int main()
	{
		long fac=1, n=20;
		for(int i=1; i<=n; ++i)fac *= i;
		std::cout << "20! = " << fac << " " << Factorial(20) << std::endl;
		return 0;
	}
```
现在使用模板技术，类似于递归的方法求 20 !。
```
	#include <iostream>

	template<int N>
	class Factorial{
	public:
		static const long value = N*Factorial<N-1>::value;
	};

	template<>
	class Factorial<0>{
	public:
		static const long value = 1;
	};

	int main()
	{
		std::cout << "20! = " << Factorial<20>::value << std::endl;
		return 0;
	}
```
说明：  
  template 通常用来参数化类型，通常 class T 或是 typename T(T 用来代替一个类型的名字)，不过也可以带一个整型参数 N (貌似规定只能是整型)。  
  template <> 是用来特殊指定一些情形，比如上面给的 Factorial<0> 指定 N = 0 时的情形，这有点像递归中的 if(n==0) return 1;  
  class 类中可以带有 static const 变量，这种变量可以在类内初始化(只能是整型)；当然既是 const 变量，又是 static 变量；  
  Factorila<20> 实际是一个类，而 ::value 是其 static 变量；在生成Factorila<20> 的时候同时生成了众多的Factorila<N> ( N >0 && N < 20)类；  

更多例子  
模板类，或是模版函数，或是模板成员函数，都是编译器根据程序的实际情况而生成的，需要什么就生成什么，不需要就不生成。上面的例子中， 程序中使用 Factorial<20> 这个类，就生成这个类，因为 Factorial<20> 依赖 Factorial<19> 所以又生成 Factorial<19> ，这样一直依赖下去，直到 Factorial<0>( me 们已经指定了)。因为是编译期生成，也是编译器求值，所以实际程序中只能使用 static const 类似的 —— 常量，而不能使用普通的 int n。所以，模板元编程中，么发使用循环，只能类似递归的技术。  
通常 me 们会将递归程序转换为循环程序，实际上循环程序基本也都可以递归解决。(是不是一定呢？O__O"…)  
求斐波那契数
```
	#include <iostream>

	template <long N>
	struct Fibonacci{
		static const long value = Fibonacci<N-1>::value + Fibonacci<N-2>::value;
	};

	template<>
	struct Fibonacci<0>{
		static const long value = 0;
	};

	template<>
	struct Fibonacci<1>{
		static const long value = 1;
	};

	int main()
	{
		std::cout << Fibonacci<12>::value << std::endl;
		return 0;
	}
```
第 12 个斐波那契数是 144，这是唯一一个 Fib(n) = n*n 的数。
求 1+2+3+...+n
```
	#include <iostream>

	template <long N>
	struct Sum{
		static const long value = N+Sum<N-1>::value;
	};

	template<>
	struct Sum<1>{
		static const long value = 1;
	};

	int main()
	{
		std::cout << Sum<100>::value << std::endl;
		return 0;
	}
```
这个和 n! 的用法基本一样。
  
#### constexpr编译期求值
  模板只是在编译的时候完成工作的一种方法，实际上上面的模板元编程也只是在编译期求了一些常量而已；为了简化使用模板进行元编程的难度，c++11 引入了 constexpr 关键字 —— 声明常量或是函数，实现在编译期求值。上面的三个程序都可以大大简化：
```
	#include <iostream>

	constexpr long factorial(long n)
	{
		return n<=1 ? 1 : n*factorial(n-1);
	}
	constexpr long fibonacci(long n)
	{
		return n<=1 ? n : fibonacci(n-1)+fibonacci(n-2);
	}
	constexpr long sum(long n)
	{
		return n<=1 ? n : n+sum(n-1);
	}

	int main()
	{
		std::cout << "10! F(12) 1+2+...+100 => " << factorial(10) << " " << fibonacci(12) << " " << sum(100) << std::endl;
		return 0;
	}
```
不用多数，看应该看得懂神马意思，要提的就是 constexpr 都是编译的时候求值。

