.. _bbs-overview-top:

Overview
========

BBS build system is a set of CMake modules, tools and configuration files that
simplify development of the libraries that adhere to the BDE physical code
organization methodology.

BBS CMake Modules
=================
BBS CMake modules provide functions for:

  * Parsing BDE metadata files that provide the list of sources and
    dependencies of a library or an application
  * Generating targets for building libraries, applications and tests from the
    sources extracted from the metadata files
  * Resolving external dependencies
  * Generating templated c++ code
  * Generating and labeling test targets
  * Generating install target and components

BBS Tools
=========

BBS tools provide a set of scripts that simplify common developer tasks such
as:

  * Setting build environement (compilers, build type and flavors)
  * Building and testing BDE libraries and applications

Effectively, BBS tools shield users from various mundane tasks associated with
build process - creating various folders, generating cmake command line and
invoking cmake and low level build system. 
