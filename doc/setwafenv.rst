.. _setwafenv-top:

================
bde_setwafenv.py
================

Introduction
============

bde_setwafenv.py is a tool that can be used to simplify the process of
selecting a compiler and managing multiple build flavors (different
platforms/options).

More specifically, the tool helps solve the following problems when using waf:

1. The output directory of build artifacts is by default just "build".  Without
   changing the output directory to be different for every build configuration,
   build artifacts for different build configurations will interfere with each
   other.

2. Waf uses a lock file to store the location of the output directory (so that
   the output directory won't have to be again specified when ``waf build`` is
   invoked).  The name of the lock file is the same for all build
   configurations on the same platform.  This means building different build
   configurations in parallel is not possible without changing the name of the
   lock file to be unqiue for each build configuration.

3. When working with multiple repositories having dependency relationships.
   Developers have to install the repository containing the lower-level
   libraries first.  Handling the install process independently for each build
   configuration is a hassle in a way similar to problem 1.

Prerequisites and Supported Platforms
=====================================

bde_setwafenv.py requires:

-  Python 2.6.x - 2.7.x, Python 3.3+

bde_setwafenv.py is supported on all platform where the :ref:`waf based build
system is supported <waf-supported_platforms>`.

On Windows, bde_setwafenv.py is *not supported* by the windows command
prompt. Instead, you must use the tool through cygwin.  See the tutorial
:ref:`tutorials-setwafenv-bde-windows` for more details.

How It Works
============

bde_setwafenv.py prints a list of Bourne shell commands to set environment
variables known to waf, so that configuration options do not need to be
manually provided to ``waf configure``.  The end result is that the build
output directory, installation prefix, and the name of the waf lock file are
unique for each build configuration.

.. important::

   Since the bde_setwafenv.py prints shell commands to the standard output, the
   output must be executed by the current *Bourne* shell using the ``eval``
   command.

Environment Variables Set by bde_setwafenv.py
---------------------------------------------

The following environment variables may be set by evaluating the output of
bde_setwafenv.py:

- ``CXX``

  The path to the C++ compiler.

- ``BDE_WAF_COMP_FLAGS``

  Extra flags that should be passed to the compiler.

- ``BDE_WAF_UFID``

  The :ref:`bde_repo-ufid` to use.

- ``BDE_WAF_UPLID``

  The UPLID determined by bde_setewafenv. Note that waf will still generate a
  uplid based on the current platform and the compiler being used. If the
  generated uplid does not match BDE_WAF_UPLID, then waf will print a warning
  message and proceed to use 'BDE_WAF_UPLID' as the uplid.

- ``BDE_WAF_BUILD_DIR``

  The path in which build artifacts will be generated.  This will be set to the
  expanded value of ``"$BDE_WAF_UPLID-$BDE_WAF_UFID``, so that build directory
  is unique for each build configuration.

- ``WAFLOCK``

  The name of lock file to use, this be unique for each build configuration.

- ``PREFIX``

  The installation prefix, which will be set to
  ``<root-installation-directory>/$BDE_WAF_UPLID-$BDE_WAF_UFID``.  See the
  description for the ``-i`` option in the :ref:`Options section
  <setwafenv-options>` for more details.

- ``PKG_CONFIG_PATH``

  The path containing the .pc files for the installed libraries.  This will be
  set to ``$PREFIX/lib/pkgconfig``.

.. _setwafenv-compiler_config:

Configuring the Available Compilers
===================================

On unix-based platforms, bde_setwafenv.py requires a compiler configuration
file located at ``~/.bdecompilerconfig`` to define the compilers that are
available on the system.

On windows, this configuration file is *not used*.  Since the list of supported
compilers is very limited on windows, it is hard coded into the tool.

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

An example file is located at ``<bde-tools>/etc/bdecompilerconfig.sample``.

The JSON file should contain a list of machine context (dictionary) to be
matched, each machine context defines the compilers that are available on the
machine.

A machine context is matched by the following 2 fields:

- ``hostname``

  An *optional* field that matches regular expression that matches the host name
  of the machine.

- ``uplid``

  A partial :ref:`bde_repo-uplid` mask that matches the platform of the
  machine.  The first machine context that matches in the list will be chosen.

.. note::
   Tip: if you are using bde_setwafenv.py on one machine.  Don't define
   ``hostname`` and just use ``-`` (a dash) as ``uplid``.

The ``compilers`` field that contains a list of compilers on the machine.  The
first compiler in the list will be treated as the default. A compiler is
represented by a dictionary having the following fields:

- ``cxx_path``

  The path to the C++ compiler. If this is specified then "path" should not be.

- ``c_path``

  The path to the C compiler.

- ``type``

  The type of the compiler.

- ``version``

  The version number of the compiler.

- ``flags``

  This is an *optional* field that defines additional arguments to pass to this
  compiler. This is useful for options such as xlc's ``-qpath`` option, which
  allows the partial patching of the compiler.


Commands and Options
====================

Commands
--------
By default, bde_setwafenv.py will print the Bourne shell commands to set
environment variables.

It also provides 2 other optional commands:

- ``unset``

  Print Bourne shell commands to unset any environment variables that might be
  set previous by bde_setwafenv.py.

- ``list``

  List the available compilers on this machine.

.. _setwafenv-options:

Options
-------

- ``-c``

  Specify the compiler to use. If not specified, then the default will be used.

- ``-t``

  Specify the build configuration using a :ref:`bde_repo-ufid`.

- ``-i``

  Specify the "root installation directory".  This directory is not the same as
  the '--prefix' option passed to the 'waf configure' command. Instead, it
  serves as the directory under which a sub-directory, named according to the
  uplid (determined by the specified compiler and the current platform) and
  ufid, is located.  This sub-directory is the actual prefix location.

  This design decision is made so that multiple builds using different
  configurations may be installed to the same "root installation directory".
  If no installation directory is supplied, but the ``PREFIX`` environment
  variable value matches the pattern produced by this script, then the
  installation directory previously configured by this script is used.


In addition, most of the configuration option provided by the :ref:`waf-top`
can be used.  Use the ``--help`` option for more information.

Usage Examples
==============

1. ``eval $(bde_setwafenv.py -c gcc-4.7.2 -t dbg_mt_exc -i ~/mbig/bde-install)``

   Set up the environment variables so that the BDE waf build tool uses the
   gcc-4.7.2 compiler, builds with the ufid options 'dbg_mt_exc' to the output
   directory '<uplid>-<ufid>', and install the libraries to a installation
   prefix of '~/mbig/bde-install/<uplid>-<ufid>'.

   On a particular unix system, the uplid will be
   'unix-linux-x86_64-2.6.18-gcc-4.7.2', and
   'unix-linux-x86_64-2.6.18-gcc-4.7.2-dbg_mt_exc' will be the name of the
   build output directory.

2. ``eval $(bde_setwafenv.py)``

   Set up the environment variables so that the BDE waf build tool uses the
   default compiler on the current system configured using the default
   ufid. Use the default installation prefix, which typically will be
   /usr/local -- this is not recommended, because the default prefix is
   typically not writable by a regular user.
