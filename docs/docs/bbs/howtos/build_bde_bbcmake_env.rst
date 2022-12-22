.. _bbs-build-bde-bbcmake-env-top:

--------------------------
Build BDE with bbcmake-env
--------------------------
This build mode is a simplified version of the bbcmake build which
automatically deploys all production build dependencies from the dpkg metadata.

See `bbcmake-env <https://bbgithub.dev.bloomberg.com/pages/cmake-community/bbcmake-env/>`_
documentation for more information on using this tool.

Download BDE library
--------------------
* Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

.. code-block:: shell

   $ git clone bbgithub:bde/bde
   $ cd bde

Build BDE
---------
* Configure build

.. code-block:: shell

   $ plocum bbcmake-env -64 -S . -DBBS_BUILD_SYSTEM=ON

.. note::

   ``plocum`` is an internal command that executes the command on the build
   farm. This is a preferred way of running computation intensive tasks
   on the shared development mashines.

* Inspect the build configuration

.. code-block:: shell

   $ plocum bbcmake-env -64 -S . --info

* Build BDE libraries

.. code-block:: shell

   $ plocum bbcmake-env -64 -S . --action build -DBBS_BUILD_SYSTEM=ON

* Build test BDE targets (by passing the test target names to the ``--action``
  parameter):

.. code-block:: shell

   $ plocum bbcmake-env -64 -S . --action build:all.t -DBBS_BUILD_SYSTEM=ON

The use of ``-DBBS_BUILD_SYSTEM=ON`` marker is temporary and will not be
required once BBS will become BDE primary build system.

* Test BDE

.. code-block:: shell

   $ plocum bbcmake-env -64 -S . --action ctest -DBBS_BUILD_SYSTEM=ON

.. note::

   See ``bbcmake-env`` help for passing ctest options to limit the set of test
   driver to run. BDE test drivers use test labels (``-L`` ctest parameter)
   matching the group, package or component name with ``.t`` suffix: ``bal.t``,
   ``bdlt.t``, ``bsls_platform.t``.

Instrumented build
------------------
``bbcmake-env`` provide an ability to select a community toolchain for drop-in
instrumented analysis configurations on top of the standard bloomberg toolchain:

.. code-block:: shell

   $ plocum bbcmake-env -64 -S .  --action build:all.t -DBBS_BUILD_SYSTEM=ON 
     -DCMAKE_BUILD_TYPE=Coverage --bbtoolchain BBInstrumentationToolchain

.. note::

   The refroot used for such builds must contain intrumentation toolchains.
