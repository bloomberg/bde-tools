set(root /bb/util/common/SS12_3-20131030/SUNWspro/bin)
set(CMAKE_C_COMPILER ${root}/cc)
set(CMAKE_CXX_COMPILER ${root}/CC)

# Select global build type flags.
set(CMAKE_CXX_FLAGS ""
    CACHE STRING "Default"        FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-xO3 -xtarget=generic -xbuiltin=%all -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-xO2 -xtarget=generic -xbuiltin=%all -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-xO2 -g0 -xtarget=generic -xbuiltin=%all -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-xO0"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS ""
    CACHE STRING "Default"        FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-xO3 -xtarget=generic -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-xO2 -xtarget=generic -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-xO2 -g0 -xtarget=generic -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-xO0"
    CACHE STRING "Debug"          FORCE)

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)
