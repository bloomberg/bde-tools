## bde_project.cmake
## ~~~~~~~~~~~~~~~~~
#
## OVERVIEW
## ---------
# This module exposes methods to build application and groups library that are
# organized following the BDE physical layout. It must be included only once
# per solution.
#
# The main exposed functions are the following ones (refer to their individual
# documentation for more information about each):
#  o bde_project_initialize
#  o bde_project_setup
#  o bde_project_add_group
#  o bde_project_add_standalone
#  o bde_project_add_application
#
# Other functions of public interest:
#  o bde_project_print_summary
#  o bde_project_append_compile_definitions
#  o bde_project_flags_builder
#
## USAGE EXAMPLE
## -------------
# The main CMakeLists.txt solution should follow this skeleton:
#..
#:  include( bde_project )
#:
#:  project( XYZ NONE ) # Replace XYZ by the project name..
#:
#:  bde_project_initialize()
#:
#:  # Perform any project's specific configuration, such as tweaking the
#:  # compiler flags (with the help of functions like
#:  # 'bde_project_flags_builder', 'bde_project_append_compile_definitions', ...)
#:
#:  bde_project_setup()
#:
#:  # Use 'add_directory' to include any application / groups CMakeLists.txt;
#:  # include order *MUST* be in dependency order, lower to higher level.
#:  # The application/groups CMakeLists.txt can simply call
#:    'bde_project_add_group', 'bde_project_add_standlone', or
#:    'bde_project_add_application'.
#:
#:  bde_project_print_summary() # Optional
#..
#
## NOTE
## ----
#  o The bde_project system supports and exposes two build modes "Development"
#    and "Production", and is compatible with all supported plateforms at
#    Bloomberg ('AIX', 'Solaris' and 'Linux') both 32 and 64 bits.
#  o It is designed to be extremely easy to use for the standard case of a
#    library/application perfectly following the BDE physical layout
#    organization (a single function call can get everything setup); while
#    still offering enough flexibility for the atypical configuration to be
#    setup (the high level 'bde_project_add_group',
#    'bde_project_add_standalone, and 'bde_project_add_application' are meta
#    functions leveraging the other lower level helper functions; one may
#    always use those building blocks directly to build a customized support
#    for his project's specifics).
#
## ========================================================================= ##

if(BDE_PROJECT_INCLUDED)
    #message(FATAL_ERROR "'bde_project' was already included")
    return()
endif()
set(BDE_PROJECT_INCLUDED true)

# BDE CMake modules.
include(bde_uor)
include(bde_log)
include(bde_default_process)
include(CMakeParseArguments)

# External packages
find_package(PkgConfig)

# :: bde_project_summary ::
# -----------------------------------------------------------------------------
# Print a summary containing the various configuration parameters, overlays
# used and versions of libraries found.

function(bde_project_summary)
    bde_log(NORMAL "=========================================")
    bde_log(NORMAL "=====            SUMMARY            =====")
    bde_log(NORMAL "=========================================")
    bde_log(NORMAL " RefRoot..........: ${DISTRIBUTION_REFROOT}")
    bde_log(NORMAL " BuildType........: ${CMAKE_BUILD_TYPE}")
    bde_log(NORMAL " UFID.............: ${UFID}")
    bde_log(NORMAL " Canonical UFID...: ${bde_canonical_ufid}")
    bde_log(NORMAL " Install UFID.....: ${bde_install_ufid}")
    bde_log(NORMAL " Install lib path.: ${bde_install_lib_suffix}")
    bde_log(NORMAL "=========================================")
endfunction()

function(_bde_process_uor_list outAllInfoTargets uorList intermediateDir type)
    set(allInfoTargets)
    foreach(uor ${uorList})
        bde_log(NORMAL "Processing ${uor} as ${type}")
        bde_default_process_uor(
            uorInfoTarget
            ${uor}
            ${intermediateDir}
            ${type}
            ${ARGN}
        )
        list(APPEND allInfoTargets ${uorInfoTarget})
    endforeach()
    set(${outAllInfoTargets} ${allInfoTargets} PARENT_SCOPE)
endfunction()

function(bde_project_process_uors projName)
    cmake_parse_arguments(
        proj
        ""
        "COMMON_INTERFACE_TARGET"
        "PACKAGE_GROUPS;APPLICATIONS;STANDALONE_PACKAGES"
        ${ARGN}
    )

    _bde_process_uor_list(
        groupInfoTargets "${proj_PACKAGE_GROUPS}" group package_group
    )
    _bde_process_uor_list(
        pkgInfoTargets "${proj_STANDALONE_PACKAGES}" package standalone_package
    )
    _bde_process_uor_list(
        appInfoTargets "${proj_APPLICATIONS}" package application
    )

    # Join information from all UORs
    set(properties TARGET DEPENDS TEST_TARGETS)

    foreach(infoTarget ${groupInfoTargets} ${pkgInfoTargets} ${appInfoTargets})
        foreach(prop ${properties})
            bde_info_target_get_property(value ${infoTarget} ${prop})
            list(APPEND all_${prop} ${value})
        endforeach()

        if (proj_COMMON_INTERFACE_TARGET)
            bde_info_target_get_property(
                interfaceTargets ${infoTarget} INTERFACE_TARGETS
            )
            foreach(interfaceTarget ${interfaceTargets})
                bde_interface_target_assimilate(
                    ${interfaceTarget} ${proj_COMMON_INTERFACE_TARGET}
                )
            endforeach()
            bde_info_target_append_property(
                ${infoTarget} INTERFACE_TARGETS ${proj_COMMON_INTERFACE_TARGET}
            )
        endif()
        bde_install_uor(${infoTarget})
    endforeach()

    # Build project info target
    bde_info_target_append_property(${projName} TARGETS ${all_TARGET})
    bde_info_target_append_property(${projName} DEPENDS "${all_DEPENDS}")

    if(all_TEST_TARGETS)
        bde_info_target_get_property(testTarget ${projName} TEST_TARGET)
        if(NOT testTarget)
            set(testTarget ${projName}.t)
            add_custom_target(${testTarget})
            bde_info_target_set_property(${projName} TEST_TARGET ${testTarget})
        endif()
        add_dependencies(${testTarget} ${all_TEST_TARGETS})
    endif()
endfunction()

# :: bde_import_target_raw_library ::
# -----------------------------------------------------------------------------
# The function tries to find the static library by name.
# If the library is found the function creates imported interface target
# that can be used in target_link_libraries().
function(bde_import_target_raw_library libName)
    # The dependency was resolved already.
    if (TARGET ${libName})
        return()
    endif()

    bde_log(VERBOSE "Searching raw library: ${libName}")
    # find_library is limited to search only in the specified
    # distribution refroot directory.

    # TODO: Might add the hints for lookup path.
    set(libraryPath "${DISTRIBUTION_REFROOT}/opt/bb/${bde_install_lib_suffix}")

    find_library(
        rawLib_${libName}
        NAMES
            lib${libName}.${bde_install_ufid}${CMAKE_STATIC_LIBRARY_SUFFIX}
            lib${libName}${CMAKE_STATIC_LIBRARY_SUFFIX}
        HINTS
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

# :: bde_import_target_from_pc ::
# -----------------------------------------------------------------------------
# The function tries to find the static library using the pkg-config file(s)
# If the library is found the function creates an imported target that
# can be used in target_link_libraries(). The imported target has necessary
# transitive dependencies.
# The function returns a list of additional dependencies found in
# the .pc file.
function(bde_import_target_from_pc outDeps depName)
    # The dependency was resolved already.
    if (TARGET ${depName})
        return()
    endif()

    if(NOT ${PKG_CONFIG_FOUND})
        return()
    endif()

    # TODO: Might add the hints for lookup path and .pc file patterns.
    set(libraryPath "${DISTRIBUTION_REFROOT}/opt/bb/${bde_install_lib_suffix}")

    # The SYSROOT_DIR will be added by pkg config to the library and include pathes
    # by pkg-config.
    set(ENV{PKG_CONFIG_SYSROOT_DIR} "${DISTRIBUTION_REFROOT}")
    # This is a location for .pc files.
    set(ENV{PKG_CONFIG_PATH} "${libraryPath}/pkgconfig")

    foreach(pcName "${depName}.${bde_install_ufid}"
                   "lib${depName}.${bde_install_ufid}"
                   "${depName}lib.${bde_install_ufid}"
                    "${depName}"
                   "lib${depName}"
                   "${depName}lib")
        pkg_check_modules(${depName}_pc QUIET "${pcName}")

        if(${depName}_pc_FOUND)
            break()
        endif()
    endforeach()

    set(staticDeps)

    if(${depName}_pc_FOUND)
        # STATIC_LIBRARIES contains transitive dependencies
        set(staticDeps "${${depName}_pc_STATIC_LIBRARIES}")

        set(searchHints "NO_CMAKE_PATH;NO_CMAKE_ENVIRONMENT_PATH")

        foreach(flag IN LISTS ${depName}_pc_LDFLAGS)
            if(flag MATCHES "^-L(.*)")
                # only look into the given paths from now on
                set(searchHints HINTS ${CMAKE_MATCH_1} NO_DEFAULT_PATH)
                continue()
            endif()
            if(flag MATCHES "^-l(.*)")
                set(pkgName "${CMAKE_MATCH_1}")
                if(TARGET pkgName)
                    continue()
                endif()
            else()
                message(WARNING "Unknown flag is found in .pc file ${${depName}_pc_LDFLAGS}")
                continue()
            endif()

            # Searching raw library
            if ((pkgName STREQUAL depName)
                AND NOT TARGET ${depName})
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

                    if(${depName}_pc_INCLUDE_DIRS)
                        set_property(
                            TARGET ${depName}
                            PROPERTY
                                INTERFACE_INCLUDE_DIRECTORIES "${${depName}_pc_INCLUDE_DIRS}"
                        )
                    endif()

                    set_property(
                        TARGET ${depName}
                        PROPERTY
                        IMPORTED_LOCATION "${rawLib_${depName}}"
                    )

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
                endif()
                break()
            endif()
        endforeach()

        set(${outDeps} ${staticDeps} PARENT_SCOPE)
    endif()
endfunction()

# :: bde_resolve_external_dependencies ::
# -----------------------------------------------------------------------------
# The function tries to resolve all external dependencies in the following
# order:
# 1. CMake config
# 2. .pc file
# 3. Raw static library.
#
# If the dependency (library) is found, the library is added to the link
# line (the order is maintained using dependency information found in the
# CMake config or .pc files)
# If the dependency (library) is not found, the '-l<depName>' line is added
# to the link line.
function(bde_resolve_external_dependencies externalDeps)
    set(deps ${externalDeps})

    while(deps)
        list(REMOVE_DUPLICATES deps)
        set(currentDeps "${deps}")
        set(deps)

        bde_log(VERBOSE "Active dependencies: ${currentDeps}")

        foreach(depName IN LISTS currentDeps)
            if(TARGET ${depName})
                continue()
            endif()

            bde_log(VERBOSE "Processing ${depName}")

            # Looking up CMake export for the external dependency.
            find_package(
                ${depName} QUIET
                PATH_SUFFIXES "${bde_install_lib_suffix}/${bde_install_ufid}/cmake"
            )

            if(TARGET ${depName})
                continue()
            endif()

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

            # The external dependancy is not found. Creating fake target to stop lookup.
            # Unresolved dependencies will be added as-is with '-l' flag to the link line.
            message(STATUS  "Not found (raw) external dependency '${depName}'")
            add_custom_target(${depName})
        endforeach()
    endwhile()
endfunction()

# Resolve all external dependencies and add all.t test target
# Takes in all project names
function(bde_finalize_projects)
    set(properties TARGETS DEPENDS TEST_TARGET)

    foreach(proj ${ARGN})
        foreach(prop ${properties})
            bde_info_target_get_property(value ${proj} ${prop})
            list(APPEND all_${prop} ${value})
        endforeach()
    endforeach()

    # Detect which dependencies are external to this project
    list(REMOVE_ITEM all_DEPENDS ${all_TARGETS})
    list(REMOVE_DUPLICATES all_DEPENDS)

    if (all_DEPENDS)
        bde_log(NORMAL "Resolving EXTERNAL dependencies: ${all_DEPENDS}.")
        bde_resolve_external_dependencies("${all_DEPENDS}")
    else()
        bde_log(NORMAL "All dependencies were resolved internally.")
    endif()

    if(all_TEST_TARGET)
        add_custom_target(all.t)
        add_dependencies(all.t ${all_TEST_TARGET})
    endif()

    bde_project_summary()
endfunction()

function(bde_default_process_project outInfoTarget rootDir)
    bde_default_process(
        "${rootDir}/project.cmake"
        bde_default_process_project
        infoTarget
        ${rootDir}
    )

    if(infoTarget)
        set(${outInfoTarget} ${infoTarget} PARENT_SCOPE)
    else()
        bde_log(NORMAL "${rootDir} does not seem to contain a valid BDE-style project.")
    endif()
endfunction()

macro(bde_process_workspace)
    # macro and not a function because enable_testing()
    # should be called at top level

    enable_testing()

    include(bde_utils)
    include(bde_ufid)

    set(projInfoTargets)
    bde_process_ufid()
    foreach(dir ${ARGN})
        bde_default_process_project(projInfoTarget ${dir})
        list(APPEND projInfoTargets ${projInfoTarget})
    endforeach()

    bde_finalize_projects(${projInfoTargets})
endmacro()
