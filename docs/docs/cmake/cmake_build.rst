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

   Specifies the path to the build directory.

   .. tip::
      If the parameter is not specfied, the value is taken from the
      ``BDE_CMAKE_BUILD_DIR`` environment variable.

.. option:: -j N, --jobs N

   Specifies the number of parallel jobs that can be spawned by the build system.

.. option:: -v, --verbose

   Increase the verbosity of the output.

.. option:: -h, --help

   Print the help page.

Configure parameters
--------------------

Those parameters are used by ``configure`` command.

.. option:: -u UFID, --ufid UFID

   Specifies the build flavor of the BDE libraries.

   .. tip::
      If the parameter is not specfied, the value is taken from the
      ``BDE_CMAKE_UFID`` environment variable.

.. option:: -G GENERATOR

   Specifies the low-level build system that should be used by CMake.

   .. tip::
      If the parameter is not specified, the script will choose the 
      low-level build system (default is ``ninja``).

.. option:: --dpkg-build

   This option selects the toolchain that is used to produce production
   versions of the BDE libraries.

   .. tip::
      This parameter overrides the ``--compiler`` and ``--toolchain`` 
      parameters.
      
.. option:: --toolchain TOOLCHAIN

   Specifies the path to the CMake toolchain file. See `CMake Toolchains
   <https://cmake.org/cmake/help/v3.10/manual/cmake-toolchains.7.html>`_
   for more details on the format of the Cmake toolchain file.

   .. tip::
      If the parameter is not specified, the script will try to find the
      generic compiler toolchain file or use the CMake defaults, if no 
      toolchain file is found.


.. option:: --compiler COMPILER

   Specifies the compiler from the list of the configured compilers. 
   See :ref:`Configure system compilers <tutorial-compiler-config>` for more
   information.

.. option:: --refroot REFROOT

   Specifies path to the distribution refroot.

.. option:: --prefix PREFIX

   Specifies prefix within ether distribution refroot. Within Bloomberg 
   development environment, this is normally set to ``/opt/bb/``.

Build parameters
----------------

.. option:: --targets TARGET_LIST

   Specifies the list of build targets. See :ref:`Build targets
   <build_system_design-build-targets>` for more information.

.. option:: --test {build, run}

   Instructs the build command build or run BDE test drivers as part of the
   build step.

.. option:: --timeout TIMEOUT

   Specifies the maximum time to run a single test driver. The test driver is
   terminated if it does not complete within the specified timeout (in
   seconds).

Install parameters
------------------

.. option:: --component COMPONENT

   Specifies the install component name. See :ref:`Install components
   <build_system_design-install-components>` for more information.

.. option:: --install_dir INSTALL_DIR

   Specifies the top level installation directory.

.. option:: --install_prefix INSTALL_PREFIX

   Specifies the intall prefix within the installation directory.
