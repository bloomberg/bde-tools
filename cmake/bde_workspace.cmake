include(bde_include_guard)
bde_include_guard()

include(GNUInstallDirs)

# Must tune the CMAKE_INSTALL_LIBDIR for other platforms
# as they are not GNU.
# Other defaults are fine.
if(CMAKE_SYSTEM_NAME MATCHES "^(AIX|SunOS)$")
    if("${CMAKE_SIZEOF_VOID_P}" EQUAL "8")
        set(CMAKE_INSTALL_LIBDIR "lib64" CACHE PATH "Object code libraries (${CMAKE_INSTALL_LIBDIR})" FORCE)
    endif()
endif()

include(bde_external_dependencies)
include(bde_log)
include(bde_virtual_function)
include(bde_ufid)
include(bde_utils)

include(layers/base) # Include the base layer for the whole workspace

macro(internal_append_field var struct prop)
    bde_struct_get_field(value ${struct} ${prop})
    list(APPEND ${var} ${value})
endmacro()

macro(bde_process_workspace)
    # macro and not a function because enable_testing()
    # should be called at top level

    enable_testing()

    # Process projects
    set(allUORs)
    foreach(rootDir ${ARGN})
        unset(proj)
        bde_load_local_customization("${rootDir}/project.cmake")
        process_project(proj ${rootDir} ${installOpts})
        bde_cleanup_local_customization()

        bde_struct_check_return(
            "${proj}" BDE_PROJECT_TYPE
            "process_project() within ${rootDir}/project.cmake"
        )
        bde_struct_get_field(uors ${proj} UORS)
        if(uors)
            internal_append_field(allUORs ${proj} UORS)
        else()
            bde_log(
                NORMAL
                "${rootDir} does not seem to contain a valid BDE-style project."
            )
        endif()
    endforeach()

    foreach(uor IN LISTS allUORs)
        internal_append_field(allTestTargets ${uor} TEST_TARGETS)
    endforeach()

    bde_resolve_uor_dependencies("${allUORs}")
    bde_create_test_metatarget(metaT "${allTestTargets}" all)
    bde_workspace_summary()
endmacro()

# Collect and resolve all external dependencies
function(bde_resolve_uor_dependencies uors)
    bde_assert_no_extra_args()

    foreach(uor IN LISTS uors)
        internal_append_field(targets ${uor} TARGET)
        internal_append_field(depends ${uor} DEPENDS)
        internal_append_field(testdepends ${uor} TEST_DEPENDS)
    endforeach()

    foreach(prefix "" "test")
        set(dependsVar ${prefix}depends)

        if(${dependsVar})
            list(REMOVE_ITEM ${dependsVar} ${targets})
            list(REMOVE_DUPLICATES ${dependsVar})
        endif()

        if(${dependsVar})
            bde_log(NORMAL "Resolving EXTERNAL ${prefix} dependencies: ${${dependsVar}}.")
            bde_resolve_external_dependencies("${${dependsVar}}")
        else()
            bde_log(NORMAL "All ${prefix} dependencies were resolved internally.")
        endif()
    endforeach()
endfunction()

# :: bde_workspace_summary ::
# -----------------------------------------------------------------------------
# Print a summary containing the various configuration parameters, overlays
# used and versions of libraries found.
function(bde_workspace_summary)
    bde_log(NORMAL "=========================================")
    bde_log(NORMAL "=====            SUMMARY            =====")
    bde_log(NORMAL "=========================================")
    bde_log(NORMAL " RefRoot..........: ${DISTRIBUTION_REFROOT}")
    bde_log(NORMAL " BuildType........: ${CMAKE_BUILD_TYPE}")
    bde_log(NORMAL " UFID.............: ${UFID}")
    bde_log(NORMAL " Canonical UFID...: ${bde_canonical_ufid}")
    bde_log(NORMAL " Install UFID.....: ${bde_install_ufid}")
    bde_log(NORMAL " Install lib path.: ${CMAKE_INSTALL_LIBDIR}")
    bde_log(NORMAL "=========================================")
endfunction()
