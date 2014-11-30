---
layout: post
title: "Connecting Two Virtual Machines"
date: 2014-02-28 17:50:00 +0800
comments: false
categories:
- 2014
- 2014~02
- debug
- debug~base
tags:
---
  You can set up the virtual serial ports in two virtual machines to connect to each other. This is useful, for example, if you want to use an application in one virtual machine to capture debugging information sent from the other virtual machine's serial port.

  To install a direct serial connection between two virtual machines (a server and a client), take the following steps:

#### Windows Host In the server virtual machine
1. Open the virtual machine settings editor (VM > Settings).
2. Click Add to start the Add Hardware Wizard.
3. Select Serial Port, then click Next.
4. Select Output to named pipe, then click Next.
5. Use the default pipe name, or enter another pipe name of your choice. The pipe name must follow the form \\.\pipe\<namedpipe> — that is, it must begin with \\.\pipe\.
6. Select This end is the server.
7. Select The other end is a virtual machine.
8. By default, the device status setting is Connect at power on. You may deselect this setting if you wish.
Click Advanced if you want to configure this serial port to use polled mode. This option is of interest primarily to developers who are using debugging tools that communicate over a serial connection. For more information, see [Special Configuration Options for Advanced Users.](https://www.vmware.com/support/ws55/doc/ws_devices_serial_advanced.html)  
9. Click Finish, then click OK to close the virtual machine settings editor.

#### In the client virtual machine
1. Open the virtual machine settings editor (VM > Settings).
2. Click Add to start the Add Hardware Wizard.
3. Select Serial Port, then click Next.
4. Select Use named pipe.
5. Use the default name, or enter another pipe name of your choice. The pipe name must follow the form \\.\pipe\<namedpipe> — that is, it must begin with \\.\pipe\. The pipe name must be the same on both server and client.
6. Select This end is the client.
7. Select The other end is a virtual machine.
8. By default, the device status setting is Connect at power on. You may deselect this setting if you wish.
Click Advanced if you want to configure this serial port to use polled mode. This option is of interest primarily to developers who are using debugging tools that communicate over a serial connection. For more information, see [Special Configuration Options for Advanced Users.](https://www.vmware.com/support/ws55/doc/ws_devices_serial_advanced.html)
9. Click Finish, then click OK to close the virtual machine settings editor.

#### Linux Host In the server virtual machine
1. Open the virtual machine settings editor (VM > Settings).
2. Click Add to start the Add Hardware Wizard.
3. Select Serial Port, then click Next.
4. Select Output to named pipe, then click Next.
5. In the Path field, enter /tmp/<socket> or another Unix socket name of your choice.
6. Select This end is the server.
7. Select The other end is a virtual machine.
8. By default, the device status setting is Connect at power on. You may deselect this setting if you wish.
Click Advanced if you want to configure this serial port to use polled mode. This option is of interest primarily to developers who are using debugging tools that communicate over a serial connection. For more information, see [Special Configuration Options for Advanced Users.](https://www.vmware.com/support/ws55/doc/ws_devices_serial_advanced.html)
9. Click Finish, then click OK to save your configuration and close the virtual machine settings editor.

#### In the client virtual machine
1. Open the virtual machine settings editor (VM > Settings).
2. Click Add to start the Add Hardware Wizard.
3. Select Serial Port, then click Next.
4. Select Output to named pipe, then click Next.
5. In the Path field, enter /tmp/<socket> or another Unix socket name of your choice. The pipe name must be the same on both server and client.
6. Select This end is the client.
7. Select The other end is a virtual machine.
8. By default, the device status setting is Connect at power on. You may deselect this setting if you wish.
Click Advanced if you want to configure this serial port to use polled mode. This option is of interest primarily to developers who are using debugging tools that communicate over a serial connection. For more information, see [Special Configuration Options for Advanced Users.](https://www.vmware.com/support/ws55/doc/ws_devices_serial_advanced.html)
9. Click Finish, then click OK to save your configuration and close the virtual machine settings editor.
