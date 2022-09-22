.. _bbs-config-top:

------------------------------
Installation And Configuration
------------------------------

.. important::

    This tutorial outlines initial installation and configuration of the BDE
    build system outside of Bloomberg development environment.

.. _bbs-config-overview:

Prerequisites
-------------
  BBS build system requires following software to be preinstalled and
  configured on the system:

    * `CMake <https://cmake.org/>`_ (version 3.22 or later)
    * `Ninja <https://ninja-build.org/>`_ (recommended) or `GNU Make
      <https://www.gnu.org/software/make/>`_
    * Python (version 3.8 or later)

Download BDE tools
------------------

{{{ internal
  * Clone the `bde-tools <https://bbgithub.dev.bloomberg.com/bde/bde-tools>`_
    repository:

    ::

      $ git clone bbgithub:bde/bde-tools
}}}
{{{ oss
  * Clone the `bde-tools <https://github.com/bloomberg/bde-tools>`_
    repository:

    ::

      $ git clone https://github.com/bloomberg/bde-tools.git
}}}

  * Add the ``<bde-tools>/bin`` to the ``PATH`` environment variable:

    ::

      $ export PATH=<bde-tools>/bin:$PATH

    .. note::
       Instead of adding ``bde-tools/bin`` to your ``PATH``, you can also execute
       the scripts from ``bde-tools/bin`` directly.

.. _bbs-compiler-config:

Configure system compilers
--------------------------
  After installing bde-tools, you can list the compilers that are found by
  the tool:

     ::

       $ bbs_build_env.py list

  In most cases, the tool will list compilers currently installed in the system
  without any additional configuration.

  For custom compilers installation or custom toolchain, please See
  {Configuring a custom build profile (TBD)}


Download BDE library
--------------------

{{{ internal
  * Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

    ::

      $ git clone bbgithub:bde/bde
      $ cd bde
}}}
{{{ oss
  * Clone the `bde <https://github.com/bloomberg/bde>`_ repository:

    ::

      $ git clone https://github.com/bloomberg/bde.git
      $ cd bde
}}}

Set build environment
---------------------

  * This following command will configure the build environment to use first
    compiler from the list and will select "Debug" build type:

    ::

      $ eval `bbs_build_env.py`

    This command is equivalent to the following command:
    ::

      $ eval `bbs_build_env.py -p 0 -u dbg`

Configure, build and test BDE 
-----------------------------

  * Configure the Cmake build system:

    ::
    
      $ bbs_build.py configure

  * Build BDE libraries:

    ::

      $ bbs_build.py build

  * Build and run BDE tests:

    ::

      $ bbs_build.py build --tests run

  * Install BDE headers and libraries:

    ::

      $ bbs_build.py install

