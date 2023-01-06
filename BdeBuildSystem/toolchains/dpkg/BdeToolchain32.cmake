cmake_minimum_required (VERSION 3.19)

if(NOT DEFINED DISTRIBUTION_REFROOT)
    if(DEFINED ENV{DISTRIBUTION_REFROOT})
        set(DISTRIBUTION_REFROOT "$ENV{DISTRIBUTION_REFROOT}/" CACHE STRING "BB Dpkg root set from environment variable.")
    else()
        get_filename_component(REFROOT ${CMAKE_CURRENT_LIST_DIR}/../../../../../../../ REALPATH)
        set(DISTRIBUTION_REFROOT ${REFROOT}/ CACHE STRING "BB Dpkg root set from toolchain file location.")
    endif()
endif()

function(remove_duplicates input_str output_str)
    set(input_list ${${input_str}})
    separate_arguments(input_list)
    list(REMOVE_DUPLICATES input_list)
    string (REGEX REPLACE "([^\\]|^);" "\\1 " _tmp_str "${input_list}")
    string (REGEX REPLACE "[\\](.)" "\\1" _tmp_str "${_tmp_str}") #fixes escapes
    set (${output_str} "${_tmp_str}" PARENT_SCOPE)
endfunction()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")

    string(APPEND CMAKE_C_FLAGS   " -fno-strict-aliasing")
    remove_duplicates(CMAKE_C_FLAGS _tmp_C_FLAGS)
    set(CMAKE_C_FLAGS ${_tmp_C_FLAGS} CACHE STRING "Bloomberg ABI C flags." FORCE)

    string(APPEND CMAKE_CXX_FLAGS " -fno-strict-aliasing")
    remove_duplicates(CMAKE_CXX_FLAGS _tmp_CXX_FLAGS)
    set(CMAKE_CXX_FLAGS ${_tmp_CXX_FLAGS} CACHE STRING "Bloomberg ABI C++ flags." FORCE)
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "AIX")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")

    string(APPEND CMAKE_C_FLAGS   " -qalias=noansi")
    remove_duplicates(CMAKE_C_FLAGS _tmp_C_FLAGS)
    set(CMAKE_C_FLAGS ${_tmp_C_FLAGS} CACHE STRING "Bloomberg ABI C flags." FORCE)

    string(APPEND CMAKE_CXX_FLAGS " -qalias=noansi")
    remove_duplicates(CMAKE_CXX_FLAGS _tmp_CXX_FLAGS)
    set(CMAKE_CXX_FLAGS ${_tmp_CXX_FLAGS} CACHE STRING "Bloomberg ABI C++ flags." FORCE)
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "SunOS")
    include("${DISTRIBUTION_REFROOT}/opt/bb/share/plink/BBToolchain32.cmake")

    string(APPEND CMAKE_C_FLAGS " -xthreadvar=dynamic")
    remove_duplicates(CMAKE_C_FLAGS _tmp_C_FLAGS)
    set(CMAKE_C_FLAGS ${_tmp_C_FLAGS} CACHE STRING "Bloomberg ABI C flags." FORCE)

    string(APPEND CMAKE_CXX_FLAGS " -xthreadvar=dynamic")
    remove_duplicates(CMAKE_CXX_FLAGS _tmp_CXX_FLAGS)
    set(CMAKE_CXX_FLAGS ${_tmp_CXX_FLAGS} CACHE STRING "Bloomberg ABI C++ flags." FORCE)
endif()

if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
    set(root /usr/bin)
    set(CMAKE_CXX_COMPILER ${root}/clang++)
    set(CMAKE_C_COMPILER ${root}/clang)

    include("${DISTRIBUTION_REFROOT}/opt/bb/share/cmake/BdeBuildSystem/toolchains/darwin/clang-default")
endif()

