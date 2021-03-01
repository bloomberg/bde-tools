if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/g++)
    set(CMAKE_C_COMPILER ${root}/gcc)

    include("toolchains/linux/gcc-default")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "AIX")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/xlC_r)
    set(CMAKE_C_COMPILER ${root}/xlc_r)

    include("toolchains/aix/xlc-default")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "SunOS")
    set(root /opt/bb/bin)
    set(CMAKE_CXX_COMPILER ${root}/CC)
    set(CMAKE_C_COMPILER ${root}/cc)

    include("toolchains/sunos/dpkg")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(root /usr/bin)
    set(CMAKE_CXX_COMPILER ${root}/clang++)
    set(CMAKE_C_COMPILER ${root}/clang)

    include("toolchains/darwin/clang-default")
endif()
