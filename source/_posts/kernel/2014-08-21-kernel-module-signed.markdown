---
layout: post
title: "linux内核模块签名"
date: 2014-08-21 18:23:00 +0800
comments: false
categories:
- 2014
- 2014~08
- kernel
- kernel~base
tags:
---
#### linux内核模块签名 Documentation/module_signing.txt
内核在模块模块加载时使用加密签名验证，校验签名是否与已编译的内核公钥匹配。目前只支持RSA X.509验证。  
签名验证在通过CONFIG_MODULE_SIG使能。打开签名同时还会强制做模块ELF元数据检查，然后再做签名验证。  

#### 公钥生成
内核编译时可以指定一系列的公钥。x509.genkey文件用来生成X509密钥。如果没有该文件，系统会自动提供一个默认的配置。Makefile会根据x509.genkey规则在内核编译根目录生成默认配置，用户可以手动更改该文件。

由此在内核编译过程中分别生成私钥和公钥文件分别为./signing_key.priv和./signing_key.x509。

默认配置是使用/dev/random生成的。如果/dev/random没有足够数据，在后台运行以下命令可以生成更多的数据：rngd -r /dev/urandom。

#### 模块签名
设置了CONFIG_MODULE_SIG_ALL，所有模块将会自动添加签名。如果没有设置，需要手动添加：  
scripts/sign-file <hash algo> $(MODSECKEY) $(MODPUBKEY) modules.ko  
哈希算法必须为sha1, sha224, sha256, sha384, sha512。对应的加密算法必须是使能的。CONFIG_MODULE_SIG_HASH设置sign-file使用的默认算法。  

`MODSECKEY=<secret-key-ring-path>`  
加密私钥文件，默认是./signing_key.priv

`MODPUBKEY=<public-key-ring-path>`  
加密公钥文件，默认为./signing_key.x509

###### 签名模块裁减
签名模块裁减就是去除签名部分，在重新签名之前需要先裁减之前的签名。在打包内核模块发布时，并没有自动裁减。

###### 加载签名模块
模块是通过insmod来加载的，模块加载时通过检查模块的签名部分来验证。

###### 不合法签名和没有签名的模块

如果设 置了CONFIG_MODULE_SIG_FORCE或者在内核启动命令行设置了module.sig_enforce，内核将只加载带有公钥的合法签名 模块。如果都没有设置则会加载没有签名的模块。如果内核有密钥，但模块没有提供合法的签名就会被拒绝加载。下表说明了各种情况：

```
模块状态		许可模式	强制检查
未签名			通过		EKEYREJECTED
签名，没有公钥		ENOKEY		ENOKEY
签名，公钥		通过		通过
非法签名，公钥		EKEYREJECTED	EKEYREJECTED
签名，过期密钥		EKEYEXPIRED	EKEYEXPIRED
破坏的签名		EBADMSG		EBADMSG
破坏的ELF		ENOEXEC		ENOEXEC
```

