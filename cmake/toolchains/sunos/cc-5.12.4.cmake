# CC compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# SunOS, cc-5.12.4
#
# Select global build type flags.

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "-m${BUILD_BITNESS} "
       "-xtarget=generic "
       "-xbuiltin=%all "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-features=rtti "
       "-Qoption ccfe -xglobalstatic "
       "-errtags=yes "
      )
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)

set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "-m${BUILD_BITNESS} "
       "-xtarget=generic "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-W0,-xglobalstatic "
       "-errtags=yes "
      )
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)


set(CMAKE_CXX_FLAGS_RELEASE         "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-xO2 -g0 -xs=no"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-xO0 -g0 -xs=no"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-xO2 -g -xs=no"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-xO0 -g -xs=no"
    CACHE STRING "Debug"          FORCE)
