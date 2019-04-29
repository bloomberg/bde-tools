.. _build_system-intro-top:

========
Overview
========

.. _build_system-intro-overview:

Overview
========

BDE build system is a set of tools and configuration files that uses ``cmake``
generator to produce make files for the low level build system (like ``ninja``
or ``make``) and invoke this low level system to  build, install and test
the BDE libraries.

The workflow consists of the following steps:

Configuration
  ``cmake`` parses the build description files, resolves internal and external
  dependancies and produces build, test and install targets

Build
  ``cmake`` invokes the low-level build system to compile and link the BDE
  libraries and unit tests.

Test
  Runs unit tests and present the results.

Install
  Installs the build artefacts (header files, libraries, application and
  supporting metadata) to the specified location.

.. _build_system-into-supported_platforms:

Supported Platform and Compilers
================================

+---------+------------------------------------------------------------+
| OS      | Compilers                                                  |
+=========+============================================================+
| Linux   | gcc 5+, clang 5.x+                                         |
+---------+------------------------------------------------------------+
| Darwin  | gcc 5+, clang 5.x+                                         |
+---------+------------------------------------------------------------+
| Windows | Visual Studio 2013, 2015, 2017, 2019                       |
+---------+------------------------------------------------------------+
| Solaris | Sun Studio 11, Sun Studio 12. gcc 4.1+                     |
+---------+------------------------------------------------------------+
| AIX     | Xlc 9, Xlc 10, Xlc 11, gcc 4.1+                            |
+---------+------------------------------------------------------------+
