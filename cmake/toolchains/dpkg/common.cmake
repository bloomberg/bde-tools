# This toolchain file is used by the dpkg builds on all ${BUILD_BITNESS} bit platforms.
# Select global build type flags.
set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS}" CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   "-m${BUILD_BITNESS}" CACHE STRING "Default" FORCE)

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/g++)
    set(CMAKE_C_COMPILER ${root}/gcc)

    set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS} -mtune=opteron" CACHE STRING "Default" FORCE)
    set(CMAKE_C_FLAGS   "-m${BUILD_BITNESS} -mtune=opteron" CACHE STRING "Default" FORCE)

    set(CMAKE_CXX_FLAGS_RELEASE         "-O2"
        CACHE STRING "Release"        FORCE)
    set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2"
        CACHE STRING "MinSizeRel"     FORCE)
    set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g"
        CACHE STRING "RelWithDebInfo" FORCE)
    set(CMAKE_CXX_FLAGS_DEBUG           "-g"
        CACHE STRING "Debug"          FORCE)

    set(CMAKE_C_FLAGS_RELEASE         "-O2"
        CACHE STRING "Release"        FORCE)
    set(CMAKE_C_FLAGS_MINSIZEREL      "-O2"
        CACHE STRING "MinSizeRel"     FORCE)
    set(CMAKE_C_FLAGS_RELWITHDEBINFO  "-O2 -g"
        CACHE STRING "RelWithDebInfo" FORCE)
    set(CMAKE_C_FLAGS_DEBUG           "-g"
        CACHE STRING "Debug"          FORCE)

    # Disable GNU c++ extensions.
    set(CMAKE_CXX_EXTENSIONS OFF)
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "AIX")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/xlC_r)
    set(CMAKE_C_COMPILER ${root}/xlc_r)

    # Important: this variable changes the behaviour of the shared library
    # link step.
    set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)

    set(CMAKE_CXX_FLAGS "-q${BUILD_BITNESS}" CACHE STRING "Default" FORCE)
    set(CMAKE_C_FLAGS   "-q${BUILD_BITNESS}" CACHE STRING "Default" FORCE)

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
    set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O"
        CACHE STRING "RelWithDebInfo" FORCE)
    set(CMAKE_C_FLAGS_DEBUG             ""
        CACHE STRING "Debug"          FORCE)
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "SunOS")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/CC)
    set(CMAKE_C_COMPILER ${root}/cc)

    set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS} -xtarget=generic -xbuiltin=%all" CACHE STRING "Default" FORCE)
    set(CMAKE_C_FLAGS   "-m${BUILD_BITNESS} -xtarget=generic" CACHE STRING "Default" FORCE)

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
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(root /usr/bin)
    set(CMAKE_CXX_COMPILER ${root}/clang++)
    set(CMAKE_C_COMPILER ${root}/clang)

    set(CMAKE_CXX_FLAGS_RELEASE         "-O2"
        CACHE STRING "Release"        FORCE)
    set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2"
        CACHE STRING "MinSizeRel"     FORCE)
    set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g"
        CACHE STRING "RelWithDebInfo" FORCE)
    set(CMAKE_CXX_FLAGS_DEBUG           "-g"
        CACHE STRING "Debug"          FORCE)

    set(CMAKE_C_FLAGS_RELEASE         "-O2"
        CACHE STRING "Release"        FORCE)
    set(CMAKE_C_FLAGS_MINSIZEREL      "-O2"
        CACHE STRING "MinSizeRel"     FORCE)
    set(CMAKE_C_FLAGS_RELWITHDEBINFO  "-O2 -g"
        CACHE STRING "RelWithDebInfo" FORCE)
    set(CMAKE_C_FLAGS_DEBUG           "-g"
        CACHE STRING "Debug"          FORCE)
endif()
