.. _bbs_build_env-top:

=============
bbs_build_env
=============

Introduction
============

``bbs_build_env`` is a tool that can be used to simplify the process of
selecting a compiler and managing multiple build flavors.

More specifically, the tool helps solve the following problems when using
CMake:

1. CMake does not create the output directory for build artifacts.  The script
   evaluates the system and build configuration and creates easily
   identifiable name for the build directory that is used by other build
   scripts.

2. Setting a compiler configuration under Windows OS ( which is significantly
   different from Unix )

Prerequisites and Supported Platforms
-------------------------------------

``bbs_build_env`` requires:

-  Python 3.6+

``bbs_build_env`` is supported on all platform where the :ref:`CMake based
build system is supported <requirements-top>`.

On Windows, bbs_build_env is **not supported** by the windows command
prompt. Instead, you must use the tool through Git bash(msysgit).  See the
tutorial for more details (TODO).

How It Works
------------

``bbs_build_env`` prints a list of Bourne shell commands to set environment
variables known to ``bbs_build``, so that configuration options do not need to
be manually provided.  The end result is that the build output directory,
compiler, and installation prefix are unique for each build configuration.

.. important::
   Since the ``bbs_build_env`` prints shell commands to the standard output,
   the output must be executed by the current *Bourne* shell using the ``eval``
   command.


Usage Examples
--------------
1. ``bbs_build_env list``

   List the selection of compilers available in the environment.

   These compilers may be provided using the ``-p`` option when configuring
   the environment (see below).  Additional compilers can be manually configured
   into this list by editing ``~/.bbs_build_profiles``.  See
   :doc:`../howtos/configure_profile`.
   

2. ``eval `bbs_build_env -p gcc-9.0.0 -u dbg_64 -i ~/bde-install```

   Set up the environment variables so that the ``bbs_build`` build tool uses
   the build profile named ``gcc-9.0.0`` (assuming that build profile with this
   name exist), builds with the UFID configuration 'dbg_64' to the output
   directory ``<uplid>-<ufid>``, and install the libraries to a installation
   prefix of ``~/bde-install/``.

   For example, on my system, the uplid was
   ``unix-linux-x86_64-2.6.32-gcc-9.0.0``, and
   ``unix-linux-x86_64-2.6.32-gcc-9.0.0-dbg_64`` was the name of the build
   output directory.


.. _bbs_build_env-env:

Environment Variables Set by bbs_build_env
------------------------------------------

The following environment variables may be set by evaluating the output of
bbs_build_env.py:

- ``CXX``

  The path to the C++ compiler.

- ``CC``

  The path to the C compiler.

- ``BBS_ENV_MARKER``

  Flag to use BBS build system in the dual-mode CMakeLists.txt
  (this flag is transitional tool to support both old and new build systems 
  and will be removed once the transition is completed )

- ``BDE_CMAKE_TOOLCHAIN``

  The path to the CMake toolchain. If the toolchain file is set, it will
  override the ``CXX`` and ``CC`` variables during CMake configuration step.

- ``BDE_CMAKE_UFID``

  The :ref:`ufid` to use.

- ``BDE_CMAKE_UPLID``

  The UPLID determined by ``bbs_build_env``. Note that UPLID is primarily
  used to setup compile environment for Windows.

- ``BDE_CMAKE_BUILD_DIR``

  The path in which build artifacts will be generated.  This will be set to the
  expanded value of ``"$BDE_CMAKE_UPLID-$BDE_CMAKE_UFID``, so that build
  directory is unique for each build configuration.

- ``PREFIX``

  The installation prefix.

Commands and Options
====================

.. _bbs_build_env-commands:

Commands
--------
By default, ``bbs_build_env`` will print the Bourne shell commands to set
environment variables.

It also provides 3 other optional commands:

.. option:: unset

  Print Bourne shell commands to unset any environment variables that might be
  set previously by ``bbs_build_env``.

.. option:: list

  List the available build profiles.

.. option:: set

  Print Bourne shell commands to set environment variables.  This is the
  default command if none is specified. The section
  :ref:`bbs_build_env-options` documents the options available for this
  command.


.. _bbs_build_env-options:

Set Command Options
-------------------

.. option:: -p, --profile

  Specify the compiler profile to use.

.. option:: -u, --ufid

  Specify the build configuration using a :ref:`ufid`.

.. option:: --build-type

  Specify the CMake native build type (Debug/Release/RelWithDebInfo).

.. option:: --abi-bits

  Specify the build bitness.

.. note::
   ``--ufid`` option superseds ``--build-type`` and ``--abit-bits`` options
   (the latter will be ignored). Also note that the CMake build types are
   translated into ufid for low level build system.

.. option:: -b, --build-dir

  Specify the build directory.

.. option:: -i, --install-dir

  Specify the "root installation directory".

Use the ``--help`` option for more information.
