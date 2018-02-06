set(root /bb/bde/bbshr/bde-internal-tools/bin/compiler-wrappers/gcc)
set(CMAKE_C_COMPILER ${root}/gcc-6)
set(CMAKE_CXX_COMPILER ${root}/g++-6)

# Select global build type flags.
set(CMAKE_CXX_FLAGS ""
    CACHE STRING "Default"        FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-O2 -mtune=opteron -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2 -mtune=opteron -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g -mtune=opteron -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-g -mtune=opteron"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS ""
    CACHE STRING "Default"        FORCE)

set(CMAKE_C_FLAGS_RELEASE         "-O2 -mtune=opteron -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL      "-O2 -mtune=opteron -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO  "-O2 -g -mtune=opteron -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG           "-g -mtune=opteron"
    CACHE STRING "Debug"          FORCE)

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)
