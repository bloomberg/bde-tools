include_guard()

# Set base environment variables for Bloomberg environment
if (NOT DEFINED DISTRIBUTION_REFROOT)
    if (DEFINED ENV{DISTRIBUTION_REFROOT})
        set(DISTRIBUTION_REFROOT "$ENV{DISTRIBUTION_REFROOT}/" CACHE STRING "BB Dpkg root set from environment variable.")
    endif()
endif()

if (DEFINED DISTRIBUTION_REFROOT)
    find_program(PKG_CONFIG_EXECUTABLE pkg-config PATHS
      ${DISTRIBUTION_REFROOT}/opt/bb/lib/bin
      /opt/bb/lib/bin
      NO_SYSTEM_ENVIRONMENT_PATH
      NO_DEFAULT_PATH)

  if (NOT ${PKG_CONFIG_EXECUTABLE})
        find_program(PKG_CONFIG_EXECUTABLE pkg-config)
        if (NOT ${PKG_CONFIG_EXECUTABLE})
            message(STATUS "pkg-config is not found; Dependency resolution might fail.")
        endif()
    endif()

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

    list(APPEND CMAKE_MODULE_PATH ${DISTRIBUTION_REFROOT}/opt/bb/share/plink ${DISTRIBUTION_REFROOT}/opt/bb/share/cmake/Modules)
endif()
