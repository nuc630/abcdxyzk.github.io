---
layout: post
title: "Java MouseListener & MouseMotionListener"
date: 2009-10-23 21:42:00 +0800
comments: false
categories:
- 2009
- 2009~10
- language
- language~java
tags:
---
##### Java 获取鼠标坐标
```
Point point= MouseInfo.getPointerInfo().getLocation();
```
#### Java MouseListener & MouseMotionListener 的使用
```
	import java.awt.*;
	import java.awt.event.*;
	import javax.swing.*;

	class MouseWork extends JFrame implements MouseListener,MouseMotionListener
	{
		private JLabel status;
		public MouseWork()
		{
			super("abcd");
			status = new JLabel();
			status.setFont(new Font("TimesRoman", Font.BOLD, 50));
			getContentPane().add(status, BorderLayout.CENTER);
			addMouseListener(this);
			addMouseMotionListener(this);
			setSize(700,500);
			show();
		}
		public void mousePressed(MouseEvent e) {
			status.setText(" Pressed "+e.getX()+" "+e.getY());
		}
		public void mouseExited(MouseEvent e) {
			status.setText(" Exited ");
		}
		public void mouseEntered(MouseEvent e) {
			status.setText(" Entered ");
		}
		public void mouseReleased(MouseEvent e) {
			status.setText(" Released ");
		}
		public void mouseClicked(MouseEvent e) {
			status.setText(" Clicked ");
		}
		public void mouseDragged(MouseEvent e) {
			status.setText(" Dragged "+e.getX()+" "+e.getY());
		}
		public void mouseMoved(MouseEvent e) {
			status.setText(" Moved "+e.getX()+" "+e.getY());
		}
	}

	public class Main {
		public static void main(String[] args) {
			MouseWork app = new MouseWork();
			app.addWindowListener(new WindowAdapter(){
				public void windowClosing(WindowEvent e) {
					System.exit(0);
				}
			});
		}
	}
```
