# Select global build type flags.
set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS} -xtarget=generic -xbuiltin=%all"
    CACHE STRING "Default"        FORCE)

set(CMAKE_C_FLAGS "-m${BUILD_BITNESS} -xtarget=generic"
    CACHE STRING "Default"        FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-xO2 -g0"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-xO0"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-xO2 -g0"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-xO0"
    CACHE STRING "Debug"          FORCE)
