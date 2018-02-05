if(BDE_PROJECT_INCLUDED)
    return()
endif()
set(BDE_PROJECT_INCLUDED true)

include(CMakeParseArguments)

# BDE CMake modules.
include(bde_log)
include(bde_process_with_default)
include(bde_uor)

set(
    BDE_PROJECT_TYPE
        DEPENDS
        TARGETS
        TEST_TARGET
)

function(internal_process_uor_list retUORs uorRoots uorType intermediateDir)
    bde_assert_no_extra_args()

    set(allUORs)
    foreach(uorRoot IN LISTS uorRoots)
        get_filename_component(uorName ${uorRoot} NAME)
        bde_log(NORMAL "Processing '${uorName}' as ${uorType} (${uorRoot})")

        set(uorFileName "${uorRoot}/${intermediateDir}/${uorName}.cmake")
        unset(uor)
        bde_process_with_default(
            ${uorFileName}
            defaults/bde_process_${uorType}
            # Arguments passed to the process() function:
            uor
            ${uorFileName}
        )

        bde_struct_check_return(
            "${uor}" BDE_UOR_TYPE "${uorName}'s process()"
        )

        list(APPEND allUORs ${uor})
    endforeach()

    bde_return(${allUORs})
endfunction()

function(bde_process_project_uors projName)
    cmake_parse_arguments(
        proj
        ""
        ""
        "COMMON_INTERFACE_TARGETS;PACKAGE_GROUPS;APPLICATIONS;STANDALONE_PACKAGES"
        ${ARGN}
    )
    bde_assert_no_unparsed_args(proj)

    internal_process_uor_list(
        groupUORs "${proj_PACKAGE_GROUPS}" package_group group
    )
    internal_process_uor_list(
        packageUORs "${proj_STANDALONE_PACKAGES}" standalone_package package
    )
    internal_process_uor_list(
        applicationUORs "${proj_APPLICATIONS}" application package
    )

    # Join information from all UORs
    set(properties TARGET DEPENDS TEST_TARGETS)

    foreach(uor IN LISTS groupUORs packageUORs applicationUORs)
        foreach(prop IN LISTS properties)
            bde_struct_get_field(value ${uor} ${prop})
            list(APPEND all_${prop} ${value})
        endforeach()

        bde_struct_get_field(
            interfaceTargets ${uor} INTERFACE_TARGETS
        )

        foreach(commonInterfaceTarget IN LISTS proj_COMMON_INTERFACE_TARGETS)
            foreach(interfaceTarget IN LISTS interfaceTargets)
                bde_interface_target_assimilate(
                    ${interfaceTarget} ${commonInterfaceTarget}
                )
            endforeach()
            bde_struct_append_field(
                ${uor} INTERFACE_TARGETS ${commonInterfaceTarget}
            )
        endforeach()

        bde_install_uor(${uor})
    endforeach()

    # Build project info target
    bde_struct_append_field(${projName} TARGETS ${all_TARGET})
    bde_struct_append_field(${projName} DEPENDS "${all_DEPENDS}")

    if(all_TEST_TARGETS)
        bde_struct_get_field(testTarget ${projName} TEST_TARGET)
        if(NOT testTarget)
            set(testTarget ${projName}.t)
            add_custom_target(${testTarget})
            bde_struct_set_field(${projName} TEST_TARGET ${testTarget})
        endif()
        add_dependencies(${testTarget} ${all_TEST_TARGETS})
    endif()
endfunction()

function(bde_process_project retProject listDir)
    bde_assert_no_extra_args()

    macro(find_uors type)
        file(GLOB dirs "${listDir}/${type}/*")
        bde_utils_filter_directories(${type} ${dirs})
    endmacro()

    find_uors(groups)
    find_uors(standalones)
    find_uors(applications)

    if (groups OR standalones OR applications)
        get_filename_component(projName ${listDir} NAME)
        bde_struct_create(BDE_PROJECT_TYPE ${projName})

        bde_process_project_uors(
            ${projName}
            COMMON_INTERFACE_TARGETS
                bde_ufid_flags
            PACKAGE_GROUPS
                ${groups}
            STANDALONE_PACKAGES
                ${standalones}
            APPLICATIONS
                ${applications}
        )
        bde_return(${projName})
    endif()

    bde_return()
endfunction()