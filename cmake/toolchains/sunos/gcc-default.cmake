# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC 
# environment variables.
#
# SunOS, gcc
#
# Select global build type flags.

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "-m${BUILD_BITNESS} "
      )
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)

set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "-m${BUILD_BITNESS} "
      )
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)

set(CMAKE_EXE_LINKER_FLAGS "-Wl,-z -Wl,relax=comdat" CACHE INTERNAL "" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-O2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-O0 -g"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-O2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-O2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O2 -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-O0 -g"
    CACHE STRING "Debug"          FORCE)

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)
