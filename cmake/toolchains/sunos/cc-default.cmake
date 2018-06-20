# Select global build type flags.
set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS} -xtarget=generic -xbuiltin=%all"
    CACHE STRING "Default"        FORCE)

set(CMAKE_C_FLAGS "-m${BUILD_BITNESS} -xtarget=generic"
    CACHE STRING "Default"        FORCE)

