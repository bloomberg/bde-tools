## bde_ufid.cmake
##
#
## OVERVIEW
## ---------
# This module provides methods to work with UFIDs.
#
# The main exposed functions are the following ones (refer to their individual
# documentation for more information about each):
#  o bde_validate_ufid

include(bde_include_guard)
bde_include_guard()

include(bde_interface_target)
include(bde_utils)

# These flags form potential installation prefix
set(install_ufid_flags opt dbg exc mt safe safe2 pic shr)

# These flags can appear in a valid ufid. The order of those flags is important.
set(known_ufid_flags opt dbg exc mt 64 safe safe2 stlport pic shr ndebug cpp11 cpp14 cpp17)

#.rst:
# bde_ufid_filter_flags
# ---------------------
# 
# This function retains all flags from the ``filter_flags`` in the
# ``ufid_flags``.  The flags not found in the ``filter_flags`` are discarded.
function(bde_ufid_filter_flags target_ufid ufid_flags filter_flags)
    bde_assert_no_extra_args()

    set(new_ufid "")

    # Outer loop retains the global sequence of the flags (canonical form).
    foreach(flag IN LISTS known_ufid_flags)
        if((${flag} IN_LIST ufid_flags) AND (${flag} IN_LIST filter_flags))
            list(APPEND new_ufid "${flag}")
        endif()
    endforeach()
    string(REPLACE ";" "_" new_ufid "${new_ufid}")
    bde_return(${new_ufid})
endfunction()

#.rst:
# bde_ufid_remove_flags
# ---------------------
# 
# This function removes all flags in the ``remove_flags`` from the
# ``ufid_flags``.

function(bde_ufid_remove_flags target_ufid ufid_flags remove_flags)
    bde_assert_no_extra_args()

    set(new_ufid "")

    # Outer loop retains the global sequence of the flags (canonical form).
    foreach(flag IN LISTS known_ufid_flags)
        if((${flag} IN_LIST ufid_flags) AND (NOT ${flag} IN_LIST remove_list))
            list(APPEND new_ufid "${flag}")
        endif()
    endforeach()

    string(REPLACE ";" "_" new_ufid "${new_ufid}")
    bde_return(${new_ufid})
endfunction()

#.rst:
# bde_ufid_add_flags
# ------------------
# 
# This function adds all flags in the ``extra_flags`` to the
# ``ufid_flags``.

function(bde_ufid_add_flags target_ufid ufid_flags extra_flags)
    bde_assert_no_extra_args()

    set(new_ufid "")

    # Outer loop retains the global sequence of the flags (canonical form).
    foreach(flag IN LISTS known_ufid_flags)
        if((${flag} IN_LIST ufid_flags) OR (${flag} IN_LIST extra_flags))
            list(APPEND new_ufid "${flag}")
        endif()
    endforeach()

    string(REPLACE ";" "_" new_ufid "${new_ufid}")
    bde_return(${new_ufid})
endfunction()

#.rst:
# bde_parse_ufid
# --------------
# 
# This function validates the specified ``ufid`` and sets a set of flags for 
# the build system.
function(bde_parse_ufid UFID)
    bde_assert_no_extra_args()

    string(REGEX MATCHALL "[^-_]+" ufid_flags "${UFID}")

    # Check for duplicates
    set(unique_ufid_flags ${ufid_flags})
    list(REMOVE_DUPLICATES unique_ufid_flags)

    if(NOT "${unique_ufid_flags}" STREQUAL "${ufid_flags}")
        message(FATAL_ERROR "UFID ${UFID} contains duplicates.")
    endif()

    foreach(flag IN LISTS ufid_flags)
        if (NOT ${flag} IN_LIST known_ufid_flags)
            message(
                FATAL_ERROR
                "${flag} is not a valid UFID element in ${UFID}."
            )
        endif()
    endforeach()

    # Check for conflicts in cpp standards
    bde_ufid_filter_flags(cppStds "${ufid_flags}" "cpp11;cpp14;cpp17")
    string(REPLACE "_" ";" cppStds "${cppStds}")
    list(LENGTH cppStds cppStdsLen)
    if (cppStdsLen GREATER 1)
        message(FATAL_ERROR
                "UFID ${UFID} contains multiple cpp standards: ${cppStds}")
    endif()

    # Setting the flags in local...
    foreach(flag IN LISTS known_ufid_flags)
        set(bde_ufid_is_${flag} 0)
        if(${flag} IN_LIST ufid_flags)
            set(bde_ufid_is_${flag} 1)
        endif()
    endforeach()

    if(${bde_ufid_is_shr} OR ${bde_ufid_is_64})
        # Shared libraries and 64bit builds must use PIC.
        set(bde_ufid_is_pic 1)
    endif()

    # ... and in parent scope. Cmake details.
    foreach(flag IN LISTS known_ufid_flags)
        set(bde_ufid_is_${flag} ${bde_ufid_is_${flag}} CACHE INTERNAL "" FORCE)
    endforeach()

    bde_ufid_filter_flags(bde_canonical_ufid "${ufid_flags}" "${known_ufid_flags}")
    set(bde_canonical_ufid ${bde_canonical_ufid} CACHE INTERNAL "" FORCE)

    bde_ufid_filter_flags(bde_install_ufid "${ufid_flags}" "${install_ufid_flags}")
    set(bde_install_ufid ${bde_install_ufid} CACHE INTERNAL "" FORCE)

    # Setting install lib suffix based on build bitness.
    set(bde_install_lib_suffix "lib")
    if(${bde_ufid_is_64})
        string(CONCAT bde_install_lib_suffix ${bde_install_lib_suffix} "64")
    endif()
    set(bde_install_lib_suffix ${bde_install_lib_suffix} CACHE INTERNAL "" FORCE)
endfunction()

# :: bde_ufid_add_library ::
# -----------------------------------------------------------------------------
function(bde_ufid_add_library name)
    # Set up shared/static library build
    if(${bde_ufid_is_shr})
        set(libType SHARED)
    else()
        set(libType STATIC)
    endif()
    add_library(${name} ${libType} "${ARGN}")
endfunction()

# :: bde_ufid_setup_flags ::
# -----------------------------------------------------------------------------
function(bde_ufid_setup_flags iface)
    bde_assert_no_extra_args()

    # Set up PIC
    # This code does not work in 3.8, but will be fixed in later versions.
    # The -fPIC flag is set explicitely in the compile options for now.
    if(${bde_ufid_is_shr} OR ${bde_ufid_is_pic})
        bde_interface_target_set_property(
            ${iface}
                POSITION_INDEPENDENT_CODE PUBLIC 1
        )
    endif()

    # Reset global properties to prohibit implicit paths for library lookup and
    # set the global custom lib suffix.
    foreach(type 32 64 X32)
        set_property(GLOBAL PROPERTY FIND_LIBRARY_USE_LIB${type}_PATHS  FALSE)
    endforeach()

    if(${bde_ufid_is_64})
        set(CMAKE_FIND_LIBRARY_CUSTOM_LIB_SUFFIX "64" CACHE INTERNAL "" FORCE)
    else()
        set(CMAKE_FIND_LIBRARY_CUSTOM_LIB_SUFFIX "" CACHE INTERNAL "" FORCE)
    endif()

    # Set up build type
    if(${bde_ufid_is_opt} AND ${bde_ufid_is_dbg})
        set(build_type RelWithDebInfo)
    elseif(${bde_ufid_is_opt})
        set(build_type Release)
    elseif(${bde_ufid_is_dbg})
        set(build_type Debug)
    else()
        message(FATAL_ERROR "The build type is not set in UFID: ${UFID}")
    endif()

    set(CMAKE_BUILD_TYPE ${build_type} CACHE STRING "Build type" FORCE)

    bde_interface_target_compile_features(
        ${iface}
        PUBLIC
            $<${bde_ufid_is_cpp11}:cxx_std_11>
            $<${bde_ufid_is_cpp14}:cxx_std_14>
            $<${bde_ufid_is_cpp17}:cxx_std_17>
    )

    bde_interface_target_compile_options(
        ${iface}
        PUBLIC
            $<$<CXX_COMPILER_ID:AppleClang>:
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -fPIC>
            >
            $<$<CXX_COMPILER_ID:Clang>:
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -fPIC>
            >
            $<$<CXX_COMPILER_ID:GNU>:
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -fPIC>
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -xcode=pic32>
            >
            $<$<CXX_COMPILER_ID:XL>:
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -qpic>
                $<${bde_ufid_is_mt}: -qthreaded>

                $<IF:${bde_ufid_is_exc},
                    -qeh -qlanglvl=newexcp,
                    -qnoeh
                >
            >
    )

    bde_interface_target_compile_definitions(
        ${iface}
        PUBLIC
            BDE_BUILD_TARGET_MT
            $<$<CONFIG:Release>:
                BDE_BUILD_TARGET_OPT
            >
            $<$<CONFIG:RelWithDebInfo>:
                BDE_BUILD_TARGET_OPT
            >
            $<$<CONFIG:Debug>:
                BDE_BUILD_TARGET_DBG
            >

            $<${bde_ufid_is_mt}:BDE_BUILD_TARGET_MT>
            $<${bde_ufid_is_shr}:BDE_BUILD_TARGET_SHR>
            $<${bde_ufid_is_cpp11}:BDE_BUILD_TARGET_CPP11>
            $<${bde_ufid_is_cpp14}:BDE_BUILD_TARGET_CPP14>
            $<${bde_ufid_is_cpp17}:BDE_BUILD_TARGET_CPP17>

            $<${bde_ufid_is_stlport}:BDE_BUILD_TARGET_STLPORT>

            $<${bde_ufid_is_ndebug}:
                NDEBUG
                BDE_BUILD_TARGET_NDEBUG
            >

            $<IF:${bde_ufid_is_exc},
                BDE_BUILD_TARGET_EXC,
                BDE_BUILD_TARGET_NO_EXC
            >

            $<${bde_ufid_is_safe}:
                BDE_BUILD_TARGET_SAFE
                BDE_DONT_ALLOW_TRANSITIVE_INCLUDES
            >
            $<${bde_ufid_is_safe2}:
                BDE_BUILD_TARGET_SAFE_2
                BDE_DONT_ALLOW_TRANSITIVE_INCLUDES
            >
    )

    bde_interface_target_compile_options(
        ${iface}
        PRIVATE
            $<$<CXX_COMPILER_ID:AppleClang>:
                $<IF:${bde_ufid_is_exc},
                    -fexceptions,
                    -fno-exceptions
                >
            >
            $<$<CXX_COMPILER_ID:Clang>:
                $<IF:${bde_ufid_is_exc},
                    -fexceptions,
                    -fno-exceptions
                >
                # Warnings
                -Waddress
                -Wall
                -Wcast-align
                -Wcast-qual
                -Wconversion
                -Wextra
                -Wformat
                -Wformat-security
                -Wformat-y2k
                -Winit-self
                -Wlarger-than-100000
                -Woverflow
                -Wpacked
                -Wparentheses
                -Wpointer-arith
                -Wsign-compare
                -Wstrict-overflow=1
                -Wtype-limits
                -Wvla
                -Wvolatile-register-var
                -Wwrite-strings
                -Wno-char-subscripts
                -Wno-long-long
                -Wno-sign-conversion
                -Wno-string-conversion
                -Wno-unknown-pragmas
                -Wno-unused-value
            >
            $<$<CXX_COMPILER_ID:GNU>:
                $<${bde_ufid_is_opt}:
                    -fno-gcse
                >

                $<IF:${bde_ufid_is_exc},
                    -fexceptions,
                    -fno-exceptions
                >
                # Warnings
                -Waddress
                -Wall
                -Wcast-align
                -Wcast-qual
                -Wconversion
                -Wextra
                -Wformat
                -Wformat-security
                -Wformat-y2k
                -Winit-self
                -Wlarger-than-100000
                -Wlogical-op
                -Woverflow
                -Wpacked
                -Wparentheses
                -Wpointer-arith
                -Wsign-compare
                -Wstrict-overflow=1
                -Wtype-limits
                -Wvla
                -Wvolatile-register-var
                -Wwrite-strings
                -Wno-char-subscripts
                -Wno-long-long
                -Wno-sign-conversion
                -Wno-unknown-pragmas
                -Wno-unused-value
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                # deletion of pointer to incomplete type
                /we4150
                # default constructor could not be generated
                /wd4510
                # default constructor could not be generated
                /wd4610
                # A member of a class template is not defined
                /wd4661
                # not all control paths return a value
                /we4715
                $<IF:${bde_ufid_is_exc},
                    /EHsc,
                    /EHs-
                >
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                $<${bde_ufid_is_mt}:
                    -mt
                >
                $<IF:${bde_ufid_is_exc},
                    -features=except,
                    -features=no%except
                >
                $<${bde_ufid_is_stlport}:
                    -library=stlport4
                    -template=no%extdef
                >
            >
            $<$<CXX_COMPILER_ID:XL>:
                $<${bde_ufid_is_mt}: -qthreaded>

                $<IF:${bde_ufid_is_exc},
                    -qeh -qlanglvl=newexcp,
                    -qnoeh
                >
            >
    )
    bde_interface_target_compile_definitions(
        ${iface}
        PRIVATE
            BDE_BUILD_TARGET_MT

            $<$<CONFIG:Release>:
                BDE_BUILD_TARGET_OPT
            >
            $<$<CONFIG:RelWithDebInfo>:
                BDE_BUILD_TARGET_OPT
            >
            $<$<CONFIG:Debug>:
                BDE_BUILD_TARGET_DBG
            >

            $<${bde_ufid_is_mt}:BDE_BUILD_TARGET_MT>
            $<${bde_ufid_is_shr}:BDE_BUILD_TARGET_SHR>
            $<${bde_ufid_is_cpp11}:BDE_BUILD_TARGET_CPP11>
            $<${bde_ufid_is_cpp14}:BDE_BUILD_TARGET_CPP14>
            $<${bde_ufid_is_cpp17}:BDE_BUILD_TARGET_CPP17>

            $<${bde_ufid_is_stlport}:BDE_BUILD_TARGET_STLPORT>

            $<${bde_ufid_is_ndebug}:
                NDEBUG
                BDE_BUILD_TARGET_NDEBUG
            >

            $<IF:${bde_ufid_is_exc},
                BDE_BUILD_TARGET_EXC,
                BDE_BUILD_TARGET_NO_EXC
            >

            $<${bde_ufid_is_safe}:
                BDE_BUILD_TARGET_SAFE
                BDE_DONT_ALLOW_TRANSITIVE_INCLUDES
                _STLP_EXTRA_OPERATORS_FOR_DEBUG=1
            >
            $<${bde_ufid_is_safe2}:
                BDE_BUILD_TARGET_SAFE_2
                BDE_DONT_ALLOW_TRANSITIVE_INCLUDES
                _STLP_EXTRA_OPERATORS_FOR_DEBUG=1
            >

            # Compiler specific defines
            $<$<CXX_COMPILER_ID:AppleClang>:
            >

            $<$<CXX_COMPILER_ID:Clang>:
            >

            $<$<CXX_COMPILER_ID:GNU>:
                $<${bde_ufid_is_cpp14}:
                    _FILE_OFFSET_BITS=64
                >
                $<${bde_ufid_is_cpp17}:
                    _FILE_OFFSET_BITS=64
                >
                $<${bde_ufid_is_mt}:
                    _REENTRANT
                    _POSIX_PTHREAD_SEMANTICS
                >
            >

            $<$<CXX_COMPILER_ID:MSVC>:
                NOGDI
                NOMINMAX
                _CRT_SECURE_NO_WARNINGS
                _SCL_SECURE_NO_DEPRECATE
                WIN32_LEAN_AND_MEAN
                VC_EXTRALEAN
                # Windows Server 2003 and later
                _WIN32_WINNT=0x0502
                WINVER=0x0502
            >

            $<$<CXX_COMPILER_ID:SunPro>:
                $<${bde_ufid_is_mt}:
                    _POSIX_PTHREAD_SEMANTICS
                >
            >
            $<$<CXX_COMPILER_ID:XL>:
                __NOLOCK_ON_INPUT
                __NOLOCK_ON_OUTPUT
                $<${bde_ufid_is_mt}:
                    _REENTRANT
                    _THREAD_SAFE
                >
            >
    )
    # target libraries and additional platfrom link flags
    if(NOT WIN32)
        find_package(Threads REQUIRED)
    endif()

    bde_interface_target_link_libraries(
        ${iface}
        PUBLIC
            $<$<CXX_COMPILER_ID:AppleClang>:
                stdc++
                Threads::Threads
            >
            $<$<CXX_COMPILER_ID:Clang>:
                rt
                stdc++
                Threads::Threads
            >
            $<$<CXX_COMPILER_ID:GNU>:
                rt
                Threads::Threads
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                -nologo
                -incremental:no
                -subsystem:console 
                $<IF:${bde_ufid_is_64}, -machine:X64, -machine:ix86>
                Ws2_32
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                rt
                Threads::Threads
                $<${bde_ufid_is_shr}:
                   Cstd
                   Crun
                   c
                   m
                   sunmath
                >
                $<${bde_ufid_is_stlport}:-library=stlport4>
            >
            $<$<CXX_COMPILER_ID:XL>:
                Threads::Threads
                $<IF:${bde_ufid_is_64}, -q64, -q32>
            >
    )
endfunction()

function(bde_process_ufid)
    if( NOT UFID )
        message(WARNING "UFID is not defined.")
        message(STATUS  "Setting default UFID to 'opt_mt_exc'.")
        set(UFID "opt_mt_exc" CACHE STRING "UFID for the project")
    endif()

    bde_parse_ufid(${UFID})
endfunction()
