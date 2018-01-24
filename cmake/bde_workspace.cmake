if(BDE_WORKSPACE_INCLUDED)
    return()
endif()
set(BDE_WORKSPACE_INCLUDED true)

include(bde_external_dependencies)
include(bde_log)
include(bde_process_with_default)
include(bde_ufid)
include(bde_utils)

macro(bde_process_workspace)
    # macro and not a function because enable_testing()
    # should be called at top level

    enable_testing()

    set(projInfoTargets)
    bde_process_ufid()
    foreach(rootDir ${ARGN})
        set(projInfoTarget)

        bde_process_with_default(
            "${rootDir}/project.cmake"
            defaults/bde_process_project
            # Arguments passed to the process() function:
            projInfoTarget
            ${rootDir}
        )

        if(projInfoTarget)
            list(APPEND projInfoTargets ${projInfoTarget})
        else()
            bde_log(
                NORMAL
                "${rootDir} does not seem to contain a valid BDE-style project."
            )
        endif()
    endforeach()

    bde_finalize_workspace("${projInfoTargets}")
endmacro()

# Resolve all external dependencies and add all.t test target
# Takes in all project names
function(bde_finalize_workspace projInfoTargets)
    bde_assert_no_extra_args()

    set(properties TARGETS DEPENDS TEST_TARGET)

    foreach(proj IN LISTS projInfoTargets)
        foreach(prop IN LISTS properties)
            bde_struct_get_field(value ${proj} ${prop})
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

    bde_workspace_summary()
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
    bde_log(NORMAL " Install lib path.: ${bde_install_lib_suffix}")
    bde_log(NORMAL "=========================================")
endfunction()
