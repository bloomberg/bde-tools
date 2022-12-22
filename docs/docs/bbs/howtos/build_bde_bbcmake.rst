.. _bbs-build-bde-bbcmake-top:

----------------------
Build BDE with bbcmake
----------------------

This build mode allow user to use production compilers and toolchains to build
BDE libraries. The set of configurations for this build mode is normally limited
to the configurations used in production.

Download BDE library
--------------------

* Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

.. code-block:: shell

   $ git clone bbgithub:bde/bde

Setup distribution refroot
--------------------------

* Create a refroot with the build dependencies necessary to build BDE
  library:

.. code-block:: shell

   $ export DISTRIBUTION_REFROOT=${PWD}/refroot
   $ refroot-install --config bde/debian/control --arch amd64 --refroot-path ${DISTRIBUTION_REFROOT} --yes

Configure, build and test BDE 
-----------------------------

* Create build folder

.. code-block:: shell
     
   $ cd bde
   $ mkdir _build; cd _build

* Configure the Cmake build system:

.. code-block:: shell
    
   $ plocum bbcmake .. -64 -DBBS_BUILD_SYSTEM=ON

.. note::
   ``plocum`` is an internal command that executes the command on the build
   farm. This is a preferred way of running computation intensive tasks
   on the shared development mashines.

The use of ``-DBBS_BUILD_SYSTEM=ON`` marker is temporary and will not be
required once BBS will become BDE primary build system.

* Build BDE libraries:

.. code-block:: shell

   $ plocum cmake --build .

* Build and run BDE tests:

.. code-block:: shell

   $ plocum cmake --build . --targets all.t
   $ plocum ctest 

