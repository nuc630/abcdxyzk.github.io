---
layout: post
title: "CodeIgniter用钩子实现基于URL的权限控制"
date: 2012-04-03 21:08:00 +0800
comments: false
categories:
- 2012
- 2012~04
- tools
- tools~ci
tags:
- oj
---
#### 基于URL权限系统：
  例如游客只能访问音乐模块的index,list,search方法。而注册用户除上述功能之外还能访问create,update,delete方法。那么我们可以在控制器之行之前判断当前用户是否具备访问该控制器的权限。

#### 实现：
直接上代码：  
##### 1.system/application/config/hooks.php中添加钩子声明：
```
	$hook['post_controller_constructor'] = array(
		'class' => 'Acl',
		'function' => 'filter',
		'filename' => 'acl.php',
		'filepath' => 'hooks',
	);
```
##### 2.system/application/config/config.php中让钩子系统生效
```
	$config['enable_hooks'] = TRUE;
```
##### 3.然后在config中新建acl.php权限系统配置文件，当然你也可以放在数据库中。
//游客权限映射
```
	$config['acl']['visitor'] = array(
		'' => array('index'),//首页
		'music' => array('index', 'list'),
		'user' => array('index', 'login', 'register')
	);
```
//管理员
```
	$config['acl']['admin'] = array(
	);
```
//-------------配置权限不够的提示信息及跳转url------------------//
```
	$config['acl_info']['visitor'] = array(
		'info' => '需要登录以继续',
		'return_url' => 'user/login'
	);
	$config['acl_info']['more_role'] = array(
		'info' => '需要更高权限以继续',
		'return_url' => 'user/up'
	);
	/* End of file acl.php */
	/* Location: ./application/config/acl.php */
```
##### 4.system/application/hooks目录下添加acl.php逻辑处理文件
```
	class Acl
	{
		private $url_model;//所访问的模块，如：music
		private $url_method;//所访问的方法，如：create
		private $url_param;//url所带参数 可能是 1 也可能是 id=1&name=test
		private $CI;
	 
		function Acl()
		{
			$this->CI = & get_instance();

			if (!session_id()) session_start();

			$url = $_SERVER['PHP_SELF'];
			$arr = explode('/', $url);
			$arr = array_slice($arr, array_search('index.php', $arr) + 1, count($arr));
			$this->url_model = isset($arr[0]) ? $arr[0] : '';
			$this->url_method = isset($arr[1]) ? $arr[1] : 'index';
			$this->url_param = isset($arr[2]) ? $arr[2] : '';
		}
		function filter()
		{
			$user = $this->CI->session->userdata('user');
			if (empty($user)) {//游客visitor
				$role_name = 'visitor';
			} else {
				$role_name = $user->role;
			}

			$this->CI->load->config('acl');
			$acl = $this->CI->config->item('acl');
			$role = $acl[$role_name];
			$acl_info = $this->CI->config->item('acl_info');

			if (array_key_exists($this->url_model, $role) && in_array($this->url_method, $role[$this->url_model])) {
				;
			} else {//无权限，给出提示，跳转url
				$_SESSION['info'] = $acl_info[$role_name]['info'];
				redirect($acl_info[$role_name]['return_url']);
			}
		}
	}
```

