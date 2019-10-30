.. _build-examples-top:

==============
Build Examples
==============

All the examples below should be run from the top-level bde source tree:

{{{ internal
  ::

    $ git clone bbgithub:bde/bde
    $ cd bde
}}}
{{{ oss
  ::

    $ git clone https://github.com/bloomberg/bde.git
    $ cd bde
}}}

.. _build-examples-1:

Example 1. Build all
--------------------

Configure the build system for the specified ufid:

  ::
   
    $ eval `bde_build_env.py -t dbg_exc_mt_64_cpp11`
    $ cmake_build.py configure build


.. _build-examples-2:

Example 2. Component development
--------------------------------

Configure the build system for the specified ufid:

  ::
   
    $ eval `bde_build_env.py -t dbg_exc_mt_64_cpp11`
    $ cmake_build.py configure 

Build and run component test driver:

  ::

    $ cmake_build.py --targets bsls_log --tests run build
    $ cmake_build.py --targets=bsls_log --tests=run build

Build the ``bsls`` package library and run all the test drivers for the
package:

  ::

    $ cmake_build.py --targets=bsls --tests=run build

Build the ``bal`` package group library and compile/link all the test drivers
for the package group:

  ::

    $ cmake_build.py --targets=bal --tests=build build

  .. note::
    ``--targets`` flag accepts multiple comma-separated targets
     

.. _build-examples-3:

Example 3. Component development (no env)
-----------------------------------------

In this mode user must specify all the relevant command parameters in the
command line.  ``--build_dir`` is mandatory parameter for every command.

Configure the build system for the specified ufid:

  ::
   
    $ cmake_build.py configure --ufid opt_exc_mt --build_dir ./_build/bld

Build and run component test driver:

  ::

    $ cmake_build.py --build_dir ./_build/bld --targets bslstl_set --tests run build

.. _build-examples-4:

Example 4. Working with low-level build system
----------------------------------------------

After configuration step, the build directory contains fully configured
low-level build system that can be invoked directly.

Configure the build system for the specified ufid:

  :: 
   
    $ cmake_build.py configure --ufid opt_exc_mt --build_dir ./_build/bld
    $ cd ./_build/bld

Invoke low-level build system (Ninja, by default) to list build targets:

  ::
    
    $ ninja -t targets

Build specific targets:

  ::

    $ ninja inteldfp
    $ ninja bdlb
    $ ninja bdlb.t
    $ ninja bdld_datum.t

  .. note::
     Low-level targets with ``.t`` suffix correspond to the test drivers. Note
     that ``.t`` target for package group and package will build all tests
     drivers for this package group or packages.

.. _build-examples-5:

Example 5. Building a workspace
-------------------------------

BDE build system supports building a workspace.

{{{ internal
Clone the repos into a workspace:

  .. code-block:: bash
   
    $ git clone bbgithub:bde/bde
    $ git clone bbgithub:bde/bde-classic
    $ git clone bbgithub:bde/hsl

Create the ``CMakeLists.txt`` file with the following content in the top level
directory:

  .. code-block:: cmake

     # CMakeLists.txt
     cmake_minimum_required(VERSION 3.8)

     project("BDE_ws")

     include(bde_workspace)

     bde_process_workspace(
         ${CMAKE_CURRENT_LIST_DIR}/bde
         ${CMAKE_CURRENT_LIST_DIR}/bde-classic
         ${CMAKE_CURRENT_LIST_DIR}/hsl
     )
}}}
{{{ oss
Clone the repos into a workspace:

  .. code-block:: bash
   
    $ git clone https://github.com/bloomberg/bde.git
    $ git clone https://github.com/<user_id>/bde_app.git

Create the ``CMakeLists.txt`` file with the following content in the top level
directory:

  .. code-block:: cmake

     # CMakeLists.txt
     cmake_minimum_required(VERSION 3.8)

     project("BDE_ws")

     include(bde_workspace)

     bde_process_workspace(
         ${CMAKE_CURRENT_LIST_DIR}/bde
         ${CMAKE_CURRENT_LIST_DIR}/bde_app
     )
}}}

Proceed with the standard workflow.

.. _build-examples-6:

Example 6. Installing build artefacts
-------------------------------------

Configure and build BDE libraries using your preferred workflow.

The install is split into a set of install components that install various
build artefacts and meta information into the target destination.

Install the ufid-qualified ``bsl`` library:

  .. code-block:: bash
   
    $ cmake_build.py --build_dir ./_build/bld --install_dir=~/install --install_prefix=/ --component=bsl install

Inspect the installation tree (for ``opt_exc_mt`` ufid):

  ::

    $ tree ~/install
    `-- lib
        `-- opt_exc_mt
            |-- cmake
            |   |-- bslConfig.cmake
            |   |-- bslInterfaceTargets.cmake
            |   |-- bslTargets-release.cmake
            |   `-- bslTargets.cmake
            `-- libbsl.a

Install the ufid-qualified compatibility symlinks for ``bsl`` library:

  ::
   
    $ cmake_build.py --build_dir ./_build/bld --install_dir=~/install --install_prefix=/ --component=bsl-symlinks install
    $ tree ~/install
    `-- lib
        |-- libbsl.opt_exc_mt.a -> opt_exc_mt/libbsl.a
        `-- opt_exc_mt
            |-- ...
            `-- libbsl.a
     
Install the non ufid-qualified (aka "Release") symlink for ``bsl`` library:

  ::
   
    $ cmake_build.py --build_dir ./_build/bld --install_dir=~/install --install_prefix=/ --component=bsl-release-symlink install
    $ tree ~/install
    `-- lib
        |-- libbsl.a -> opt_exc_mt/libbsl.a
        |-- libbsl.opt_exc_mt.a -> opt_exc_mt/libbsl.a
        `-- opt_exc_mt
            |-- ...
            `-- libbsl.a

  .. note::

     ``release-symlink`` component create the symlink to the currently
     installing flavor of the library. 

Install the header files for ``bsl`` library:

  ::

    $ cmake_build.py --build_dir ./_build/bld --install_dir=~/install --install_prefix=/ --component=bsl-headers install


  .. note:: 
  
     See :ref:`build_system_design-install-components` for more information.
