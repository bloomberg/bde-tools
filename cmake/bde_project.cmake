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
include(CMakeParseArguments)

# :: bde_project_summary ::
# ----------------------------------------------------------------------------- 
# Print a summary containing the various configuration parameters, overlays
# used and versions of libraries found.

function(bde_project_summary)
    message(STATUS "=========================================")
    message(STATUS "=====            SUMMARY            =====")
    message(STATUS "=========================================")
    message(STATUS " BuildType........: ${CMAKE_BUILD_TYPE}")
    message(STATUS " UFID.............: ${UFID}")
    message(STATUS " Canonical UFID...: ${bde_canonical_ufid}")
    message(STATUS " Install UFID.....: ${bde_install_ufid}")
    message(STATUS " Install lib path.: ${bde_install_lib_suffix}")
    message(STATUS "=========================================")
endfunction()

function(bde_project name)
    cmake_parse_arguments(proj "" "COMMON_INTERFACE_TARGET" "FILES" ${ARGN})
    
    set(property_list TARGET DEPENDS TEST_TARGETS)

    foreach(prop ${property_list})
        set(all_${prop})
    endforeach()

    foreach(uorFileName ${proj_FILES})
        # The uor file must contain the definition of 'process_uor' function or macro
        bde_reset_function(process_uor)
        message(STATUS "Processing ${uorFileName}")
        include(${uorFileName})
        process_uor(
            uorInfoTarget
            ${uorFileName}
            COMMON_INTERFACE_TARGET
                ${proj_COMMON_INTERFACE_TARGET}
        )

        foreach(prop ${property_list})
            bde_info_target_get_property(value ${uorInfoTarget} ${prop})
            list(APPEND all_${prop} ${value})
        endforeach()
    endforeach()

    bde_add_info_target(${name})
    bde_info_target_set_property(${name} TARGETS ${all_TARGET})
    bde_info_target_set_property(${name} DEPENDS ${all_DEPENDS})

    if(all_TEST_TARGETS)
        add_custom_target(${name}.t)
        add_dependencies(${name}.t ${all_TEST_TARGETS})
        bde_info_target_set_property(${name} TEST_TARGETS ${name}.t)
    endif()
endfunction()

# takes in all project names
function(bde_finalize_projects)
    # todo - remove duplication
    set(property_list TARGETS DEPENDS TEST_TARGETS)

    foreach(prop ${property_list})
        set(all_${prop})
    endforeach()

    foreach(proj ${ARGN})
        foreach(prop ${property_list})
            bde_info_target_get_property(value ${proj} ${prop})
            list(APPEND all_${prop} ${value})
        endforeach()
    endforeach()

    # Detect which dependencies are external to this project
    list(REMOVE_ITEM all_DEPENDS ${all_TARGETS})
    list(REMOVE_DUPLICATES all_DEPENDS)

    message(STATUS "Searching for EXTERNAL dependencies: ${all_DEPENDS}")
    foreach(external_dep ${all_DEPENDS})
        find_package(${external_dep} REQUIRED PATH_SUFFIXES "${bde_install_lib_suffix}/${bde_install_ufid}/cmake")
        if (NOT TARGET ${external_dep})
            message(
                FATAL_ERROR
                "Found external dependency '${external_dep}', "
                "but the target '${external_dep}' was not defined."
            )
        endif()
    endforeach()

    if(all_TEST_TARGETS)
        add_custom_target(all.t)
        add_dependencies(all.t ${all_TEST_TARGETS})
    endif()

    bde_project_summary()
endfunction()

macro(bde_process_workspace) 
    # macro and not a function because enable_testing()
    # should be called at top level

    enable_testing()

    include(bde_utils)
    include(bde_ufid)

    set(projects)
    bde_process_ufid()
    foreach(dir ${ARGN})
        bde_reset_function(process_project)
        include(${dir}/project.cmake)
        process_project(proj ${dir})
        list(APPEND projects ${proj})
    endforeach()

    bde_finalize_projects(${projects})
endmacro()

