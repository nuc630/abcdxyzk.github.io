---
layout: post
title: "jni 编程"
date: 2012-02-15 20:22:00 +0800
comments: false
categories:
- 2012
- 2012~02
- language
- language~java
tags:
- koj
---
#### jni 编译：
g++ -L /usr/lib/jvm/default-java/jre/lib/amd64/server -o judge judge.cpp -ljvm

#### jni 运行：
以root身份把库路径加入/etc/ld.so.conf或在/etc/ld.so.conf.d中创建特定的.conf文件，然后运行 ldconfig更新/etc/ld.so.cache。例如：在/etc/ld.so.conf.d下创建文件jvm.conf写入
```
/usr/lib/jvm/default-java/jre/lib/amd64
/usr/lib/jvm/default-java/jre/lib/amd64/server
```

#### jni
  GetFieldID是得到java类中的参数ID，GetMethodID得到java类中方法的ID，它们只能调用类中声明为 public的参数或方法。使用如下：
```
jfieldID topicFieldId = env->GetFieldID(objectClass,"name", "Ljava/lang/String;");
jmethodID getcName=env->GetMethodID(objectClass,"getcatName","()Ljava/lang/String;");
```
第一参数是Java 类对象。第二个参数是参数（或方法名），第三个参数是该参数（或方法）的签名。第三个参数由以下方法得到。
有类
```
	public class Cat {
		private int catNumber;
		String catName;
		public Cat(int i,String name){catNumber=i;catName=name;}
		public String getCatName () {
			return this.catName;
		}

		public void setCatName (String catName) {
			this.catName=catName;
		}
	}
```
查看 Cat类进入到Cat所在目录 先用javac Cat.java进行编译 然后输入命令：
```
Javap –s Cat
```
得到Cat方法getcatName 的签名是()Ljava/lang/String，Cat类中的参数是private 所以它没有签名。
```
options[0].optionString = "-Djava.class.path=./tmp/1";
```

