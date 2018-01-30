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

if(BDE_UFID_INCLUDED)
    return()
endif()
set(BDE_UFID_INCLUDED true)

include(bde_interface_target)
include(bde_utils)

# :: bde_ufid_filter ::
# -----------------------------------------------------------------------------
function(bde_ufid_filter target_ufid ufid_flags filter_list)
    bde_assert_no_extra_args()

    set(filtered_ufid "")

    foreach(flag IN LISTS filter_list)
        if(${flag} IN_LIST ufid_flags)
            list(APPEND filtered_ufid "${flag}")
        endif()
    endforeach()
    string(REPLACE ";" "_" filtered_ufid "${filtered_ufid}")
    set(${target_ufid} ${filtered_ufid} PARENT_SCOPE)
endfunction()

# :: bde_parse_ufid ::
# -----------------------------------------------------------------------------
function(bde_parse_ufid UFID)
    bde_assert_no_extra_args()

    string(REGEX MATCHALL "[^-_]+" ufid_flags "${UFID}")

    # Check for duplicates
    set(unique_ufid_flags ${ufid_flags})
    list(REMOVE_DUPLICATES unique_ufid_flags)

    if(NOT "${unique_ufid_flags}" STREQUAL "${ufid_flags}")
        message(FATAL_ERROR "UFID ${UFID} contains duplicates.")
    endif()

    # These flags form potential installation prefix
    set(install_ufid_flags opt dbg exc mt 64 safe safe2 pic shr)
    set(known_ufid_flags ${install_ufid_flags} ndebug cpp11 cpp14)

    foreach(flag IN LISTS ufid_flags)
        if (NOT ${flag} IN_LIST known_ufid_flags)
            message(
                FATAL_ERROR
                "${flag} is not a valid UFID element in ${UFID}."
            )
        endif()
    endforeach()

    # Check for conflicts in standard
    if (cpp11 IN_LIST ufid_flags AND cpp14 IN_LIST ufid_flags)
        message(FATAL_ERROR "UFID ${UFID} both cpp11 and cpp14 flags.")
    endif()

    # Setting the flags in local...
    foreach(flag IN LISTS known_ufid_flags)
        set(bde_ufid_is_${flag} 0)
        if(${flag} IN_LIST ufid_flags)
            set(bde_ufid_is_${flag} 1)
        endif()
    endforeach()

    if(${bde_ufid_is_shr})
        # Shared libraries must use PIC.
        set(bde_ufid_is_pic 1)
    endif()

    # ... and in parent scope. Cmake details.
    foreach(flag IN LISTS known_ufid_flags)
        set(bde_ufid_is_${flag} ${bde_ufid_is_${flag}} PARENT_SCOPE)
    endforeach()

    bde_ufid_filter(bde_canonical_ufid "${ufid_flags}" "${known_ufid_flags}")
    set(bde_canonical_ufid ${bde_canonical_ufid} PARENT_SCOPE)

    bde_ufid_filter(bde_install_ufid "${ufid_flags}" "${install_ufid_flags}")
    set(bde_install_ufid ${bde_install_ufid} PARENT_SCOPE)

    # Setting install lib suffix based on build bitness.
    set(bde_install_lib_suffix "lib")
    if(${bde_ufid_is_64})
        string(CONCAT bde_install_lib_suffix ${bde_install_lib_suffix} "64")
    endif()
    set(bde_install_lib_suffix ${bde_install_lib_suffix} PARENT_SCOPE)
endfunction()

# :: bde_set_common_target_properties ::
# -----------------------------------------------------------------------------
function(bde_set_common_target_properties)
    bde_assert_no_extra_args()

    bde_add_interface_target(bde_ufid_flags)

    # Set up shared/static library build
    if(${bde_ufid_is_shr})
        set(BUILD_SHARED_LIBS ON PARENT_SCOPE)
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

    message(STATUS "Setting build type to ${build_type}.")
    set(CMAKE_BUILD_TYPE ${build_type} CACHE STRING "Build type" FORCE)

    bde_interface_target_compile_features(
        bde_ufid_flags
        PUBLIC
            $<${bde_ufid_is_cpp11}:cxx_std_11>
            $<${bde_ufid_is_cpp14}:cxx_std_14>
    )

    bde_interface_target_compile_options(
        bde_ufid_flags
        PUBLIC
            $<$<CXX_COMPILER_ID:Clang>:
                $<IF:${bde_ufid_is_64}, -m64, -m32>
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -fPIC>
            >
            $<$<CXX_COMPILER_ID:GNU>:
                $<IF:${bde_ufid_is_64}, -m64, -m32>
                $<$<OR:${bde_ufid_is_shr},${bde_ufid_is_pic}>: -fPIC>
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                /bigobj
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                # 'dbg' and 'opt' flags must be handeled separately as they can
                # be both valid.
                $<${bde_ufid_is_dbg}: -g0 -xdebugformat=stabs>
                $<${bde_ufid_is_opt}: -O>
                $<IF:${bde_ufid_is_64}, -m64, -m32>
            >
            $<$<CXX_COMPILER_ID:XL>:
                -fno-strict-aliasing
                -qalias=noansi
                -qarch=pwr6
                -qrtti=all
                -qtbtable=small
                -qtls
                -qtune=pwr7
                -qxflag=dircache:71,100
                -qxflag=inlinewithdebug:stepOverInline
                -qxflag=noautoinline
                -qxflag=tocrel
                -qxflag=v6align
                -qxflag=FunctionCVTmplArgDeduction2011
                -qxflag=UnwindTypedefInClassDecl

                $<${bde_ufid_is_mt}: -qthreaded>

                $<IF:${bde_ufid_is_exc},
                    -qeh -qlanglvl=newexcp,
                    -qnoeh
                >
            >
    )

    bde_interface_target_compile_definitions(
        bde_ufid_flags
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

            # Compiler specific definitions
            $<$<CXX_COMPILER_ID:Clang>:
                $<${bde_ufid_is_mt}:
                    _POSIX_PTHREAD_SEMANTICS
                    _REENTRANT
                >
            >
            $<$<CXX_COMPILER_ID:GNU>:
                $<${bde_ufid_is_mt}:
                    _POSIX_PTHREAD_SEMANTICS
                    _REENTRANT
                >
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                NOGDI
                NOMINMAX
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
                    _REENTRANT
                    _PTHREADS
                >
                _RWSTD_COMPILE_INSTANTIATE=1
                __FUNCTION__=__FILE__

            >
            $<$<CXX_COMPILER_ID:XL>:
                $<${bde_ufid_is_mt}:
                    _POSIX_PTHREAD_SEMANTICS
                    _REENTRANT
                    _PTHREADS
                    _THREAD_SAFE
                >
            >
    )

    bde_interface_target_compile_options(
        bde_ufid_flags
        PRIVATE
            $<$<CXX_COMPILER_ID:Clang>:
                -fno-strict-aliasing
                $<IF:${bde_ufid_is_exc},
                    -fexceptions,
                    -fno-exceptions
                >
            >
            $<$<CXX_COMPILER_ID:GNU>:
                -fno-strict-aliasing
                -fdiagnostics-show-option
                --param ggc-min-expand=30
                $<${bde_ufid_is_opt}:
                    -fno-gcse
                    # Warnings
                    -Waddress
                    -Wall
                    -Wcast-align
                    -Wcast-qual
                    -Wconversion
                    -Werror=cast-qual
                    -Wextra
                    -Wformat
                    -Wformat-security
                    -Wformat-y2k
                    -Winit-self
                    -Wlarger-than-100000
                    -Wlogical-op
                    -Wno-char-subscripts
                    -Wno-long-long
                    -Wno-sign-conversion
                    -Wno-unknown-pragmas
                    -Wno-unused-value
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
                >
                $<IF:${bde_ufid_is_exc},
                    -fexceptions,
                    -fno-exceptions
                >
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                /GS-
                /GT
                /GR
                # Multiprocessor compilation
                /MP
                # Generate intrinsic functions
                /Oi
                # deletion of pointer to incomplete type
                /wd4150
                # default constructor could not be generated
                /wd4510
                # default constructor could not be generated
                /wd4610
                # A member of a class template is not defined
                /wd4661
                # not all control paths return a value
                /we4715
                $<$<NOT:${bde_ufid_is_exc}>:
                    /EHs-
                >
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                -library=no%rwtools7
                -temp=/bb/data/tmp
                -xannotate=no
                -xtarget=generic
                -xthreadvar=dynamic
                $<${bde_ufid_is_mt}:
                    -mt
                >
                $<IF:${bde_ufid_is_exc},
                    -features=except,
                    -features=no%except
                >
                $<${bde_ufid_is_pic}:
                    -xcode=pic32
                >
            >
            $<$<CXX_COMPILER_ID:XL>:
                -fno-strict-aliasing
                -qalias=noansi
                -qarch=pwr6
                -qdebug=nparseasm
                -qfuncsect
                -qlanglvl=staticstoreoverlinkage
                -qnotempinc
                -qrtti=all
                -qsuppress=1500-029
                -qsuppress=1540-2910
                -qsuppress=1501-201
                -qtbtable=small
                -qtls
                -qtune=pwr7
                -qxflag=dircache:71,100
                -qxflag=inlinewithdebug:stepOverInline
                -qxflag=noautoinline
                -qxflag=tocrel
                -qxflag=v6align
                -qxflag=FunctionCVTmplArgDeduction2011
                -qxflag=UnwindTypedefInClassDecl

                $<${bde_ufid_is_mt}: -qthreaded>

                $<IF:${bde_ufid_is_exc},
                    -qeh -qlanglvl=newexcp,
                    -qnoeh
                >
            >
    )
    bde_interface_target_compile_definitions(
        bde_ufid_flags
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
            $<$<CXX_COMPILER_ID:Clang>:
            >
            $<$<CXX_COMPILER_ID:GNU>:
            >
            $<$<CXX_COMPILER_ID:MSVC>:
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                _POSIX_PTHREAD_SEMANTICS
                _PTHREADS
            >
            $<$<CXX_COMPILER_ID:XL>:
                $<${bde_ufid_is_mt}: _THREAD_SAFE>
            >
    )
    # target libraries and additional platfrom link flags
    if(NOT WIN32)
        find_package(Threads REQUIRED)
    endif()

    bde_interface_target_link_libraries(
        bde_ufid_flags
        PUBLIC
            $<$<CXX_COMPILER_ID:Clang>:
                rt
                stdc++
                Threads::Threads
                $<IF:${bde_ufid_is_64}, -m64, -m32>
            >
            $<$<CXX_COMPILER_ID:GNU>:
                rt
                Threads::Threads
                $<IF:${bde_ufid_is_64}, -m64, -m32>
            >
            $<$<CXX_COMPILER_ID:MSVC>:
                Ws2_32
            >
            $<$<CXX_COMPILER_ID:SunPro>:
                rt
                Threads::Threads
                $<IF:${bde_ufid_is_64}, -m64, -m32>
            >
            $<$<CXX_COMPILER_ID:XL>:
            >
    )
endfunction()

macro(bde_process_ufid)
    if( NOT UFID )
        message(WARNING "UFID is not defined.")
        message(STATUS  "Setting default UFID to 'opt_mt_exc'.")
        set(UFID "opt_mt_exc" CACHE STRING "UFID for the project")
    endif()

    bde_parse_ufid(${UFID})
    bde_set_common_target_properties()
endmacro()
