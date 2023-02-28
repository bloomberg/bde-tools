include_guard()

# import bbs_thread as a target 
function(_bbs_import_threads)
    add_library(bbs_threads INTERFACE IMPORTED GLOBAL)

    # let cmake resolve the actual thread library needed on the link line
    find_package(Threads REQUIRED) # note: this only runs if FindThreads has not been found yet
    # Do not use Threads::Threads here. EmitPkgConfig bbcmake module will add this
    # to the .pc file's Requires.private which is invalid.
    target_link_libraries(bbs_threads INTERFACE ${CMAKE_THREAD_LIBS_INIT})

    # add OS specific compilation definitions for multithreaded code
    if(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
        target_compile_definitions(bbs_threads
            INTERFACE
                _POSIX_PTHREAD_SEMANTICS
                _REENTRANT)

        if (CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
            target_compile_options(
                bbs_threads
                INTERFACE
                    -mt)
        elseif (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
            target_compile_options(
                bbs_threads
                INTERFACE
                    -pthread)
        endif()
    elseif(CMAKE_SYSTEM_NAME STREQUAL "AIX")
        target_compile_definitions(
            bbs_threads
            INTERFACE
                _POSIX_PTHREAD_SEMANTICS
                _REENTRANT
                _THREAD_SAFE
                __VACPP_MULTI__)
        target_compile_options(
            bbs_threads
            INTERFACE
                -qthreaded)
    elseif(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        target_compile_definitions(
            bbs_threads
            INTERFACE
                _POSIX_PTHREAD_SEMANTICS
                _REENTRANT)
        target_compile_options(
            bbs_threads
            INTERFACE
                -pthread)
    endif()
endfunction()

function(_bbs_import_bsl_rt)
    add_library(bbs_bsl_rt INTERFACE IMPORTED GLOBAL)

    if(CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
        target_link_libraries(bbs_bsl_rt INTERFACE -lrt)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "XL")
        target_compile_definitions(
            bbs_bsl_rt
            INTERFACE 
                __NOLOCK_ON_INPUT
                __NOLOCK_ON_OUTPUT)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_link_libraries(bbs_bsl_rt INTERFACE -lrt)
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_link_libraries(bbs_bsl_rt INTERFACE Ws2_32)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        target_link_libraries(bbs_bsl_rt INTERFACE rt stdc++)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    endif ()
endfunction()

function(_bbs_import_bde_flags)
    add_library(bbs_bde_flags INTERFACE IMPORTED GLOBAL)

    # Those 2 flags are inferred from CMAKE_BUILD_TYPE
    set(BDE_BUILD_TARGET_OPT OFF)
    set(BDE_BUILD_TARGET_DBG OFF)
    # Other flags can be set by users
    option(BDE_BUILD_TARGET_NO_EXC "Disable exceptions")
    option(BDE_BUILD_TARGET_NO_MT  "Disable multi-threading")
    option(BDE_BUILD_TARGET_SAFE   "Enable safe build")
    option(BDE_BUILD_TARGET_ASAN   "Enable address sanitizer")
    option(BDE_BUILD_TARGET_MSAN   "Enable memory sanitizer")
    option(BDE_BUILD_TARGET_TSAN   "Enable thread sanitizer")
    option(BDE_BUILD_TARGET_UBSAN  "Enable UB sanitizer")
    option(BDE_BUILD_TARGET_FUZZ   "Enable fuzzer")
    # Asserts and reviews (mutually exclusive values options)
    set(BDE_BUILD_TARGET_ASSERT_LEVEL default CACHE STRING "Assert level")
    set_property(CACHE BDE_BUILD_TARGET_ASSERT_LEVEL PROPERTY STRINGS default AOPT ADBG ASAFE ANONE)
    set(BDE_BUILD_TARGET_REVIEW_LEVEL default CACHE STRING "Review level")
    set_property(CACHE BDE_BUILD_TARGET_REVIEW_LEVEL PROPERTY STRINGS default ROPT RDBG RSAFE RNONE)

    if (NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "Debug" CACHE STRING "Choose the type of build." FORCE)
    endif()

    message(STATUS "Build type: ${CMAKE_BUILD_TYPE}")
    if (CMAKE_BUILD_TYPE STREQUAL "Release" OR
        CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        set(BDE_BUILD_TARGET_OPT ON)
    endif()

    if (CMAKE_BUILD_TYPE STREQUAL "Debug" OR
        CMAKE_BUILD_TYPE STREQUAL "RelWithDebInfo")
        set(BDE_BUILD_TARGET_DBG ON)
    endif()

    foreach(flag OPT DBG NO_EXC NO_MT SAFE)
        if (BDE_BUILD_TARGET_${flag})
            target_compile_definitions(
                bbs_bde_flags
                INTERFACE
                    BDE_BUILD_TARGET_${flag})
        endif()
    endforeach()

    # Sanitizers
    foreach(flag ASAN MSAN TSAN UBSAN)
        if (BDE_BUILD_TARGET_${flag})
            target_compile_definitions(
                bbs_bde_flags
                INTERFACE
                    BDE_BUILD_TARGET_${flag})
        endif()
    endforeach()

    # Fuzzer
    if (BDE_BUILD_TARGET_FUZZ)
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BDE_ACTIVATE_FUZZ_TESTING
                FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION)
    endif()

    # ASSERT levels
    if(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "default")
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "AOPT")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_ASSERT_LEVEL_ASSERT_OPT)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ADBG")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_ASSERT_LEVEL_ASSERT)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ASAFE")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_ASSERT_LEVEL_ASSERT_SAFE)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ANONE")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_ASSERT_LEVEL_NONE)
    endif()

    # REVIEW levels
    if(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "default")
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "ROPT")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_REVIEW_LEVEL_REVIEW_OPT)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RDBG")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_REVIEW_LEVEL_REVIEW)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RSAFE")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_REVIEW_LEVEL_REVIEW_SAFE)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RNONE")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                BSLS_REVIEW_LEVEL_NONE)
    endif()

    # non thread related definitions for specific compilers
    if(CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "XL")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE 
                __NOLOCK_ON_INPUT
                __NOLOCK_ON_OUTPUT)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_compile_definitions(
            bbs_bde_flags
            INTERFACE
                NOGDI
                NOMINMAX
                _CRT_SECURE_NO_WARNINGS
                _SCL_SECURE_NO_DEPRECATE
                WIN32_LEAN_AND_MEAN
                VC_EXTRALEAN)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    endif ()
endfunction()

if(NOT TARGET bbs_threads)
    _bbs_import_threads()
    _bbs_import_bsl_rt()
    _bbs_import_bde_flags()
endif()
