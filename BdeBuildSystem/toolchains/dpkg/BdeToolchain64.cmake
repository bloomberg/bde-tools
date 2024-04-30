cmake_minimum_required (VERSION 3.19)

if(NOT DEFINED DISTRIBUTION_REFROOT)
    if(DEFINED ENV{DISTRIBUTION_REFROOT})
        set(DISTRIBUTION_REFROOT "$ENV{DISTRIBUTION_REFROOT}/" CACHE STRING "BB Dpkg root set from environment variable.")
    else()
        get_filename_component(REFROOT ${CMAKE_CURRENT_LIST_DIR}/../../../../../../../ REALPATH)
        set(DISTRIBUTION_REFROOT ${REFROOT}/ CACHE STRING "BB Dpkg root set from toolchain file location.")
    endif()
endif()

# We converged on the compilation flags with the production toolchains on all platforms.
if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain64.cmake")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "AIX")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain64.cmake")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "SunOS")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain64.cmake")
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(root /usr/bin)
    set(CMAKE_CXX_COMPILER ${root}/clang++)
    set(CMAKE_C_COMPILER ${root}/clang)

    include("${DISTRIBUTION_REFROOT}/opt/bb/share/cmake/BdeBuildSystem/toolchains/darwin/clang-default")
endif()

