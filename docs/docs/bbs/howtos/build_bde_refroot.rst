.. _bbs-build-bde-refroot-top:

----------------------
Build BDE with refroot
----------------------
This build mode allow user to use production compiler and toolchains to build
BDE libraries. The set of configurations for this build mode is normally
limited to the configurations used in production.

Download BDE library
--------------------
* Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

.. code-block:: shell

   $ git clone bbgithub:bde/bde

Setup distribution refroot
--------------------------

* Create a refroot with the build dependencies necessary to build BDE library:

.. code-block:: shell

   $ export DISTRIBUTION_REFROOT=${PWD}/refroot
   $ refroot-install --config bde/debian/control --arch amd64 --refroot-path ${DISTRIBUTION_REFROOT} --yes

Check production build profiles
-------------------------------
BBS build system should detect production toolchains that will be used for the
build.

* This following command will list detected profiles. First 2 profiles, named
  "BBToolchain64/32" respectively should appear in the list of profiles:

.. code-block:: shell

      $ bbs_build_env list

      Available profiles:
      0: BBToolchain64 (default)
         Toolchain:     /<refroot_path>/opt/bb/share/plink/BBToolchain64.cmake
         Properties:    {'noexc': False, 'bitness': 64, 'standard': 'cpp20', 'sanitizer': False, 'assert_level': 'default', 'review_level': 'default'}
         Description:   Production toolchain for dpkg builds, 64-bit.

      1: BBToolchain32
         Toolchain:     /<refroot_path>/opt/bb/share/plink/BBToolchain32.cmake
         Properties:    {'noexc': False, 'bitness': 32, 'standard': 'cpp20', 'sanitizer': False, 'assert_level': 'default', 'review_level': 'default'}
         Description:   Production toolchain for dpkg builds, 32-bit.

Configure, build and test BDE 
-----------------------------

* Select the build profile and build type:

.. code-block:: shell
     
   $ cd bde
   $ eval `bbs_build_env -u opt`

.. note::
   Note that production toolchains fix all aspects of the compiler invocation
   and the user can effectively select only CMAKE_BUILD_TYPE.

.. note::
   Note that the actual active ufid used by the build system can differ from
   the ufid specified in the command line.  Inspect information printed by the
   ``bbs_build_env`` for the actual ufid.

* Configure and build BDE libraries:

.. code-block:: shell
     
      $ bbs_build configure build
