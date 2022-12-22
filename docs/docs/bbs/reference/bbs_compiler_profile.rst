=================
Compiler Profiles
=================

BBS compiler profiles are CMake toolchains that define compiler configuration
used to build the project.  CMake toolchains can define a compiler
configuration with different levels of details, but BBS conceptually
recognizes 2 type of profile:

  * Hardcoded (constrained) compiler profiles
  * Flexible BBS compiler profiles

Note that a client can always write a profile that will support only a subset
of standard BDE build flags and hardcode other aspects of the compiler
settings. Writing such a profile will require in-depth knowledge of both CMake
toolchains and BBS build flags (See :ref:`ufid` for more details).

Hardcoded Compiler Profiles
---------------------------

Those profiles are essentially a fully defined CMake toolchains that provide
all compilation and link flags as well as pathes to the C/C++ compilers and
other build tools. Such profiles are usually supplied as part of the production
build environment and guarantee the consistency of production builds.

The simplified example of such profile is shown below:

.. code-block:: cmake

   set(CMAKE_C_COMPILER /usr/bin/gcc-10 CACHE FILEPATH "C Compiler path")
   set(CMAKE_CXX_COMPILER /usr/bin/g++-10 CACHE FILEPATH "C++ Compiler path")

   set(CMAKE_C_FLAGS "-march=westmere -m64" CACHE STRING "Bloomberg ABI C flags.")
   set(CMAKE_C_FLAGS_RELWITHDEBINFO "-g -O2 -fno-strict-aliasing" CACHE STRING "ABI C flags.")
   set(CMAKE_CXX_STANDARD 17 CACHE STRING "C++ standard.")
   set(CMAKE_CXX_FLAGS "-D_GLIBCXX_USE_CXX11_ABI=0 -march=westmere -m64" CACHE STRING "ABI C++ flags.")
   set(CMAKE_CXX_FLAGS_RELWITHDEBINFO "-g -O2 -fno-strict-aliasing" CACHE STRING "ABI C++ flags.")


As shown above, this profile hardcodes the path to compiler, bitness ('-m64'),
compilation flags, additional defines and C++ standard.

Note that CMake toolchains by default supports 4 build types:

.. csv-table::
   :header: "CMake Build Type", "Ufid mapping"
   :widths: 40, 60
   :align: left

   "Release", "opt"
   "Debug", "dbg"
   "RelWithDebInfo", "opt_dbg"
   "MinSizeRel", "N/A - not supported"

Hardcoded compiler profiles allow users to select different build types only.


Flexible Compiler Profiles
--------------------------

Those profiles are effectively a specially designed CMake toolchains that will
set compilation and links flags based on the CMake and environement variables
passed at the configure step.  Those profiles are provided by BDE build system.

The simplified excerpt from gcc flexible profile is shown below:

.. code-block:: cmake

   set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
   set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

   if(BDE_BUILD_TARGET_64)
       string(CONCAT DEFAULT_CXX_FLAGS
              "${DEFAULT_CXX_FLAGS} "
              "-m64 "
              )
       string(CONCAT DEFAULT_C_FLAGS
              "${DEFAULT_C_FLAGS} "
              "-m64 "
              )
   endif()

   if(BDE_BUILD_TARGET_32)
       string(CONCAT DEFAULT_CXX_FLAGS
              "${DEFAULT_CXX_FLAGS} "
              "-m32 "
              "-mstackrealign "
              "-mfpmath=sse "
              "-D_FILE_OFFSET_BITS=64 "
              )
       string(CONCAT DEFAULT_C_FLAGS
              "${DEFAULT_C_FLAGS} "
              "-m32 "
              "-mstackrealign "
              "-mfpmath=sse "
              "-D_FILE_OFFSET_BITS=64 "
              )
   endif()

   if (BDE_BUILD_TARGET_CPP03)
       set(CMAKE_CXX_STANDARD 98)
   elseif(BDE_BUILD_TARGET_CPP11)
       set(CMAKE_CXX_STANDARD 11)
   elseif(BDE_BUILD_TARGET_CPP14)
       set(CMAKE_CXX_STANDARD 14)
   elseif(BDE_BUILD_TARGET_CPP17)
       set(CMAKE_CXX_STANDARD 17)
   elseif(BDE_BUILD_TARGET_CPP20)
       set(CMAKE_CXX_STANDARD 20)
   elseif(BDE_BUILD_TARGET_CPP23)
       set(CMAKE_CXX_STANDARD 23)
   endif()
   ...
   set(CMAKE_CXX_FLAGS        ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
   set(CMAKE_C_FLAGS          ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
   set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

   set(CMAKE_CXX_FLAGS_RELEASE         "-O2 -DNDEBUG"
       CACHE STRING "Release"        FORCE)
   set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2 -DNDEBUG"
       CACHE STRING "MinSizeRel"     FORCE)
   set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g -DNDEBUG"
       CACHE STRING "RelWithDebInfo" FORCE)
   set(CMAKE_CXX_FLAGS_DEBUG           "-g"
       CACHE STRING "Debug"          FORCE)

   set(CMAKE_C_FLAGS_RELEASE           "-O2 -DNDEBUG"
       CACHE STRING "Release"        FORCE)
   set(CMAKE_C_FLAGS_MINSIZEREL        "-O2 -DNDEBUG"
       CACHE STRING "MinSizeRel"     FORCE)
   set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O2 -g -DNDEBUG"
       CACHE STRING "RelWithDebInfo" FORCE)
   set(CMAKE_C_FLAGS_DEBUG             "-g"
       CACHE STRING "Debug"          FORCE)

This toolchain allows user to invoke CMake with different BUILD flags to change
the active compiler configuration:

.. code-block:: Bash

   $ cmake -DBDE_BUILD_TARGET_CPP20=ON -DBDE_BUILD_TARGET_64 <path>
