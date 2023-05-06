.. _bbs-setup-build-top:

-------------------
Setup and Build BDE
-------------------
The ``BDE Build System`` (BBS) allows users to quickly set build parameters in
the environment variables that will be used by various bbs tools.

.. note::

   This same process can be used to build any :doc:`BDE-style<../reference/bde_repo_layout>` repository.

.. note::

   The Build setup must always be performed at the top of the repository or the workspace.

Download the BDE libraries
--------------------------
BDE library can be cloned from
{{{ internal
ether internal `bbgithub bde
<https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

.. code-block:: shell

   $ git clone bbgithub:bde/bde
   $ cd bde

or from
}}}
public `github bde <https://github.com/bloomberg/bde>`_ repository:

.. code-block:: shell

   $ git clone https://github.com/bloomberg/bde.git
   $ cd bde

See :ref:`bbs-build-workspace-top` for the instruction on setting a build
workspace with multiple repos.

.. _setup_the_environment:

Setup the Environment
---------------------
Use :doc:`../tools/bbs_build_env` To set the build variables in the
environment:

.. code-block:: shell

   $ eval `bbs_build_env -u dbg_64`

.. note::

   The ``-p`` and ``-u`` options can be used to configure the compiler and
   build options resectively.

``bbs_build_env list`` can be used to list the available compilers (users can
also :doc:`add a custom compiler profile<configure_profile>`). The build
options are passed by :ref:`ufid`

After setting the build environment, user can subsequently run ``bbs_build
configure`` without additional options.

Inspect Build Environment Settings
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Users can also use :doc:`../tools/bbs_build_env` to see the environment
variables that will be set:

.. code-block:: shell

   $ bbs_build_env -u dbg_64
   Effective ufid: dbg_64
   Using build profile: gcc-10.2.1
   export BBS_ENV_MARKER=ON
   export BDE_CMAKE_UPLID=unix-linux-x86_64-3.10.0-gcc-10.2.1
   export BDE_CMAKE_UFID=dbg_64
   export BDE_CMAKE_BUILD_DIR="_build/unix-linux-x86_64-3.10.0-gcc-10.2.1-dbg"
   export CC=/opt/bb/bin/gcc
   export CXX=/opt/bb/bin/g++
   export BDE_CMAKE_TOOLCHAIN=/home/<user>/bde-tools/BdeBuildSystem/toolchains/linux/gcc-default.cmake
   export BDE_CMAKE_INSTALL_DIR=/home/<user>/workspace/bde/_install

Configure the Build
-------------------
Because we used :doc:`../tools/bbs_build_env` to set environment variables
specifying the compiler and build options, we do not need to pass any options
to configure.  Alternatively, compiler and build options can be passed
explicitly to :doc:`bbs_build on the command line<../tools/bbs_build>`.

.. code-block:: shell

   $ bbs_build configure

.. note::

   The ``configure`` step must be done after setting a new build environment
   (be it a different compiler, ufid or a build shell).

In the case when you want to make sure that any pre-existing build
configuration is erased, add ``--clean`` parameter:

.. code-block:: shell

   $ bbs_build configure --clean


Build and Install
-----------------
* Build the software:

.. code-block:: shell

   $ bbs_build build

* Build and run any tests:

.. code-block:: shell

   $ bbs_build build --tests run

* Install the headers and built libraries:

.. code-block:: shell

   $ bbs_build install

Developers can also :doc:`build individual components and groups of
components<build_single_target>`.
