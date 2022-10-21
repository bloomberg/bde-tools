# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# SunOS, cc
#
# Set base environment variables for Bloomberg environment
if (DEFINED ENV{DISTRIBUTION_REFROOT})
    set(DISTRIBUTION_REFROOT "$ENV{DISTRIBUTION_REFROOT}/" CACHE STRING "BB Dpkg root set from environment variable.")

    find_program(PKG_CONFIG_EXECUTABLE pkg-config PATHS
      ${DISTRIBUTION_REFROOT}/opt/bb/lib/bin
      /opt/bb/lib/bin
      NO_SYSTEM_ENVIRONMENT_PATH)

    if (BDE_BUILD_TARGET_64)
        set(ROBO_PKG_CONFIG_PATH "${DISTRIBUTION_REFROOT}/opt/bb/lib64/robo/pkgconfig:${DISTRIBUTION_REFROOT}/opt/bb/lib64/pkgconfig" CACHE STRING "The location of the robo pkgconfig files.")
        set_property(GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS yes)
        set(CMAKE_INSTALL_LIBDIR lib64)
    else()
        set(ROBO_PKG_CONFIG_PATH "${DISTRIBUTION_REFROOT}/opt/bb/lib/robo/pkgconfig:${DISTRIBUTION_REFROOT}/opt/bb/lib/pkgconfig" CACHE STRING "The location of the robo pkgconfig files.")
        set_property(GLOBAL PROPERTY FIND_LIBRARY_USE_LIB64_PATHS no)
    endif()

    if (DEFINED ENV{PKG_CONFIG_PATH} AND NOT "$ENV{PKG_CONFIG_PATH}" MATCHES ".*${ROBO_PKG_CONFIG_PATH}$")
        message(STATUS "WARNING: Using user supplied PKG_CONFIG_PATH=$ENV{PKG_CONFIG_PATH}")
    endif()
    if (NOT "$ENV{PKG_CONFIG_PATH}" MATCHES ".*${ROBO_PKG_CONFIG_PATH}$")
        set(ENV{PKG_CONFIG_PATH} "$ENV{PKG_CONFIG_PATH}:${ROBO_PKG_CONFIG_PATH}")
    endif()

    set(ENV{PKG_CONFIG_SYSROOT_DIR} ${DISTRIBUTION_REFROOT})

    # Set the path for looking up includes, libs and files.
    list(APPEND CMAKE_SYSTEM_PREFIX_PATH ${DISTRIBUTION_REFROOT}/opt/bb)
endif()

set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS} "
       "-mt "
       "-xtarget=generic "
       "-xbuiltin=%all "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-features=rtti "
       "-Qoption ccfe "
       "-xglobalstatic "
       "-errtags=yes "
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS} "
       "-xtarget=generic "
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xthreadvar=dynamic "
       "-W0,-xglobalstatic "
       "-errtags=yes "
      )

string(CONCAT DEFAULT_EXE_LINKER_FLAGS
       ${DEFAULT_EXE_LINKER_FLAGS}
       "-temp=/bb/data/tmp "
       "-xannotate=no "
       "-xmemalign=8i "
       )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/cc-bde-presets.cmake")

set(CMAKE_CXX_FLAGS        ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS          ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-xO2 -g0"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-xO0 -g0"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-xO2"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-xO2"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-xO2 -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-xO0 -g"
    CACHE STRING "Debug"          FORCE)
