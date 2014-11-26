---
layout: post
title: "Java KeyListener 的使用"
date: 2009-10-23 22:49:00 +0800
comments: false
categories:
- 2009
- 2009~10
- language
- language~java
tags:
---
#### Java KeyListener 的使用
```
	//package java_key;
	import java.awt.*;
	import java.awt.event.*;
	import javax.swing.*;

	class KeyWork extends JFrame implements KeyListener
	{
		private JLabel status;
		public KeyWork()
		{
			super("abcd");
			status = new JLabel();
			status.setFont(new Font("TimesRoman", Font.BOLD, 50));
			getContentPane().add(status, BorderLayout.CENTER);
			addKeyListener(this);
			setSize(700,500);
			show();
		}
		public void keyPressed(KeyEvent e) {
			char ch = e.getKeyChar();
			status.setText(String.valueOf(ch) + "   " +(int)ch);
		}
		public void keyTyped(KeyEvent e) {
		   
		}
		public void keyReleased(KeyEvent e) {
		   
		}
	}

	public class Main {
		public static void main(String[] args) {
			KeyWork app = new KeyWork();
			app.addWindowListener(new WindowAdapter(){
				public void windowClosing(WindowEvent e) {
					System.exit(0);
				}
			});
		}
	}
```
