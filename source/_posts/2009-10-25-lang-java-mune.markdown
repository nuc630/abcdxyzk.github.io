---
layout: post
title: "Java Mune & Button"
date: 2009-10-25 21:20:00 +0800
comments: false
categories:
- 2009
- 2009~10
- language
- language~java
tags:
---
#### Java Mune & Button
```
	//package java_menu;
	import java.awt.*;
	import java.awt.event.*;

	class BBB extends Button
	{
		private int tt=0;
		public BBB() {
			super("0");
			addMouseListener( new MouseListener() {
				public void mousePressed(MouseEvent e) {
					setLabel(String.valueOf((++tt)));
				}
				public void mouseExited(MouseEvent e) {}
				public void mouseReleased(MouseEvent e) {}
				public void mouseEntered(MouseEvent e) {}
				public void mouseClicked(MouseEvent e) {}
			});
			int x=(int)(Math.random()*10000), y=(int)(Math.random()*10000);
			setBounds( x % 500+70, y % 300+70, 70, 70);
			show();
		}
	}

	class MenuExam extends Frame
	{
		public MenuExam()
		{
			super("abcdxyzk");
			MenuBar bar = new MenuBar(); setMenuBar(bar);
			Menu bb = new Menu(" bbb ");
			MenuItem b1 = new MenuItem(" b1 ");
			MenuItem b2 = new MenuItem(" b2 ");
			bb.add(b1); bb.addSeparator(); bb.add(b2); bar.add(bb);

			b2.addActionListener( new ActionListener() {
				public void actionPerformed(ActionEvent e) {
					BBB bbb = new BBB();
					add(bbb);
				}
			});
			setLayout(null);   setSize(700, 500);
			TextField tf = new TextField();
			tf.setText("click b2");
			tf.setFont(new Font("TimesRoman", Font.BOLD, 30));
			tf.setEnabled(false);
			tf.setBounds(100, 350, 200, 100);
			add(tf);
			show();
		}
	}

	public class Main {
		public static void main(String[] args) {
			MenuExam mm = new MenuExam();
			mm.addWindowListener( new WindowAdapter() {
				public void windowClosing(WindowEvent e) {
					System.exit(0);
				}
			});
		}
	}
```
