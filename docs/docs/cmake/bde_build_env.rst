.. _bde_build_env-top:

================
bde_build_env.py
================

Introduction
============

``bde_build_env.py`` is a tool that can be used to simplify the process of
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

``bde_build_env.py`` requires:

-  Python 2.6.x - 2.7.x, Python 3.3+

``bde_build_env.py`` is supported on all platform where the :ref:`CMake based
build system is supported <build_system-into-supported_platforms>`.

On Windows, bde_build_env.py is **not supported** by the windows command
prompt. Instead, you must use the tool through Cygwin or msysgit.  See the
tutorial for more details (TODO).

How It Works
------------

``bde_build_env.py`` prints a list of Bourne shell commands to set environment
variables known to ``cmake_build.py``, so that configuration options do not
need to be manually provided.  The end result is that the build output
directory, compiler, and installation prefix are unique for each build
configuration.

.. important::
   Since the bde_build_env.py prints shell commands to the standard output, the
   output must be executed by the current *Bourne* shell using the ``eval``
   command.


Usage Examples
--------------

1. ``eval `bde_build_env.py -c gcc-5.4.0 -t dbg_exc_mt -i ~/bde-install```

   Set up the environment variables so that the ``cmake_build.py`` build tool
   uses the gcc-5.4.0 compiler (from ``~/.bdecompilerconfig``), builds with the
   UFID configuration 'dbg_mt_exc' to the output directory ``<uplid>-<ufid>``,
   and install the libraries to a installation prefix of ``~/bde-install/``.

   For example, on my system, the uplid was
   ``unix-linux-x86_64-2.6.32-gcc-5.4.0``, and
   ``unix-linux-x86_64-2.6.32-gcc-5.4.0-dbg_exc_mt`` was the name of the build
   output directory.


2. ``eval `bde_setwafenv.py```

   Set up the environment variables so that the BDE waf build tool uses the
   default compiler on the current system configured using the default UFID.
   Use the default installation prefix, which typically will be ``/usr/local``
   -- this is not recommended, because the default prefix is typically not
   writable by a regular user.


.. _bde_build_env-env:

Environment Variables Set by bde_build_env.py
---------------------------------------------

The following environment variables may be set by evaluating the output of
bde_setwafenv.py:

- ``CXX``

  The path to the C++ compiler.

- ``CC``

  The path to the C compiler.

- ``BDE_CMAKE_TOOLCHAIN``

  The path to the CMake toolchain. If the toolchain file is set, it will
  override the ``CXX`` and ``CC`` variables during CMake configuration step.

- ``BDE_CMAKE_UFID``

  The :ref:`bde_repo-ufid` to use.

- ``BDE_CMAKE_UPLID``

  The UPLID determined by ``bde_build_env.py``. Note that UPLID is primarily
  used to setup compile environment for Windows.

- ``BDE_CMAKE_BUILD_DIR``

  The path in which build artifacts will be generated.  This will be set to the
  expanded value of ``"$BDE_CMAKE_UPLID-$BDE_CMAKE_UFID``, so that build
  directory is unique for each build configuration.

- ``PREFIX``

  The installation prefix.

.. _bde_build_end-compiler_config:

Configuring the Available Compilers
===================================

On UNIX-based platforms, bde_setwafenv.py requires a compiler configuration
file located at ``~/.bdecompilerconfig`` to define the compilers that are
available on the system.

On Windows, this configuration file is **not used**.  Since the list of
supported compilers is very limited on windows, it is hard coded into the tool.

The JSON file should have the following format:

::

    [
        {
            "hostname": "<hostname_regex>",
            "uplid": "<partial-uplid>",
            "compilers": [
                {
                    "type": "<type>",
                    "c_path": "<c_path>",
                    "cxx_path": "<cxx_path>",
                    "version": "<version>",
                    "flags": "<flags>",
                },
                ...
            ]
        },
        ...
    ]

A sample configuration file can be found at
``<bde-tools>/share/sample-config/bdecompilerconfig.sample``.

The JSON file should contain a list of machine context (dictionary) to be
matched, each machine context defines the compilers that are available on the
machine.

A machine context is matched by the following 2 fields:

- ``hostname``

  An *optional* field that is a regular expression that matches the host name
  of the machine.

- ``uplid``

  A partial :ref:`bde_repo-uplid` mask that matches the platform of the
  machine.  The first machine context that matches in the list will be chosen.

.. note::
   Tip: if you are using ``bde_build_env.py`` on one machine.  Don't define
   ``hostname`` and just use ``-`` (a dash) as ``uplid``.

The ``compilers`` field that contains a list of compilers on the machine.  The
first compiler in the list will be treated as the default. A compiler is
represented by a dictionary having the following fields:

- ``cxx_path``

  The path to the C++ compiler.

- ``c_path``

  The path to the C compiler.

- ``type``

  The type of the compiler.

- ``version``

  The version number of the compiler.

Commands and Options
====================

Commands
--------
By default, ``bde_build_env.py`` will print the Bourne shell commands to set
environment variables.

It also provides 3 other optional commands:

.. option:: unset

  Print Bourne shell commands to unset any environment variables that might be
  set previous by bde_setwafenv.py.

.. option:: list

  List the available configured compilers on this machine.

.. option:: set

  Print Bourne shell commands to set environment variables.  This is the
  default command if none is specified. The section
  :ref:`bde_build_env-options` documents the options available for this
  command.


.. _bde_build_env-options:

Set Command Options
-------------------

.. option:: -c, --compiler

  Specify the compiler to use. If not specified, then the default will be used.

.. option:: -t, --ufid

  Specify the build configuration using a :ref:`bde_repo-ufid`.

.. option:: -b, --build-dir

  Specify the build directory.

.. option:: -i

  Specify the "root installation directory". TODO ( currently ignored )

Use the ``--help`` option for more information.
