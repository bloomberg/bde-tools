include(bde_include_guard)
bde_include_guard()

include(GNUInstallDirs)

# BDE CMake modules.
include(bde_log)
include(bde_virtual_function)
include(bde_uor)

bde_register_struct_type(
    BDE_INSTALL_OPTS_TYPE
        COMPONENT
        EXPORT_SET
        INCLUDE_DIR
        ARCHIVE_DIR
        LIBRARY_DIR
        PKGCONFIG_DIR
        EXECUTABLE_DIR
)

bde_register_struct_type(
    BDE_PROJECT_TYPE
        UORS
        INSTALL_OPTS
)

function(internal_process_uor_list proj uorRoots uorType intermediateDir)
    bde_assert_no_extra_args()

    bde_struct_get_field(installOpts ${proj} INSTALL_OPTS)

    foreach(uorRoot IN LISTS uorRoots)
        get_filename_component(uorName ${uorRoot} NAME)
        bde_log(NORMAL "Processing '${uorName}' as ${uorType} (${uorRoot})")

        set(uorFileName "${uorRoot}/${intermediateDir}/${uorName}.cmake")

        bde_struct_set_field(${installOpts} COMPONENT ${uorName})
        bde_struct_set_field(${installOpts} EXPORT_SET ${uorName})

        bde_load_local_customization(${uorFileName})
        if(uorType STREQUAL "package_group")
            process_package_group(uor ${uorFileName} ${installOpts})
        elseif(uorType STREQUAL "application")
            process_application(uor ${uorFileName} ${installOpts})
        elseif(uorType STREQUAL "standalone_package")
            process_standalone_package(uor ${uorFileName} ${installOpts})
        else()
            message(FATAL_ERROR "Unknown uor type.")
        endif()
        bde_cleanup_local_customization()

        bde_struct_check_return(
            "${uor}" BDE_UOR_TYPE "${uorName}'s process_${uorType}"
        )

        bde_struct_append_field(${proj} UORS ${uor})
        unset(uor)
    endforeach()
endfunction()

function(bde_project_process_package_groups proj)
    internal_process_uor_list(${proj} "${ARGN}" package_group group)
endfunction()

function(bde_project_process_standalone_packages proj)
    internal_process_uor_list(${proj} "${ARGN}" standalone_package package)
endfunction()

function(bde_project_process_applications proj)
    internal_process_uor_list(${proj} "${ARGN}" application package)
endfunction()

function(bde_project_initialize retProj projName)
    bde_assert_no_extra_args()

    bde_struct_create(
        proj
        BDE_PROJECT_TYPE
        NAME ${projName}-proj
    )

    bde_return(${proj})
endfunction()

function(bde_project_setup_install_opts proj)
    bde_assert_no_extra_args()

    bde_struct_create(
        installOpts
        BDE_INSTALL_OPTS_TYPE
            INCLUDE_DIR ${CMAKE_INSTALL_INCLUDEDIR}
            LIBRARY_DIR ${CMAKE_INSTALL_LIBDIR}
            ARCHIVE_DIR ${CMAKE_INSTALL_LIBDIR}
            PKGCONFIG_DIR "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
            EXECUTABLE_DIR ${CMAKE_INSTALL_BINDIR}
    )

    bde_struct_set_field(${proj} INSTALL_OPTS ${installOpts})
endfunction()

function(bde_project_process_uors proj listDir)
    bde_assert_no_extra_args()

    macro(find_uors out)
        bde_utils_list_template_substitute(srcDirs "%" "src/%" ${ARGN})
        foreach(dir ${srcDirs} ${ARGN})
            file(GLOB dirs "${listDir}/${dir}/*")
            list(APPEND ${out} ${dirs})
        endforeach()
        bde_utils_filter_directories(${out} "${${out}}")
    endmacro()

    find_uors(groups "groups" "enterprise" "wrappers")
    bde_project_process_package_groups(${proj} "${groups}")

    find_uors(standalones "adapters" "standalones")
    bde_project_process_standalone_packages(${proj} "${standalones}")

    find_uors(applications "applications")
    bde_project_process_applications(${proj} "${applications}")
endfunction()
