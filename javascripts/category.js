function showDiv(divname)
{
	if (document.getElementById(divname).style.display == "block")
		document.getElementById(divname).style.display = "none"; //隐藏层
	else
		document.getElementById(divname).style.display = "block"; //显示层

	var text = document.getElementById("exp_"+divname).innerHTML;
	if (text == "[+]")
		document.getElementById("exp_"+divname).innerHTML = "[-]";
	else if (text == "[-]")
		document.getElementById("exp_"+divname).innerHTML = "[+]";
	else if (text.charAt(0) == '+') {
		document.getElementById("exp_"+divname).innerHTML = text.replace('+', '-');
	} else if (text.charAt(0) == '-') {
		document.getElementById("exp_"+divname).innerHTML = text.replace('-', '+');
	}
}
function GetRequest(name) {
   var url = location.search; //获取url中"?"符后的字串
   if (url.indexOf("?") != -1) {
      var str = url.substr(1);
      strs = str.split("&");
      for(var i = 0; i < strs.length; i ++) {
         if (name == strs[i].split("=")[0])
		return unescape(strs[i].split("=")[1]);
      }
   }
   return null;
}
function hadOpenDiv() {
	var divname = GetRequest("opendiv");
	if (divname != null) {
		var divarr = divname.split("~");
		var name = ""
		for (var i=0; i<divarr.length; i++) {
			if (name != "") name += "~";
			name += divarr[i];
			showDiv(name);
		}
	}
}
