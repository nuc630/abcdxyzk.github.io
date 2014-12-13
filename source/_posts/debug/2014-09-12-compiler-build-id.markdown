---
layout: post
title: "Universal Build-ID"
date: 2014-09-12 18:08:00 +0800
comments: false
categories:
- 2014
- 2014~09
- debug
- debug~base
tags:
---
http://fedoraproject.org/wiki/Summer_Coding_2010_ideas_-_Universal_Build-ID

#### Summary
  Build-IDs are currently being put into binaries, shared libraries, core files and related debuginfo files to uniquely identify the build a user or developer is working with. There are a couple of conventions in place to use this information to identify "currently running" or "distro installed" builds. This helps with identifying what was being run and match it to the corresponding package, sources and debuginfo for tools that want to help the user show what is going on (at the moment mostly when things break). We would like to extend this to a more universial approach, that helps people identify historical, local, non- or cross-distro or organisational builds. So that Build-IDs become useful outside the current "static" setup and retain information over time and across upgrades.

### Build-ID background
  Build-IDs are unique identifiers of "builds". A build is an executable, a shared library, the kernel, a module, etc. You can also find the build-id in a running process, a core file or a separate debuginfo file.

  The main idea behind Build-IDs is to make elf files "self-identifying". This means that when you have a Build-ID it should uniquely identify a final executable or shared library. The default Build-ID calculation (done through ld --build-id, see the ld manual) calculates a sha1 hash (160 bits/20 bytes) based on all the ELF header bits and section contents in the file. Which means that it is unique among the set of meaningful contents for ELF files and identical when the output file would otherwise have been identical. GCC now passes --build-id to the linker by default.

  When an executable or shared library is loaded into memory the Build-ID will also be loaded into memory, a core dump of a process will also have the Build-IDs of the executable and the shared libraries embedded. And when separating debuginfo from the main executable or shared library into .debug files the original Build-ID will also be copied over. This means it is easy to match a core file or a running process to the original executable and shared library builds. And that matching those against the debuginfo files that provide more information for introspection and debugging should be trivial.

  Fedora has had full support for build-ids since Fedora Core 8: https://fedoraproject.org/wiki/Releases/FeatureBuildId

#### Getting Build-IDs
  A simple way to get the build-id(s) is through eu-unstrip (part of elfutils).

build-id from an executable, shared library or separate debuginfo file:  
$ eu-unstrip -n -e <exec|.sharedlib|.debug>

build-ids of an executable and all shared libraries from a core file:  
$ eu-unstrip -n --core <corefile>

build-ids of an executable and all shared libraries of a running process:  
$ eu-unstrip -n --pid <pid>

build-id of the running kernel and all loaded modules:  
$ eu-unstrip -n -k

