---
layout: post
title: "Java WindowListener & ActionListener"
date: 2009-10-24 15:32:00 +0800
comments: false
categories:
- 2009
- 2009~10
- language
- language~java
tags:
---
#### Java WindowListener & ActionListener
```
	//package java_window;
	import java.awt.*;
	import java.awt.event.*;

	class Window
	{
		Frame fra = new Frame();
		public static int tt = 1;
		public static Label lb = new Label(" label ");
		public void go() {
			fra.addWindowListener(
				new WindowAdapter(){
				public void windowClosing(WindowEvent e) {
					System.exit(0);
				}
			});
			fra.setSize(700, 550);
			fra.setLayout(null);
			Button but = new Button(" OK ");
			but.setBounds(200, 200, 100, 70);	fra.add(but);
			lb.setBounds(200, 300, 200, 100);	 fra.add(lb);

			but.addActionListener(
				new ActionListener() {
				public void actionPerformed(ActionEvent event) {
					 lb.setText("ActionEvent "+event.getActionCommand()+"   "+(tt++));
				}
			});
			fra.show();
		}
	}

	public class Main {
		public static void main(String[] args) {
			Window win = new Window();
			win.go();
		}
	}
```
