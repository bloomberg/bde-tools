.. _cmake-tutorial-top:

==================
BDE CMake Tutorial
==================

.. important::

    This tutorial outlines initial installation and configuration of the BDE
    build system outside of Bloomberg development environment.

.. _cmake-tutorial-overview:

Prerequisites
-------------

BDE CMake build system requires following software to be installed on the
system:

 * `CMake <https://cmake.org/>`_ (version 3.10 or later)
 * `Ninja <https://ninja-build.org/>`_ or `GNU Make
   <https://www.gnu.org/software/make/>`_
 * Python

Download BDE tools
------------------

* Clone the `bde-tools <https://github.com/bloomberg/bde-tools>`_ repository
  from `github <https://github.com/bloomberg/>`_:

  ::

    $ git clone https://github.com/bloomberg/bde-tools.git

* Add the ``<bde-tools>/bin`` to the ``PATH`` environment variable:

  ::

    $ export PATH=<bde-tools>/bin:$PATH

  .. note::

    Instead of adding ``bde-tools/bin`` to your ``PATH``, you can also execute
    the scripts in ``bde-tools/bin`` directly.

Download BDE library
--------------------

* Clone the `bde <https://github.com/bloomberg/bde>`_ repository from `github
  <https://github.com/bloomberg/>`_:

  ::

    $ git clone https://github.com/bloomberg/bde.git


.. _tutorial-compiler-config:

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
                    "type":     "gcc",
                    "c_path":   "/opt/gcc-5.4.0/bin/gcc",
                    "cxx_path": "/opt/gcc-5.4.0/bin/g++",
                    "version":  "5.4.0"
                },
                {
                    "type":     "clang",
                    "c_path":   "/opt/clang-7.0/bin/clang",
                    "cxx_path": "/opt/clang-7.0/bin/clang++",
                    "version":  "7.0"
                }
            ]
        }
    ]

  .. note::

    First compiler specified in the configuration file will be used by
    the build scripts as a default compiler.

* Verify the compiler configuration:

  ::

    $ bde_build_env.py list

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
  
