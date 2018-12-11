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

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "-maix${BUILD_BITNESS} "
      )
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)

set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "-maix${BUILD_BITNESS} "
      )
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)

# All tools on AIX need a bitness.

set(CMAKE_CXX_ARCHIVE_CREATE
    "<CMAKE_AR> -X${BUILD_BITNESS} cr <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_APPEND
    "<CMAKE_AR> -X${BUILD_BITNESS} r <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_FINISH
    "<CMAKE_RANLIB> -X${BUILD_BITNESS} <TARGET> <LINK_FLAGS>")

set(CMAKE_C_ARCHIVE_CREATE
    "<CMAKE_AR> -X${BUILD_BITNESS} cr <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_C_ARCHIVE_APPEND
    "<CMAKE_AR> -X${BUILD_BITNESS} r <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_C_ARCHIVE_FINISH
    "<CMAKE_RANLIB> -X${BUILD_BITNESS} <TARGET> <LINK_FLAGS>")

set(CMAKE_CXX_CREATE_SHARED_LIBRARY
    "<CMAKE_CXX_COMPILER> <CMAKE_SHARED_LIBRARY_CXX_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")

set(CMAKE_C_CREATE_SHARED_LIBRARY
    "<CMAKE_C_COMPILER> <CMAKE_SHARED_LIBRARY_C_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
