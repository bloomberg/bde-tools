function(process outInfoTarget list_dir)
    macro(find_uors type)
        file(GLOB dirs "${list_dir}/${type}/*")
        bde_filter_directories(${type} ${dirs})
    endmacro()

    find_uors(groups)
    find_uors(standalones)
    find_uors(applications)

    if (groups OR standalones OR applications)
        get_filename_component(projName ${list_dir} NAME)
        bde_add_info_target(${projName})

        bde_project_process_uors(
            ${projName}
            COMMON_INTERFACE_TARGET
                bde_ufid_flags
            PACKAGE_GROUPS
                ${groups}
            STANDALONE_PACKAGES
                ${standalones}
            APPLICATIONS
                ${applications}
        )
        set(${outInfoTarget} ${projName} PARENT_SCOPE)
    endif()
endfunction()