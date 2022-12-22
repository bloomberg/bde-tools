.. _bbs-different-compiler-top:

-------------------------------------------
Use a Non-Standard Compiler or Build Option
-------------------------------------------

A common task is to need to build BDE (or another
:doc:`BDE-style<../reference/bde_repo_layout>` repository) with a non-standard
compiler or build options.

.. warning::

   Production software should not be built using a non-standard compiler or build options.

Most common compilers and build options and should be configured using ``-p`` and ``-u``
options to :doc:`../tools/bbs_build_env` or by command line options
to :doc:`../tools/bbs_build`. ``bbs_build_env list`` will provide a list of detected \
compilers.  Common build options are documented as :ref:`UFIDs<ufid>`.

For compilers that will be used regularly, users can
:doc:`create a custom compiler profile<configure_profile>`.

Using ``CXX`` and ``CXXFLAGS``
------------------------------

For experimental builds using non-default compiler installations or non-standard option
the simplest approach is to use the standard ``CMake`` environment variables like
``CC``, ``CXX``, and ``CXXFLAGS``.

For example:

.. code:: shell
          
   $ eval `bbs_build_env`
     Using system configuration: /somewhere/bbs_build_profiles   
     Effective ufid: dbg
     Using build profile: gcc-10.2.1
     Using install directory: /somewhere/else/bde/_install
   
   $ export CXX=/unusual/compiler/location/compiler
   $ export CXXFLAGS=-fcoroutines
   $ bbs_build configure build

The example above overides the compiler being used to be
``/unusual/compiler/location/compiler``, and passes the ``-fcorourtines`` option
via the compiler command line.

.. note::

   :doc:`../tools/bbs_build_env` will overwrite existing variables you have set.
          
Observering Compiler Command Lines
----------------------------------

The ``-v`` (verbose) option to :doc:`../tools/bbs_build` will print the command
line to the console, allowing us to verify the compiler and build options are being
used correctly.

.. code:: shell

   $ bbs_build build -v
   ...
   [376/1436] /unusual/compiler/location/compiler -DBDE_BUILD_TARGET_DBG -I/somewhere/bde/groups/bsl/bsls ... -fcoroutines ... -c /somewhere/bde/groups/bsl/bsls/bsls_systemtime.cpp
