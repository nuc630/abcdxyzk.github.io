---
layout: post
title: "debugedit，find-debuginfo 改进及el7"
date: 2016-03-28 09:10:00 +0800
comments: false
categories:
- 2016
- 2016~03
- debug
- debug~dwarf
tags:
---

http://vault.centos.org/7.2.1511/os/Source/SPackages/rpm-4.11.3-17.el7.src.rpm

修改tool/debugedit.c
```
	diff --git a/tools/debugedit.c b/tools/debugedit.c
	index 0f85885..257f5f8 100644
	--- a/tools/debugedit.c
	+++ b/tools/debugedit.c
	@@ -602,13 +602,14 @@ edit_dwarf2_line (DSO *dso, uint32_t off, char *comp_dir, int phase)
	 	  if (base_dir == NULL)
	 	    p = s;
	 	  else if (has_prefix (s, base_dir))
	-	    p = s + strlen (base_dir);
	+		{ p = s + strlen (base_dir); while (*p == '/') p++; }
	 	  else if (has_prefix (s, dest_dir))
	-	    p = s + strlen (dest_dir);
	+		{ p = s + strlen (dest_dir); while (*p == '/') p++; }
	 
	-	  if (p)
	+	  if (p && strlen (p) > 2 && flock(list_file_fd, LOCK_EX) == 0)
	 	    {
	 	      size_t size = strlen (p) + 1;
	+		
	 	      while (size > 0)
	 		{
	 		  ssize_t ret = write (list_file_fd, p, size);
	@@ -617,6 +618,7 @@ edit_dwarf2_line (DSO *dso, uint32_t off, char *comp_dir, int phase)
	 		  size -= ret;
	 		  p += ret;
	 		}
	+		flock(list_file_fd, LOCK_UN);
	 	    }
	 	}
	 
	@@ -928,17 +930,18 @@ edit_attributes (DSO *dso, unsigned char *ptr, struct abbrev_tag *t, int phase)
	      it and the debugger (GDB) cannot safely optimize out the missing
	      CU current dir subdirectories.  */
	   if (comp_dir && list_file_fd != -1)
	-    {
	+  {
	       char *p;
	       size_t size;
	 
	       if (base_dir && has_prefix (comp_dir, base_dir))
	-	p = comp_dir + strlen (base_dir);
	+		{ p = comp_dir + strlen (base_dir); while (*p == '/') p++; }
	       else if (dest_dir && has_prefix (comp_dir, dest_dir))
	-	p = comp_dir + strlen (dest_dir);
	+		{ p = comp_dir + strlen (dest_dir); while (*p == '/') p++; }
	       else
	 	p = comp_dir;
	 
	+    if (p && strlen (p) > 2 && flock(list_file_fd, LOCK_EX) == 0) {
	       size = strlen (p) + 1;
	       while (size > 0)
	 	{
	@@ -949,6 +952,8 @@ edit_attributes (DSO *dso, unsigned char *ptr, struct abbrev_tag *t, int phase)
	 	  p += ret;
	 	}
	     }
	+    flock(list_file_fd, LOCK_UN);
	+  }
	 
	   if (found_list_offs && comp_dir)
	     edit_dwarf2_line (dso, list_offs, comp_dir, phase);
	@@ -1548,7 +1553,7 @@ main (int argc, char *argv[])
	     canonicalize_path(dest_dir, dest_dir);
	 
	   /* Make sure there are trailing slashes in dirs */
	-  if (base_dir != NULL && base_dir[strlen (base_dir)-1] != '/')
	+  /*if (base_dir != NULL && base_dir[strlen (base_dir)-1] != '/')
	     {
	       p = malloc (strlen (base_dir) + 2);
	       strcpy (p, base_dir);
	@@ -1563,7 +1568,7 @@ main (int argc, char *argv[])
	       strcat (p, "/");
	       free (dest_dir);
	       dest_dir = p;
	-    }
	+    }*/
	 
	   if (list_file != NULL)
	     {
```

[debugedit_el7](/download/debug/debugedit_el7)

----------------------------

### find-debuginfo.sh 'extracting debug info'时改成多进程

##### 1. 首先要像上面那样debugedit.c加入文件锁

[c 文件锁flock](/blog/2015/11/26/lang-c-flock/)

##### 2. shell模拟多进程

[shell 多进程](/blog/2016/03/25/shell-forks/)

```
	# 先建立fd
	tmp_fifo="/tmp/.tmp_fifo"

	mkfifo $tmp_fifo
	exec 6<>$tmp_fifo
	rm $tmp_fifo

	# 假设8进程，先往fd中写入8字节
	forks=8
	for ((i=0;i<$forks;i++))
	do  
		echo >&6 
	done

	# Strip ELF binaries
	find "$RPM_BUILD_ROOT" ! -path "${debugdir}/*.debug" -type f \
	     		     \( -perm -0100 -or -perm -0010 -or -perm -0001 \) \
			     -print |
	file -N -f - | sed -n -e 's/^\(.*\):[ 	]*.*ELF.*, not stripped/\1/p' |
	xargs --no-run-if-empty stat -c '%h %D_%i %n' |
	while read nlinks inum f; do
	  get_debugfn "$f"
	  [ -f "${debugfn}" ] && continue

	  # If this file has multiple links, keep track and make
	  # the corresponding .debug files all links to one file too.
	  if [ $nlinks -gt 1 ]; then
	    eval linked=\$linked_$inum
	    if [ -n "$linked" ]; then
	      link=$debugfn
	      get_debugfn "$linked"
	      echo "hard linked $link to $debugfn"
	      ln -nf "$debugfn" "$link"
	      continue
	    else
	      eval linked_$inum=\$f
	      echo "file $f has $[$nlinks - 1] other hard links"
	    fi
	  fi

	  # 从fd读取一个字节，开始一个进程
	  read -u6
	  {
	    echo "extracting debug info from $f"
	    id=$(/usr/lib/rpm/debugedit_kk -b "$RPM_BUILD_DIR" -d "/usr/src/debug$REPLACE_COMP_DIR" \
				      -i -l "$SOURCEFILE" "$f")
	    if $strict && [ -z "$id" ]; then
	      echo >&2 "*** ${strict_error}: No build ID note found in $f"
	      $strict && exit 2   # 需要先写回一个字节？？？
	    fi

	    # A binary already copied into /usr/lib/debug doesn't get stripped,
	    # just has its file names collected and adjusted.
	    case "$dn" in
	    /usr/lib/debug/*)
	      [ -z "$id" ] || make_id_link "$id" "$dn/$(basename $f)"
	      continue ;;  # 需要先写回一个字节？？？
	    esac

	    mkdir -p "${debugdn}"
	    if test -w "$f"; then
	      strip_to_debug "${debugfn}" "$f"
	    else
	      chmod u+w "$f"
	      strip_to_debug "${debugfn}" "$f"
	      chmod u-w "$f"
	    fi

	    if [ -n "$id" ]; then
	      make_id_link "$id" "$dn/$(basename $f)"
	      make_id_link "$id" "/usr/lib/debug$dn/$bn" .debug
	    fi

	    echo >&6 # 一个进程结束写回一个字节
	    exit 0   # 退出子进程
	  } &
	done || exit

	wait # 等待所有子进程结束
	exec 6>&-  # 删除fd
```

