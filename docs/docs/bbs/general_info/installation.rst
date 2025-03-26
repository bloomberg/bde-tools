.. _bbs-install-top:

------------------------------
Installation And Configuration
------------------------------

Prerequisites
-------------

Bde build system expects following software to be preinstalled and configured
on the system:

  * `CMake <https://cmake.org/>`_ (version 3.19 or later)
  * `Ninja <https://ninja-build.org/>`_ (recommended) or `GNU Make
    <https://www.gnu.org/software/make/>`_
  * C++ compilers (gcc, clang)
  * Perl (optional). Required only for code generation.
  * Python (version 3.8 or later)

See the :doc:`requirements` for details.

Download BDE tools
------------------

{{{ internal
* Clone the `bde-tools <https://bbgithub.dev.bloomberg.com/bde/bde-tools>`_
  repository:

  .. code-block:: Bash

     $ git clone bbgithub:bde/bde-tools
}}}

{{{ oss
* Clone the `bde-tools <https://github.com/bloomberg/bde-tools>`_
  repository:

.. code-block:: Bash

   $ git clone https://github.com/bloomberg/bde-tools.git
}}}

* Add the ``<bde-tools>/bin`` to the ``PATH`` environment variable:

.. code-block:: Bash

   $ export PATH=<bde-tools>/bin:$PATH

.. note::
      Instead of adding ``bde-tools/bin`` to your ``PATH``, you can also execute
      the scripts from directly from ``bde-tools/bin`` folder.

{{{ internal
.. important::
   Bloomberg general development machines have the tools installed in
   ``/bb/bde/bbsh/bde-tools``.
}}}


Check detected compilers
------------------------
After installing bde-tools, you can verify the build system installation by
listing the compilers that are found on the host:

.. code-block:: Bash

   $ bbs_build_env list

In most cases, the tool will list compilers currently installed in the system
without any additional configuration.

For custom compilers installation or custom toolchain, please See :doc:`../howtos/configure_profile`

Congratulations! BBS build system  is complete and is ready to use.

