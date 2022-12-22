.. _bbs-simple-group-top:

---------------------------------
Create a Library or Application
---------------------------------

Creating a Standalone Package (Library)
---------------------------------------
Suppose you want to write a standalone BDE-style package ``s_xyp``.

BDE physical code layout for such a package yelds the following hierarchy:

.. code-block:: text

   standalone
   `- s_xyp
      |- package
      |  |- s_xyp.mem
      |  `- s_xyp.dep
      |- s_xyp_component.h
      |- s_xyp_component.cpp
      `- s_xyp_component.t.cpp

The package ``.mem`` file should list respective members:

.. code-block::

   # s_xyp.mem
   s_xyp_component

Once the package metadata is populated, we need to add few ``CMakeList.txt``
files.

Top level ``CMakeLists.txt`` contains a minimal CMake boilerplate:

.. code-block:: cmake

   # CMakeLists.txt
   cmake_minimum_required(VERSION 3.22)
   project(myLib)

   enable_testing()

   add_subdirectory(standalone/a_xyp)

The code to parse and generate all build and test targets for ``s_xyp``
package:

.. code-block:: cmake

   # standalone/s_xyp/CMakeLists.txt
   find_package(BdeBuildSystem REQUIRED)

   set(target s_xyp)

   add_library(${target} STATIC)
   bbs_setup_target_uor(${target})


Creating a Package Group (Library)
----------------------------------
Suppose you want to write a simple BDE-style package group ``xyz`` containing 2
packages ``xyza`` and ``xyzb``.

BDE physical code layout for such a group yelds the following hierarchy:

.. code-block::

   group
   `- xyz
      |- group
      |     |- xyz.mem
      |     `- zyx.dep
      |- xyza
      |    |- package
      |    |  |- xyza.mem
      |    |  `- xyza.dep
      |    |- xyza_component.h
      |    |- xyza_component.cpp
      |    `- xyza_component.t.cpp
      `- xyzb
           |- package
           |  |_ xyzb.mem
           |  `- xyzb.dep
           |- xyzb_component.h
           |- xyzb_component.cpp
           `- xyzb_component.t.cpp

Futhermore, the group and package ``.mem`` file should list respective members:

.. code-block::

   # xyz.mem
   xyza
   xyzb

.. code-block::
  
   # xyza.mem
   xyza_component

.. code-block::
  
   # xyzb.mem
   xyzb_component

For the purpose of this example let's assume that the package ``xyzb`` depends
on ``xyza``:

.. code-block::

   # xyzb.dep
   xyza

Once the group metadata is populated, we need to add few ``CMakeList.txt``
files.

Top level ``CMakeLists.txt`` contains a minimal CMake boilerplate:

.. code-block:: cmake

   # CMakeLists.txt
   cmake_minimum_required(VERSION 3.22)
   project(myLib)

   enable_testing()

   add_subdirectory(group/xyz)

The code to parse and generate all build and test targets for ``xyz`` group:

.. code-block:: cmake

   # group/xyz/CMakeLists.txt
   find_package(BdeBuildSystem REQUIRED)

   set(target xyz)

   add_library(${target} STATIC)
   bbs_setup_target_uor(${target})

Creating an Application
-----------------------
Suppose you want to write a simple application and link it to one or more BDE libraries

BDE physical code layout for such an application yelds the following hierarchy:

.. code-block:: text

   application
   `- my_app
      |- package
      |  |- my_app.mem
      |  `- my_app.dep
      `- my_app.m.cpp

The application ``.mem`` file for this example should be empty as the source
file containing the ``main()`` entry point should match the application name
and have suffix ``.m.cpp``.

The application depends on the components from the BDE ``bal`` library, thus
the ``.dep`` file should contain:

.. code-block::

   # my_app.dep
   bal

The application source:

.. code-block:: C++

   #include <ball_log.h>
   #include <ball_loggermanager.h>
   #include <ball_loggermanagerconfiguration.h>
   #include <ball_streamobserver.h>
   #include <bsl_memory.h>
   
   using namespace BloombergLP;
   
   BALL_LOG_SET_NAMESPACE_CATEGORY("MAIN");

   int main(int argc, char ** argv)
   {
       ball::LoggerManagerConfiguration configuration;

       configuration.setDefaultThresholdLevelsIfValid(
                                    ball::Severity::e_INFO);  // "Pass-Through"
       ball::LoggerManagerScopedGuard lmGuard(configuration);

       bsl::shared_ptr<ball::StreamObserver> observer =
                            bsl::make_shared<ball::StreamObserver>(&bsl::cout);

       // Register file observer with the LM singleton.
       ball::LoggerManager::singleton().registerObserver(observer, "default");

       // Ball initialization completed.

       // Start logging.
       BALL_LOG_INFO << "Hello, World!";

       return 0;
   }

Once the application metadata and sources are populated, we need to add few
``CMakeList.txt`` files.

Top level ``CMakeLists.txt`` contains a minimal CMake boilerplate:

.. code-block:: cmake

   # CMakeLists.txt
   cmake_minimum_required(VERSION 3.22)
   project(my_app)

   enable_testing()

   add_subdirectory(application/my_app)

The code to parse the bde metadata and generate an application target:

.. code-block:: cmake

   # application/my_app/CMakeLists.txt
   find_package(BdeBuildSystem REQUIRED)

   set(target my_app)

   add_executable(${target})
   bbs_setup_target_uor(${target})

Setup application build dependencies
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
Application dependencies can be setup in 2 different ways:

* Create a refroot with required libraries, production toolchains and the
  dependency resolution cmake module:

.. code-block:: shell

   $ export DISTRIBUTION_REFROOT=${PWD}/refroot
   $ refroot-install --arch=amd64 --refroot-path=./refroot --package libbal-dev --package plink-cmake-toolchain

* Create a build workspace with the BDE libraries and application.
  In this scenario, BDE libraries and application will be build together.

Configure, build and test your application
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

* Select the build profile and build type:

.. code-block:: shell

   $ cd bde
   $ eval `bbs_build_env -u opt`

* Configure and build your aplication:

.. code-block:: shell
    
   $ bbs_build configure build --target my_app

* Run the application:

.. code-block:: shell

   $ ./_build/<build_profile>/application/my_app/my_app

