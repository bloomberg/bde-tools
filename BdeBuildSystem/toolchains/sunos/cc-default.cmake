# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# SunOS, cc
#
# Select global build type flags.

set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS} "
       "-mt "
       "-xtarget=generic "
       "-xbuiltin=%all "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-features=rtti "
       "-Qoption ccfe "
       "-xglobalstatic "
       "-errtags=yes "
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS} "
       "-xtarget=generic "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-W0,-xglobalstatic "
       "-errtags=yes "
      )

string(CONCAT DEFAULT_EXE_LINKER_FLAGS
       ${DEFAULT_EXE_LINKER_FLAGS}
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xmemalign=8i "
       )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/cc-bde-presets.cmake")

set(CMAKE_CXX_FLAGS        ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS          ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-xO2 -g0"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-xO0 -g0"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-xO2 -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-xO0 -g"
    CACHE STRING "Debug"          FORCE)
