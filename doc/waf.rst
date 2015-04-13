.. _waf-top:

======================
Waf Based Build System
======================

Introduction
============

The waf-based build system supports building :ref:`BDE-style repositories <bde_repo-top>`.

Supported build actions include:

* Building individual components, packages, or package-groups.
* Building and running test drivers.

The build system is built on top of `waf <https://code.google.com/p/waf/>`_ and
supports all of the vanilla waf commands and options, as well as additional
configuration and build options for working with BDE-style repositories.

For brevity, we'll refer to BDE's waf-based build system simply as waf
going forward.

Prerequisites
=============

Running waf requires:

- Python 2.6.x - 2.7.x, Python 3.3+

Optional:

- pkg-config is required for configuring external dependencies.  If pkg-config
  is not found on the ``PATH`` environment variable, `pykg-config
  <https://github.com/gbiggs/pykg-config>`_, a bundled python based pkg-config
  replacement tool will be used.

For a source-code repository to be built with waf:

- The source code must be organized as a :ref:`bde_repo-top`.

.. note::

   The repository layout can be customized. Please see
   :ref:`bde_repo-layout_customize` for more details.

- A copy of ``bde-tools/etc/wscript`` must be located at the root directory of
  the repository.

You can either run ``bde-tools/bin/waf`` directly or add ``bde-tools/bin`` to
the ``PATH`` environment variable.  The rest of the document assumes that you
have done the later.

.. note::

   The ``bde-tools`` repository contains customziations that may apply to only
   the version of waf bundled in the repo.  If you would like to use a globally
   installed instance of waf for other projects, then don't add
   ``bde-tools/bin`` to your ``PATH``, instead, add to your ``PATH`` a symlink
   having a unqiue name (say ``bdewaf``) pointing to ``bde-tools/bin/waf``.

.. _waf-supported_platforms:

Supported Platform and Compilers
================================

+---------+------------------------------------------------------------+
| OS      | Compilers                                                  |
+=========+============================================================+
| Linux   | gcc 4.1+, clang 3.x                                        |
+---------+------------------------------------------------------------+
| Darwin  | gcc 4.1+, clang 3.x                                        |
+---------+------------------------------------------------------------+
| Windows | Visual Studio 2008, 2010, 2012, 2013                       |
+---------+------------------------------------------------------------+
| Solaris | gcc 4.1+, Sun Studio 11, Sun Studio 12                     |
+---------+------------------------------------------------------------+
| AIX     | gcc 4.1+, Xlc 9, Xlc 10, Xlc 11                            |
+---------+------------------------------------------------------------+

Quick Start
===========

The following steps can be used to build package and package group
libraries, but not test drivers:

::

    cd <repository root>
    waf configure
    waf build

To also build the test drivers, use:

::

    waf build --test build

To build and run the test drivers, use:

::

``shell waf build --test run``

For additional examples, see `Quick Reference`_.

Commands and Options
====================

Waf commands can be invoked by running:

::

    waf command [options]

Waf provides the following commands, which correspond to popular
Makefile targets in open source projects:

-  ``configure``

   Configure the repository for building and installation, this command
   needs to be run only once per build configuration.

-  ``build``

   Build the libraries in the repository, including potentially building
   and running the test drivers.

-  ``install``

   Copy the libraries files, public header files, and the generated
   pkg-config files into the installation destination directory.

-  ``clean``

   Remove build artifacts but keep the configuration cache.

-  ``distclean``

   Remove build artifacts and the configuration cache.

You can view the list of options available for each command by running:
``shell waf --help`` ##Configure Command

Configure Command
-----------------

The first step in building a BDE-Style repository is to configure the
build by running ``waf configure``. This command reads the BDE metadata
files to determine the source files to build, and the appropriate
compiler and linker flags to use. This information is cached, so the
command only needs to be invoked once per build configuration. This
command **must** be invoked from the root path of the repository (the
location of the wscript file).

::

    waf configure [-t=(UFID)] [--build-type=(debug|release)] [--abi-bits=(32|64)]
                  [--library-type=(static|shared)] [--assert-level=(none|safe|safe2)]
                  [--out=<output directory>] [--prefix=<install prefix>]


Configure Options
`````````````````

- ``-t``

  Specify the build configuration using a :ref:`bde_repo-ufid`.

- ``--abi-bits`` or ``-a``

  choices: ``32`` (default), ``64``

  Control whether the build system produces 32-bit x86 (``32``) or 64-bit
  x86\_64 (``64``) object files and libraries.

- ``--assert-level``

  choices: ``none`` (default), ``safe``, ``safe2``

  Control the level of "Safe mode" builds. "Safe mode" enables additional
  debugging code in the libraries. See the component level documentation in
  ``bsls_assert.h`` for more details on Safe mode.

- ``--build-type`` or ``-b``

  choices: ``debug`` (default), ``release``

  Control whether the debug build configuration (``debug``, the default) or the
  release build configuration (``release``) will be used. Debug builds are
  unoptimized and include debugging symbols in the resulting binaries. Release
  builds are optimized and do not include debugging symbols.

- ``--library-type``

  choices: ``static`` (default), ``shared``

  Control whether the build system produces static libraries (``.a`` files) or
  shared libraries (``.so`` files). Note that shared library builds are
  currently **not supported** on windows.

- ``--out`` or ``-o``

  Specify the output directory that will contain the build artifacts and the
  configure cache. The default value is 'build'.

- ``--prefix``

  Set the installation prefix. This is the path where the ``install`` command
  install the headers and libraries by default, unless the ``--destdir`` option
  is used.

- ``--msvc_version``

  choices: "msvc 12.0", "msvc 11.0", "msvc 10.0", "msvc 9.0"

  For windows only: use either the compiler and linker provided by Visual
  Studio 2013 (msvc 12.0), 2012 (msvc 11.0), 2010 (msvc 10.0), or 2008 (msvc
  9.0). Note that by default, waf will select the most recent Visual Studio
  installation it detects.

- ``--verify``

  Perform verification of the structure of the repository.  Currently this
  option checks whether cycles exist between UORs, packages, and components.

Environment Variables
`````````````````````
Some environment variables also affect the behavior of the configure
command. By default, the configure command tries to determine a suitable
C and C++ compiler from the ``PATH`` environment variable. You can
override the compilers used by setting the ``CC`` and ``CXX``
environment variables. Other environment variables can be used to add
additional preprocessor flags, compiler flags, linker flags, and the
installation prefix.

-  ``CC``

   Set the C compiler that will be used instead of the platform default,
   e.g., CC=/usr/bin/gcc-4.8.1. Note that this environment variable is
   not applicable when building using Visual Studio on Windows; To
   select from multiple visual studio compilers installed on the system,
   use the ``--msvc_version`` option instead.

-  ``CXX``

   Set the C++ compiler that will be used instead of the platform
   default, e.g., CXX=/usr/bin/g++-4.8.1. Note that this environment
   variable is not applicable when building using Visual Studio on
   Windows; To select from multiple visual studio compilers installed on
   the system, use the ``--msvc_version`` option instead.

-  ``CFLAGS``

   Set extra C compiler options, e.g., "-O3".

-  ``CXXFLAGS``

   Set extra C++ compiler options, e.g., "-O3".

-  ``CPPFLAGS``

   Set extra preprocessor options, e.g., "-DFOO=bar".

-  ``LINKFLAGS``

   Set extra linker options, e.g., "-L/usr/local -lsome-library".

-  ``PREFIX``

   Set the installation prefix to use, if ``--prefix`` option is not
   specified. This is the directory where the ``install`` command will
   install the headers and built libraries.

Successful execution of the configure command creates a build output
sub-directory, named 'build' by default (can be set using the ``-o``
option), that will contain any future build artifacts.

.. _waf-qualified_build_config:

UFID And Qualified Build Configuration
``````````````````````````````````````

There are two ways to specify the build configuration:

-  Specify the `UFID <BDE-Style-Repository#ufid>`_ using the ``-t``
   option. For example ``-tdbg_exc_mt`` indicates a "debug
   exception-enabled multi-threading-denabled" build.

-  Using the qualified build options, such as ``--abi-bits``,
   ``--build-type``, ``--library-type``. The configuration command will
   convert these options into a UFID value.

If both the UFID (using the ``-t`` option) and some of the qualified
build options are specified, the UFID will take precedence. Note that
the universe of possible build configurations that can be specified
using the UFID is greater than that of qualified build options. For
example, debug and optimized build can both be enabled using the UFID
``dbg_opt``. However, this can not be done using the qualified build
options, because ``--build-type`` can be set to either ``debug`` or
``release`` (equivalent to optimized), but not both. This restriction is
intentional -- the qualified build options are intended to cover the
most frequently used build configurations (especially those used by
application developers), but not the exhaustive set of build
configurations.

Build Command
-------------

Once the repository has been configured, it can be built using the the
build command. This command **must** be invoked from a path within the
repository.

::

    waf build [--targets=<list of targets>] [-j <number of jobs>] [--test=(none|build|run)]
              [--test-v=<test driver verbosity level>] [--test-timeout=<test driver timeout>]
              [--show-test-out]

Build Options
`````````````

-  ``--targets``

   Restrict the list of build targets. By default, the build command
   will build all targets. You can use ``python waf list`` to get a list
   of available targets. Multiple targets can be specified via a
   comma-delimited list. For example,
   ``python waf build --target bsls,bslstl`` builds only the 'bsls' and
   'bslstl' packages (and their dependencies).

-  ``-j``

   Set the number of parallel jobs. By default, this is set to the
   number of cores available on the system.

-  ``--test``

   choices: ``none`` (default), ``build``, ``run``

   Control whether to build and run test drivers. Test drivers will not
   be built if the value is ``none``; they will be only built if the
   value is ``build``; they will be built and run if the value is
   ``run``.

-  ``--test-v``

   Set the verbosity level of the test output. The default value is 0.

-  ``--test-timeout``

   Set the timeout for running each test driver in seconds. The default
   value is 200 seconds.

-  ``--show-test-out``

   Shows the output of all test drivers. By default, only the output of
   failed tests is shown.

Build Output
````````````

The build process will create a number of sub-directories under the
build output directory:

-  ``build/c4che``

   Contain the cached build settings used by waf.

-  ``build/groups``

   Contain the built object files and library files. The relative path
   to the build output directory of each output file (source file or
   library file) is the same as the relative path of the source file or
   directory from which the output file is built.

-  ``build/vc``

   Contain a pkg-config file for each package group library.

Install Command
---------------

Once the repository has been built, it can be installed using the
install command. This command **must** be invoked from a path within the
repository.

::

    waf install

The install command copies the library files and pkg-config files
created by the build command, along with relevant header files, into the
install directory. The install directory can be specified during the
configuration phase by setting the ``PREFIX`` environment variable or
the ``--prefix`` option. If both options are specified, ``--prefix``
takes precedence.

The following directory structure will be created in the install
directory:

::

   <destination dir>
    |
    `-- include
    |   |
    |   |-- bsls_util.h
    |   |-- ...                    <-- installed header files
    `-- lib
        |
        |-- libbsl.a
        |-- ...                    <-- installed libraries
        |
        `-- pkgconfig
            |
            |-- bsl.pc
            `-- ...                <-- pkg-config files for each lib

.. _waf-pkgconfig:

Handling External Dependencies Using Pkg-config
===============================================

The dependencies of a package group are specified in the
:ref:`bde_repo-dep`. By default, waf will look for the dependencies of a
:ref:`UOR <bde_repo-uor>` as other UORs within the repository. Failing that,
waf will attempt to resolve the dependency using `pkg-config
<http://www.freedesktop.org/wiki/Software/pkg-config>`_.  This process has the
following benefits:

1. Allow third party dependencies to be specified in the same way as
   internal dependencies.

2. Allow a single source repo to be easily split into multiple repos, without
   requiring any change to the BDE metadata.  Once a repo is split into two,
   building the high-level repo requires the lower-level repo be first
   installed.

The freedesktop site has a `guide
<http://people.freedesktop.org/~dbn/pkg-config-guide.html>`_ to explain how
pkg-config works. For pkg-config to find an explicit dependency, a ``pc`` file
of that dependency must be located in the path pointed to by the
``PKG_CONFIG_PATH`` environment variable.

For example, suppose you want the package group ``foo`` to depend on Open
SSL. First, you need to install Open SSL on the system.  Then, you need to
point ``PKG_CONFIG_PATH`` to the path containing ``openssl.pc``. Finally, you
need to add ``openssl`` as a dependency to ``foo.dep``. After these three
steps, waf will automatically determine the build flags required to use Open
SSL at configuration time.

.. _waf-workspace:

Building Multiple Repos Using Workspaces
========================================

You have 2 options to work with multiple BDE-style repositories:

1. Install the lower-level libraries first, and build higher level libraries by
   resolving their dependencies using pkg-config (see :ref:`waf-pkgconfig`).

2. The simpler option is to use workspaces, which allows you to build multiple
   BDE-style repositories in the same way as a single repository by using the
   workspace feature.

To use the workspace feature, first, create a workspace directory and check out
the repositories that you want to store in the workspace. Then, simply add an
(empty) file named ``.bdeworkspaceconfig`` and copy ``bde-tools/etc/wscript``.

See :ref:`tutorials-workspace` for an example.

.. _waf-windows:

Building on Windows
===================

Waf can be used on the windows command prompt in the same way as it can
be used on Unix platforms. You can select the version of Visual Studio
compiler to use at configuration time using the ``--msvc_version``
option.

An important curiosity is that the Visual Studio command line compiler
uses /MT by default, which statically links the C Runtime. This is
different than the IDE, which uses /MD by default (dynamically linking
the C Runtime). The two cannot be mixed. Therefore, if you want to
ensure that BDE dynamically loads the C Runtime, be sure to set your
CXXFLAGS environment variable as follows:

::

    set CXXFLAGS=/MD
    waf configure
    waf build

*Important*: You should use a *regular* command prompt (cmd.exe) instead
of the command prompt provided by a specific version of Visual Studio,
because waf can be configured to use a version of Visual Studio
different from the one supported by the that command prompt.

Building using cygwin's gcc compiler is not supported. However, you can work in
the cygwin environment, but still use the Visual Studio compiler by invoking
using the provided shell script ``bin/cygwaf.sh``.

To use ``cygwaf.sh``, you must export the WIN_PATH environment variable to
point to the *cygwin* path of the *Windows* version of Python.

For example, if the Windows version of CPython is installed to #
C:\Python27\python, then you can use the following command to set up the
required environment variable:

::

   $ export WIN_PYTHON=/cygdrive/c/Python27/python
   $ cygwaf.sh <waf command>

Waf also can be used to generate a Visual Studio solution by running the waf
commands 'msvs' or 'msvs2008'. The 'msvs' command generates a Visual Studio
2010 solution named project.sln, and 'msvs2008' generates a Visual Studio
solution named project\_2008.sln.

The generated Visual Studio solution still uses waf as the back-end for
compiling and linking, so it simply serves as an alternate interface
from running waf directly on the command line.

Building on OSX
===============

Waf can be used to generate a xcode project by running the waf command
'xcode'. This command generates a Xcode project named
foldername.xcodeproj, where 'foldername' is the name of root directory
of the source repository.

The generated Xcode project still uses waf as the backend for compiling
and linking, so it simply serves as an alternate interface from running
waf directly on the command line.


Quick Reference
===============

Below are examples of build options that are frequently useful during
development:

::

    cd bde
    $ waf --help                        # Help information (all the options
                                        # shown below are documented)

    $ waf build                         # Build the entire repository
    $ waf build --targets bsl           # Build the bsl package-group
    $ waf build --targets bsls          # Build the bsls package
    $ waf build --targets bsls_atomic.t # Build the bsls_atomic component

    $ waf build --targets bsls --test build
                                        # Build all the components and test
                                        # drivers in bsls

    $ waf build --targets bsls_atomic.t --test run
                                        # Build and run the tests for bsls_atomic

    $ waf build --targets bsls_atomic.t --test run --show-test-out --test-v 2
                                        # Build and run the test, show the test
                                        # output with verbosity 2

    $ waf step --files='groups/bsl/bslstl/.*\.cpp'
                                            # Force rebuild files in bslstl.  Note
                                            # that --files takes a regular expression
                                            # to the relative path of the files.
