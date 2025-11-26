include_guard()

macro(_bbs_init_bde_options)
    # Flags that can be set by users
    option(BDE_BUILD_TARGET_NO_EXC "Disable exceptions")
    option(BDE_BUILD_TARGET_NO_MT  "Disable multi-threading")
    option(BDE_BUILD_TARGET_SAFE   "Enable safe build")
    option(BDE_BUILD_TARGET_ASAN   "Enable address sanitizer")
    option(BDE_BUILD_TARGET_MSAN   "Enable memory sanitizer")
    option(BDE_BUILD_TARGET_TSAN   "Enable thread sanitizer")
    option(BDE_BUILD_TARGET_UBSAN  "Enable UB sanitizer")
    option(BDE_BUILD_TARGET_FUZZ   "Enable fuzzer")
    option(BDE_BUILD_TARGET_CPP03  "Use c++03 standard")
    option(BDE_BUILD_TARGET_CPP11  "Use c++11 standard")
    option(BDE_BUILD_TARGET_CPP14  "Use c++14 standard")
    option(BDE_BUILD_TARGET_CPP17  "Use c++17 standard")
    option(BDE_BUILD_TARGET_CPP20  "Use c++20 standard")
    option(BDE_BUILD_TARGET_CPP23  "Use c++23 standard")
    option(BDE_BUILD_TARGET_CPP26  "Use c++26 standard")
    option(BDE_BUILD_TARGET_32     "32-bit build")
    option(BDE_BUILD_TARGET_64     "64-bit build")
    # Asserts and reviews (mutually exclusive values options)
    set(BDE_BUILD_TARGET_ASSERT_LEVEL default CACHE STRING "Assert level")
    set_property(CACHE BDE_BUILD_TARGET_ASSERT_LEVEL PROPERTY STRINGS default AOPT ADBG ASAFE ANONE)
    set(BDE_BUILD_TARGET_REVIEW_LEVEL default CACHE STRING "Review level")
    set_property(CACHE BDE_BUILD_TARGET_REVIEW_LEVEL PROPERTY STRINGS default ROPT RDBG RSAFE RNONE)
endmacro()

# Add thread related options to the target
function(bbs_add_target_thread_flags target scope)
    if (NOT BDE_BUILD_TARGET_NO_MT)
        # add OS specific compilation definitions for multithreaded code
        if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_compile_definitions(${target}
                ${scope}
                    _POSIX_PTHREAD_SEMANTICS
                    _REENTRANT)
            target_compile_options(${target}
                ${scope}
                    -pthread)
        elseif(CMAKE_SYSTEM_NAME STREQUAL "SunOS")
            target_compile_definitions(${target}
                ${scope}
                    _POSIX_PTHREAD_SEMANTICS
                    _REENTRANT)

            if (CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
                target_compile_options(${target}
                    ${scope}
                        -mt)
            elseif (CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
                target_compile_options(${target}
                    ${scope}
                        -pthread)
            endif()
        endif()
    endif()
endfunction()

function(bbs_add_target_rt_flags target scope)
    if(CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
        target_link_libraries(${target} ${scope} -lrt)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "XL")
        target_compile_definitions(
            ${target}
            ${scope}
                __NOLOCK_ON_INPUT
                __NOLOCK_ON_OUTPUT)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
        if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_link_libraries(${target} ${scope} -lrt)
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_link_libraries(${target} ${scope} Ws2_32)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
        if (CMAKE_SYSTEM_NAME STREQUAL "Linux")
            target_link_libraries(${target} ${scope} -lrt -lstdc++)
        endif()
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    endif ()
endfunction()

function(bbs_add_target_bde_flags target scope)
    foreach(flag NO_EXC NO_MT SAFE CPP03 CPP11 CPP14 CPP17 CPP20 32 64)
        if (BDE_BUILD_TARGET_${flag})
            target_compile_definitions(
                ${target}
                ${scope}
                    BDE_BUILD_TARGET_${flag})
        endif()
    endforeach()
    target_compile_definitions(
        ${target}
        ${scope}
            "$<$<CONFIG:RelWithDebInfo,Debug>:BDE_BUILD_TARGET_DBG>"
            "$<$<CONFIG:RelWithDebInfo,Release>:BDE_BUILD_TARGET_OPT>")

    # Sanitizers
    foreach(flag ASAN MSAN TSAN UBSAN)
        if (BDE_BUILD_TARGET_${flag})
            target_compile_definitions(
                ${target}
                ${scope}
                    BDE_BUILD_TARGET_${flag})
        endif()
    endforeach()

    # Fuzzer
    if (BDE_BUILD_TARGET_FUZZ)
        target_compile_definitions(
            ${target}
            ${scope}
                BDE_ACTIVATE_FUZZ_TESTING
                FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION)
    endif()

    # ASSERT levels
    if(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "default")
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "AOPT")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_ASSERT_LEVEL_ASSERT_OPT)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ADBG")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_ASSERT_LEVEL_ASSERT)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ASAFE")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_ASSERT_LEVEL_ASSERT_SAFE)
    elseif(BDE_BUILD_TARGET_ASSERT_LEVEL STREQUAL "ANONE")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_ASSERT_LEVEL_NONE)
    endif()

    # REVIEW levels
    if(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "default")
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "ROPT")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_REVIEW_LEVEL_REVIEW_OPT)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RDBG")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_REVIEW_LEVEL_REVIEW)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RSAFE")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_REVIEW_LEVEL_REVIEW_SAFE)
    elseif(BDE_BUILD_TARGET_REVIEW_LEVEL STREQUAL "RNONE")
        target_compile_definitions(
            ${target}
            ${scope}
                BSLS_REVIEW_LEVEL_NONE)
    endif()

    # non thread related definitions for specific compilers
    if(CMAKE_CXX_COMPILER_ID STREQUAL "SunPro")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "XL")
        target_compile_definitions(
            ${target}
            ${scope}
                __NOLOCK_ON_INPUT
                __NOLOCK_ON_OUTPUT)
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
        target_compile_definitions(
            ${target}
            ${scope}
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

if(NOT bbs_internal_init_complete)
    _bbs_init_bde_options()
    set(bbs_internal_init_complete "1")
endif()
