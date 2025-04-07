cmake_minimum_required (VERSION 3.19)

if(NOT DEFINED DISTRIBUTION_REFROOT)
    if(DEFINED ENV{DISTRIBUTION_REFROOT})
        set(DISTRIBUTION_REFROOT "$ENV{DISTRIBUTION_REFROOT}/" CACHE STRING "BB Dpkg root set from environment variable.")
    else()
        get_filename_component(REFROOT ${CMAKE_CURRENT_LIST_DIR}/../../../../../../../ REALPATH)
        set(DISTRIBUTION_REFROOT ${REFROOT}/ CACHE STRING "BB Dpkg root set from toolchain file location.")
    endif()
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")
    # Nothing to add.
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "AIX")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")
    # Nothing to add.
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "SunOS")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")

    # CMAKE_<LANG>_COMPILER_ID is not populated for toolchain file yet
    # Using CMAKE_<LANG>_COMPILER instead ( contains full path to the compiler binary )

    if (NOT "${CMAKE_C_COMPILER}" MATCHES ".*gcc")
        string(APPEND CMAKE_C_FLAGS " -xthreadvar=dynamic")
        set(CMAKE_C_FLAGS ${CMAKE_C_FLAGS} CACHE STRING "Bloomberg ABI C flags." FORCE)
    endif()

    if (NOT "${CMAKE_CXX_COMPILER}" MATCHES ".*g\\+\\+")
        string(APPEND CMAKE_CXX_FLAGS " -xthreadvar=dynamic")
        set(CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS} CACHE STRING "Bloomberg ABI C++ flags." FORCE)
    endif()
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(root /usr/bin)
    set(CMAKE_CXX_COMPILER ${root}/clang++)
    set(CMAKE_C_COMPILER ${root}/clang)

    include("${DISTRIBUTION_REFROOT}/opt/bb/share/cmake/BdeBuildSystem/toolchains/darwin/clang-default")
endif()

