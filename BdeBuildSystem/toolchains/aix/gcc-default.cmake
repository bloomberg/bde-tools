# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC 
# environment variables.
#
# AIX, gcc
#
# Important: this variable changes the behaviour of the shared library
# link step.
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)

# In order to simulate XLs behavior of implicitly extern "C" portions of
# system header files, GNU compilers extern "C" *ALL* system header files.
# This obviously doesn't work in the presence of C++, so turn off using
# -isystem to avoid great hilarity.
set(CMAKE_NO_SYSTEM_FROM_IMPORTED ON)

set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "-maix${BUILD_BITNESS} "
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "-maix${BUILD_BITNESS} "
      )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/gcc-bde-presets.cmake")

set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-O"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-g"
    CACHE STRING "Debug"          FORCE)


set(CMAKE_C_FLAGS_RELEASE           "-O"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-O"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-g"
    CACHE STRING "Debug"          FORCE)
