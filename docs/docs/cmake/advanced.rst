.. _build-advanced-top:

=======================
Advanced Build Examples
=======================

Scenarios shown below are valid only within Bloomberg development environment.

Refroot
-------

BDE build system can build libraries and application that depend on externally
provided, pre-built libraries via refroot mechanism. Refroot (reference root)
is essentially a folder which contains a set of headers, libraries
and tools that closely match the production environment.

Refroot is created by installing the packages listed in the command line
(multiple packages can be specified in a single command):

  ::

    $ refroot-install --refroot-path=<path> --arch=<arch> --package <package>

Refroot can also be created by automatically extracting build dependencies from
the package:

  ::

    $ refroot-install --refroot-path=<path> --arch=<arch> --build-depends <package>

.. _build-advanced-1:

Example 1. Building ``hsl``
---------------------------

``hsl`` is a HyperSheet Language library provided by BDE team.
In order to build this library against pre-compiled BDE libraries, you need to
do the following steps:

* Create a refroot and install all external dependencies of the ``hsl`` library:

  ::

    $ refroot-install --refroot-path=/bb/data/tmp/${USER} --arch=amd64 --build-depends hsl --yes

  .. note::
    Note that this form of ``refroot-install`` command will extract and install all
    build dependencies of the specified package. 

* Clone ``hsl`` source:

  ::

    $ git clone bbgithub:bde/hsl
    $ cd hsl

* Configure the build system:

  ::

    $ eval `bde_build_env.py -t opt_exc_mt_64_cpp11`
    $ cmake_build.py configure --refroot=/bb/data/tmp/${USER} -v

* Build the library and run all test drivers:

  ::

    $ cmake_build.py build --tests run

  .. note::
    Note that ``hsl`` can be also build as part of the workspace. See
    :ref:`build-examples-5` for details.

.. _build-advanced-2:

Example 1. Building ``a_cdb2``
------------------------------

The ``a_cdb2`` adapter allows access to comdb2 databases from C++ without a
bbenv.

The process of building ``a_cdb2`` adapter is principally identical to building
any other source repository with external dependencies.

* Create a refroot and install all external dependencies of the ``a_cdb2``
  library:

  ::

    $ refroot-install --refroot-path=/bb/data/tmp/${USER} --arch=amd64 --build-depends a-cdb2 --yes

  .. note::
    Note the ``a-cdb2`` in the command line of the ``refroot-install`` command.
    The exact name of the dpkg source package name can be found in the ``debian/control``
    file of the source repository ( ``Source`` line ).

* Clone ``a_cdb2`` source:

  ::

    $ git clone bbgithub:bde/a_cdb2
    $ cd a_cdb2

* Configure the build system:

  ::

    $ eval `bde_build_env.py -t opt_exc_mt_64_cpp11`
    $ cmake_build.py configure --refroot=/bb/data/tmp/${USER} -v

* Build the library and run all test drivers:

  ::

    $ cmake_build.py build --tests run
