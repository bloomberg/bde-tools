.. _build-config-top:

==============================
Installation And Configuration
==============================

.. important::

    This tutorial outlines initial installation and configuration of the BDE
    build system outside of Bloomberg development environment.

.. _build-config-overview:

Prerequisites
-------------

BDE CMake build system requires following software to be preinstalled and
configured on the system:

 * `CMake <https://cmake.org/>`_ (version 3.10 or later)
 * `Ninja <https://ninja-build.org/>`_ (recommended) or `GNU Make
   <https://www.gnu.org/software/make/>`_
 * Python
 * pkg-config (to compile with third-party libraries)

Download BDE tools
------------------

* Clone the `bde-tools <https://bbgithub.dev.bloomberg.com/bde/bde-tools>`_
  repository:

  ::

    $ git clone https://bbgithub.dev.bloomberg.com/bde/bde-tools.git

* Add the ``<bde-tools>/bin`` to the ``PATH`` environment variable:

  ::

    $ export PATH=<bde-tools>/bin:$PATH

  .. note::
    Instead of adding ``bde-tools/bin`` to your ``PATH``, you can also execute
    the scripts from ``bde-tools/bin`` directly.

.. _build-compiler-config:

Configure system compilers
--------------------------

* Configure the compilers available on your system in a
  ``~/.bdecompilerconfig``.  Example configuration file:

  :: 

    [
        {
            "uplid": "unix-linux-",
            "compilers": [
                {
                    "type":      "gcc",
                    "c_path":    "/opt/gcc-5.4.0/bin/gcc",
                    "cxx_path":  "/opt/gcc-5.4.0/bin/g++",
                    "version":   "5.4.0",
                    "toolchain": "gcc-default"
                },
                {
                    "type":      "clang",
                    "c_path":    "/opt/clang-7.0/bin/clang",
                    "cxx_path":  "/opt/clang-7.0/bin/clang++",
                    "version":   "7.0",
                    "toolchain": "clang-default"
                }
            ]
        },
        {
            "uplid": "unix-darwin-",
            "compilers": [
                {
                    "type":      "clang",
                    "c_path":    "/usr/bin/clang",
                    "cxx_path":  "/usr/bin/clang++",
                    "version":   "5.1.0",
                    "toolchain": "clang-default"
                }
            ]
        }
    ]

  .. note::

    First compiler specified in the configuration file will be used by
    the build scripts as a default compiler.

  .. note::

    Default toolchains provided with the build system can be found in the
    ``<bde-tools>/cmake/toolchains`` directory.

  .. note::

    System ``bdecompilerconfig`` provided for the Bloomberg development
    environment can be found in ``/bb/bde/bbshr/bde-internal-tools/etc/``
    folder. The config placed into the home directory will override the system
    compiler config.

* Verify the compiler configuration:

  ::

    $ bde_build_env.py list

Download BDE library
--------------------

* Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

  ::

    $ git clone https://bbgithub.dev.bloomberg.com/bde/bde.git
    $ cd bde

Set build environment
---------------------

* This command sets environment variables that define effective ufid/uplid,
  compiler and build directory for subsequent commands:

  ::

    $ eval `bde_build_env.py -t <ufid> -c <compiler>`

  .. note::
    Please refer to :ref:`bde_repo-ufid`

Configure and build BDE
-----------------------

* Configure the Cmake build system:

  ::
  
    $ cmake_build.py configure

* Build BDE libraries:

  ::

    $ cmake_build.py build

  .. note::
    Please refer to :ref:`build-examples-top` for advanced build scenarios.
