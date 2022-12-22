.. _bbs-overview-top:

------------
BBS Overview
------------
The ``BDE Build System`` (BBS) is a set of CMake modules, tools, and
configuration files that automate the configuration, build, and installation of
the code that use a :doc:`BDE-style physical code
organization<bde_repo_layout>`.

CMake Modules
-------------
BBS CMake modules provide functions for:

  * Parsing BDE metadata files that provide the list of sources and
    dependencies of a library or an application
  * Generating targets for building libraries, applications and tests from the
    sources extracted from the metadata files
  * Resolving external dependencies
  * Generating templated c++ code
  * Generating and labeling test targets
  * Generating install target and components

Tools
-----
BBS tools provide a set of scripts that simplify common developer tasks such
as:

  * Setting build environement (compilers, build type and flavors)
  * Building and testing BDE libraries and applications

Effectively, BBS tools shield users from various mundane tasks associated with
build process - creating various folders, generating cmake command line and
invoking cmake and low level build system.
