include(bde_include_guard)
bde_include_guard()

include(bde_log)
include(bde_utils)
include(bde_pkgconfig_utils)

find_program(PKG_CONFIG_EXECUTABLE pkg-config PATHS
    ${CMAKE_PREFIX_PATH}/${CMAKE_INSTALL_LIBDIR}/bin
    /opt/bb/${CMAKE_INSTALL_LIBDIR}/bin
    NO_DEFAULT_PATH)

# Initialize pkg config module
find_package(PkgConfig)

# :: bde_import_target_raw_library ::
# -----------------------------------------------------------------------------
# The function tries to find the static library by name.
# If the library is found the function creates imported interface target
# that can be used in target_link_libraries().
function(bde_import_target_raw_library libName)
    bde_assert_no_extra_args()

    # The dependency was resolved already.
    if (TARGET ${libName})
        return()
    endif()

    bde_log(VERBOSE "Searching raw library: ${libName}")
    # find_library is limited to search only in the specified
    # distribution refroot directory.

    # TODO: Might add the hints for lookup path.
    set(libraryPath "${CMAKE_PREFIX_PATH}/${CMAKE_INSTALL_LIBDIR}")

    find_library(
        rawLib_${libName}
        NAMES
            lib${libName}.${bde_install_ufid}${CMAKE_STATIC_LIBRARY_SUFFIX}
            lib${libName}${CMAKE_STATIC_LIBRARY_SUFFIX}
        PATHS
            "${libraryPath}"
        NO_DEFAULT_PATH
    )
    if(rawLib_${libName})
        bde_log(VERBOSE "Found(raw): ${rawLib_${libName}}")
        add_library(${libName} INTERFACE IMPORTED)
        set_property(
            TARGET ${libName}
            PROPERTY
                INTERFACE_LINK_LIBRARIES "${rawLib_${libName}}"
        )
    endif()
endfunction()

# :: bde_load_conan_build_info ::
# -----------------------------------------------------------------------------
# The function tries to detect the use of conan and loads the
# 'conan_build_info.cmake' file into memory
function(bde_load_conan_build_info)
    if (TARGET "CONAN_PKG::bde-tools")
        message(STATUS "Conan package already loaded")
        return()
    endif()

    set(CONAN_BUILD_INFO ${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
    if (EXISTS ${CONAN_BUILD_INFO})
        message(STATUS "Found ${CMAKE_BINARY_DIR}/conanbuildinfo.cmake")
        include(${CONAN_BUILD_INFO})
        conan_basic_setup(TARGETS)
    endif()
endfunction()

# :: bde_resolve_external_dependency_conan ::
# -----------------------------------------------------------------------------
# The function tries to resolve a single dependency using conan targets.  The
# main purpose of the function is to resolve the disparity of target names, and
# work around the current limitation in the conan cmake generator creating
# non-global targets that cannot be aliased
function(bde_resolve_external_dependency_conan depName)
    bde_assert_no_extra_args()

    set(conanDep "CONAN_PKG::${depName}")
    if (TARGET ${conanDep})
        bde_log(VERBOSE "Found dependency ${depName} in conan")

        # After https://github.com/conan-io/conan/issues/3482 is resolved this
        # should be just an alias
        add_library(${depName} INTERFACE IMPORTED)
        target_link_libraries(${depName} INTERFACE ${conanDep})
        foreach(prop INTERFACE_LINK_LIBRARIES INTERFACE_INCLUDE_DIRECTORIES INTERFACE_COMPILE_DEFINITIONS INTERFACE_COMPILE_OPTIONS)
            get_property(tmpProp TARGET ${conanDep} PROPERTY ${prop})
            set_property(TARGET ${conanDep} PROPERTY ${prop} ${tmpProp})
        endforeach()
    endif()
endfunction()

# :: bde_import_target_from_pc ::
# -----------------------------------------------------------------------------
# The function tries to find the static library using the pkg-config file(s)
# If the library is found the function creates an imported target that
# can be used in target_link_libraries(). The imported target has necessary
# transitive dependencies.
# The function returns a list of additional dependencies found in
# the .pc file.
function(bde_import_target_from_pc retDeps depName)
    bde_assert_no_extra_args()

    # The dependency was resolved already.
    if (TARGET ${depName})
        bde_return()
    endif()

    if(NOT ${PKG_CONFIG_FOUND})
        bde_return()
    endif()

    # TODO: Might add the hints for lookup path and .pc file patterns.
    set(libraryPath "${CMAKE_PREFIX_PATH}/${CMAKE_INSTALL_LIBDIR}")

    # The SYSROOT_DIR will be added by pkg config to the library and include pathes
    # by pkg-config.
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "${DISTRIBUTION_REFROOT}")
    # This is a location for .pc files.
    set(ENV{PKG_CONFIG_PATH} "${libraryPath}/pkgconfig")

    bde_uor_to_pkgconfig_name(depPkgconfigName ${depName})

    foreach(pcName "${depPkgconfigName}.${bde_install_ufid}"
                   "${depPkgconfigName}"
                   "lib${depPkgconfigName}.${bde_install_ufid}"
                   "${depPkgconfigName}lib.${bde_install_ufid}"
            )

        pkg_check_modules(${depName}_pc
                          QUIET NO_CMAKE_PATH "${pcName}")

        if(${depName}_pc_FOUND)
            break()
        endif()
    endforeach()

    if(NOT ${depName}_pc_FOUND)
        bde_return()
    endif()

    # STATIC_LIBRARIES contains transitive dependencies
    set(staticDeps "${${depName}_pc_STATIC_LIBRARIES}")

    set(searchHints)

    foreach(flag IN LISTS ${depName}_pc_LDFLAGS)
        if(flag MATCHES "^-L(.*)")
            # only look into the given paths from now on
            list(APPEND searchHints PATHS ${CMAKE_MATCH_1})
            continue()
        endif()
    endforeach()

    if(searchHints)
        list(APPEND searchHints NO_DEFAULT_PATH)
    else()
        set(searchHints NO_CMAKE_PATH NO_CMAKE_ENVIRONMENT_PATH)
    endif()

    #bde_log(VERY_VERBOSE "Search hints: ${searchHints}")

    foreach(flag IN LISTS ${depName}_pc_LDFLAGS)
        if(flag MATCHES "^-l(.*)")
            set(pkgName "${CMAKE_MATCH_1}")
            if(TARGET pkgName)
                bde_log(VERY_VERBOSE "Skipping : ${pkgName}")
                continue()
            endif()

            if (pkgName STREQUAL depName)
                find_library(
                    rawLib_${depName}
                    NAMES
                        lib${depName}.${bde_install_ufid}${CMAKE_STATIC_LIBRARY_SUFFIX}
                        lib${depName}${CMAKE_STATIC_LIBRARY_SUFFIX}
                        ${searchHints}
                )

                if(rawLib_${depName})
                    list(REMOVE_ITEM staticDeps ${depName})

                    bde_log(VERBOSE "External dependency: ${depName}")
                    bde_log(VERBOSE "  Using: ${rawLib_${depName}}")
                    if (staticDeps)
                        bde_log(VERBOSE "  Depends on: ${staticDeps}")
                    endif()

                    add_library(${depName} UNKNOWN IMPORTED)

                    set_property(
                        TARGET ${depName}
                        PROPERTY
                        IMPORTED_LOCATION "${rawLib_${depName}}"
                    )
                endif()
                break()
            endif()
        endif()
    endforeach()

    # Handle headers-only library that does not have -L/-l
    if(NOT TARGET ${depName})
        add_library(${depName} INTERFACE IMPORTED)
    endif()

    if(${depName}_pc_INCLUDE_DIRS)
        set_property(
            TARGET ${depName}
            PROPERTY
                INTERFACE_INCLUDE_DIRECTORIES "${${depName}_pc_INCLUDE_DIRS}"
        )
    endif()

    if(staticDeps)
        set_property(
            TARGET ${depName}
            APPEND PROPERTY
                INTERFACE_LINK_LIBRARIES "${staticDeps}"
        )
    endif()

    if(${depName}_pc_FLAGS_OTHER)
        set_property(
            TARGET ${depName}
            PROPERTY
                INTERFACE_COMPILE_OPTIONS "${${depName}_pc_CFLAGS_OTHER}"
        )
    endif()

    bde_return(${staticDeps})
endfunction()

# :: bde_resolve_external_dependencies ::
# -----------------------------------------------------------------------------
# The function tries to resolve all external dependencies in the following
# order:
# 1. CMake config
# 2. Conan generated cmake target
# 3. .pc file
# 4. Raw static library.
#
# If the dependency (library) is found, the library is added to the link
# line (the order is maintained using dependency information found in the
# CMake config or .pc files)
# If the dependency (library) is not found, the '-l<depName>' line is added
# to the link line.
function(bde_resolve_external_dependencies externalDeps)
    bde_assert_no_extra_args()

    bde_load_conan_build_info()

    set(deps ${externalDeps})

    while(deps)
        list(REMOVE_DUPLICATES deps)
        set(currentDeps "${deps}")

        foreach(depName IN LISTS currentDeps)
            if(depName AND TARGET ${depName})
                list(REMOVE_ITEM currentDeps ${depName})
            endif()
        endforeach()

        set(deps)

        bde_log(VERBOSE "Active dependencies: ${currentDeps}")

        foreach(depName IN LISTS currentDeps)
            if(NOT depName OR TARGET ${depName})
                continue()
            endif()

            bde_log(VERBOSE "Processing ${depName}")

            # Checking if defined in conanfile
            bde_resolve_external_dependency_conan(${depName})
            if (NOT depName OR TARGET ${depName})
                continue()
            endif()

            # Looking up CMake export for the external dependency.
            find_package(
                ${depName}
                    NO_SYSTEM_ENVIRONMENT_PATH
                    NO_CMAKE_PACKAGE_REGISTRY
                    QUIET
                    PATH_SUFFIXES "${CMAKE_INSTALL_LIBDIR}/${bde_install_ufid}/cmake"
            )

            if(TARGET ${depName})
                bde_log(VERY_VERBOSE "CMake config found for ${depName} in ${CMAKE_PREFIX_PATH}/${CMAKE_INSTALL_LIBDIR}/${bde_install_ufid}/cmake")
                continue()
            endif()

            bde_log(VERY_VERBOSE "CMake config not found for ${depName} in ${CMAKE_PREFIX_PATH}/${CMAKE_INSTALL_LIBDIR}/${bde_install_ufid}/cmake")

            # CMake EXPORT set is not found. Trying pkg-config.
            set(newDeps)
            bde_import_target_from_pc(newDeps "${depName}")
            list(APPEND deps "${newDeps}")

            if(TARGET ${depName})
                continue()
            endif()

            bde_import_target_raw_library("${depName}")

            if(TARGET ${depName})
                continue()
            endif()

            # The external dependancy is not found.
            # Unresolved dependencies will be added as-is with '-l' flag to the link line.
            message(STATUS  "Not found (raw) external dependency '${depName}'")
        endforeach()
    endwhile()
endfunction()
