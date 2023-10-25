.. _bbs_build-top:

=========
bbs_build
=========

Introduction
============

``bbs_build`` is a wrapper script that simplifies invocation of the ``cmake``
and provides simple command line interface to the BBS build system.

More specifically, the tool handles the following aspects of the build process:

1. Creates/selects the build directory for current build configuration.

2. Selects the compiler and sets up arguments passed to the compiler.

3. Sets a compiler configuration under Windows OS.

4. Sets/passes necesssary parameters to the ``cmake``.

``bbs_build`` knowns the environment variables set by the
:ref:`bbs_build_env <bbs_build_env-top>` and will pick up those parameters
from the environment if they are not specified in the command line.

Command line 
============

.. note::
   The code samples below assume that the path to the ``bbs_build`` script
   is added to the ``PATH`` environment variable.

Full set of supported parameters can be listed by running::

  bbs_build --help

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

   .. note::
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

   Unified Flag IDentifier (e.g. "opt_64_cpp17"). 

   .. note::
      If the parameter is not specified, the value is taken from the
      ``BDE_CMAKE_UFID`` environment variable.

.. option:: -G GENERATOR

   Select the build system for compilation.

   .. note::
      If the parameter is not specified, the script will choose the 
      low-level build system (default is ``ninja``).

.. option:: --toolchain TOOLCHAIN

   Path to the CMake toolchain file. See `CMake Toolchains
   <https://cmake.org/cmake/help/v3.10/manual/cmake-toolchains.7.html>`_ for
   more details on the format of the Cmake toolchain file.

   .. note::
      If the parameter is not specified, the script will try to find the
      generic compiler toolchain file or use the CMake defaults, if no 
      toolchain file is found.

.. option:: --compiler COMPILER

   Specifies the compiler (Windows only). Currently supported compilers are:
   ``msvc-2022``, ``msvc-2019`` and ``msvc-2017``. Latest detected version will
   be set as a default.

.. option:: --refroot REFROOT

   Path to the distribution refroot.

   .. note::
      If the parameter is not specified, the value is taken from the
      ``DISTRIBUTION_REFROOT`` environment variable.

.. option:: --prefix PREFIX

   The path prefix in which to look for dependencies for this buils. If
   ``--refroot`` is specified, this prefix is relative to the refroot
   (default="/opt/bb"). 
   
   .. note::
      This parameter also defines the installation prefix for install 
      command.

.. option:: --clean

   Clean the specified build directory before configuration.

   .. important::
      Compiler-specific configuration is generated only on initial
      configuration and cached by the build system. User must use
      empty (clean) build directory when switching compilers.

Parameters for build command
----------------------------

.. option:: --targets TARGET_LIST

   Specifies the list of comma separated build targets. There are targets for
   package groups (bsl/bsl.t), packages (bdlt/bdlt.t) and individual components
   (ball_log/ball_log.t) and well as high-level target for building everything
   (all/all.t)

.. option:: --test {build, run}

   Selects whether to build or run the tests. Tests are not built by default.
   build step.

.. option:: --timeout TIMEOUT

   Specifies the maximum time to run a single test driver. The test driver is
   terminated if it does not complete within the specified timeout (in
   seconds).

.. option:: -k, --keep-going

   Continues as much as possible after an error.

   .. note::
      Supported by 'ninja' and 'make' build systems.

.. option:: --xml-report

   Generate xml report when running tests. Reports can be found in the
   ``<build_dir>/Testing`` folder.

Available targets
-----------------

.. csv-table::
   :header: "Target", "Description"
   :widths: 40, 60
   :align: left

   "help", "List all of the available targets"
   "all", "Build all libraries and application UORs (except tests)"
   "all.t", "Build all UORs and their test drivers"
   "<uor>", "Build the specified UOR (except tests)"
   "<uor>.t", "Build the specified UOR and its test driver"
   "<package_name>", "Build the specified package (except tests)"
   "<package_name>.t", "Build the specified package and its test driver"
   "<component_name>.t", "Build the specified component's test driver"
   "check_cycles", "Verify the workspace for implementation and test cyclic dependencies"
   "<uor>.check_cycles", "Verify the specified OUR for implementation and test cyclic dependencies"
   "clean", "Remove currently configure build folder"

Parameters for install command
------------------------------

.. option:: --component COMPONENT

   The name of the component to install. This flag should be used only by the
   builds helper that do BDE library packaging. When not specified, the command
   installs headers and libraries for all UORs defined in the repo.

.. option:: --install_dir INSTALL_DIR

   Path to the top level installation directory.
