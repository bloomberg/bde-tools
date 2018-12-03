.. _cmake_build-top:

==============
cmake_build.py
==============

Introduction
============

``cmake_build.py`` is a wrapper script that simplifies invocation of the
``cmake`` and provides simple command line interface to the BDE build
system.

More specifically, the tool handles the following aspects of the build process:

1. Creates/selects the build directory for current build configuration.

2. Selects the compiler and sets up arguments passed to the compiler.

3. Sets a compiler configuration under Windows OS.

4. Sets/passes necesssary parameters to the ``cmake``.

``cmake_build.py`` knowns the environment variables set by the
:ref:`bde_build_env.py <bde_build_env-top>` and will pick up those parameters
from the environment if they are not specified in the command line.

Command line 
============

.. note::
   The code samples below assume that the path to the ``cmake_build.py`` script
   is added to the ``PATH`` environment variable.

Full set of supported parameters can be listed by running::

  cmake_build.py --help

Commands
--------

.. option:: configure

   Perform Cmake configuration step. During this step the build directory is
   created and low-level build system make files are generated.

.. option:: build

   Perform build step. During this step the BDE libraries and (optionally) test
   drivers are compiled, linked and (optionally) test drivers are executed.

.. option:: install

   Perform installation step. During this step the build artefacts are
   installed into user specified location.


Common parameters
-----------------

.. option:: --build_dir BUILD_DIR

   Path to the build directory.

   .. tip::
      If the parameter is not specfied, the value is taken from the
      ``BDE_CMAKE_BUILD_DIR`` environment variable. If environment variable is
      not set, the build system generates the name using the current platform,
      compiler, and ufid. The generated build directory looks like:
      ``./_build/unix-linux-x86_64-2.6.32-gcc-5.4.0-opt_exc_mt_cpp11``

.. option:: -j N, --jobs N

   Specify number of jobs to run in parallel.

.. option:: -v, --verbose

   Produce verbose output. 

.. option:: -h, --help

   Print the help page.

Parameters for configure command
--------------------------------

Those parameters are used by ``configure`` command.

.. option:: -u UFID, --ufid UFID

   Unified Flag IDentifier (e.g. "opt_exc_mt"). 

   .. tip::
      If the parameter is not specified, the value is taken from the
      ``BDE_CMAKE_UFID`` environment variable.

.. option:: -G GENERATOR

   Select the build system for compilation.

   .. tip::
      If the parameter is not specified, the script will choose the 
      low-level build system (default is ``ninja``).

.. option:: --dpkg-build

   This option selects the toolchain that is used to produce production
   versions of the BDE libraries.

   .. tip::
      This parameter overrides the ``--compiler`` and ``--toolchain`` 
      parameters.

   .. warning::
      This option should be used only when building release dpkg packages.
      
.. option:: --toolchain TOOLCHAIN

   Path to the CMake toolchain file. See `CMake Toolchains
   <https://cmake.org/cmake/help/v3.10/manual/cmake-toolchains.7.html>`_ for
   more details on the format of the Cmake toolchain file.

   .. tip::
      If the parameter is not specified, the script will try to find the
      generic compiler toolchain file or use the CMake defaults, if no 
      toolchain file is found.

.. option:: --compiler COMPILER

   Specifies the compiler (Windows only). Currently supported compilers are:
   ``cl-18.00``, ``cl-19.00``, and ``cl-19.10``.

.. option:: --refroot REFROOT

   Path to the distribution refroot.

   .. tip::
      If the parameter is not specified, the value is taken from the
      ``DISTRIBUTION_REFROOT`` environment variable.

.. option:: --prefix PREFIX

   The path prefix in which to look for dependencies for this buils. If
   ``--refroot`` is specified, this prefix is relative to the refroot
   (default="/opt/bb").

.. option:: --clean

   Clean the specified build directory before configuration.

   .. important::
      Compiler-specific configuration is generated only on initial
      configuration and cached by the build system. User must use
      empty (clean) build directory with switching compilers.

Parameters for build command
----------------------------

.. option:: --targets TARGET_LIST

   Specifies the list of build targets. See :ref:`Build targets
   <build_system_design-build-targets>` for more information.

.. option:: --test {build, run}

   Selects whether to build or run the tests. Tests are not built by default.
   build step.

.. option:: --timeout TIMEOUT

   Specifies the maximum time to run a single test driver. The test driver is
   terminated if it does not complete within the specified timeout (in
   seconds).

.. option:: -k, --keep-going

   Continues as much as possible after an error.

   .. tip::
      Supported by 'ninja' and 'make' build systems.

Parameters for install command
------------------------------

.. option:: --component COMPONENT

   The name of the component to install. See :ref:`Install components
   <build_system_design-install-components>` for more information.

.. option:: --install_dir INSTALL_DIR

   Path to the top level installation directory.

.. option:: --install_prefix INSTALL_PREFIX

   The install prefix within the installation directory.
