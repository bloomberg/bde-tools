include(bde_include_guard)
bde_include_guard()

include(bde_log)
include(bde_package)
include(bde_virtual_function)
include(bde_uor)
include(bde_utils)

macro(internal_read_version_tag fileName)
    set(re "^[ \t]*#define[ \t]+[A-Z_]+VERSION_([A-Z]+)[ \t]+([0-9]+).*$")
    file(STRINGS ${fileName} versionStrings REGEX ${re})

    foreach(str IN LISTS versionStrings)
        if(${str} MATCHES ${re})
            set(_v_${CMAKE_MATCH_1} ${CMAKE_MATCH_2})
        endif()
    endforeach()
endmacro()

function(bde_package_group_set_version uor listFile)
    bde_expand_list_file(${listFile} FILENAME groupName ROOTDIR rootDir)

    # This file contains major and minor versions.
    set(file1  "${rootDir}/${groupName}scm/${groupName}scm_versiontag.h")
    # One of those file contain the patch version.
    set(file2a "${rootDir}/${groupName}scm/${groupName}scm_patchversion.h")

    # Depending on the component scm implementation, we must try here as well.
    set(file2b "${rootDir}/${groupName}scm/${groupName}scm_version.cpp")
    set(file2c "${rootDir}/${groupName}scm/${groupName}scm_version.c")

    if (EXISTS ${file1})
        internal_read_version_tag(${file1})
    endif()

    if (EXISTS ${file2a})
        internal_read_version_tag(${file2a})
    elseif(EXISTS ${file2b})
        internal_read_version_tag(${file2b})
    elseif(EXISTS ${file2c})
        internal_read_version_tag(${file2c})
    endif()

    if (NOT DEFINED _v_MAJOR OR
        NOT DEFINED _v_MINOR OR
        NOT DEFINED _v_PATCH)
        message(FATAL_ERROR "Missing scm version tags for ${groupName}")
    endif()

    set(versionTag "${_v_MAJOR}.${_v_MINOR}.${_v_PATCH}")

    bde_log(NORMAL "Version: ${versionTag}")
    bde_struct_set_field(${uor} VERSION_TAG ${versionTag})
    bde_struct_mark_field_const(${uor} VERSION_TAG)
endfunction()

function(bde_package_group_process_packages uor listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(
        ${listFile} FILENAME groupName LISTDIR listDir ROOTDIR rootDir
    )

    # Sources and headers
    bde_utils_add_meta_file("${listDir}/${groupName}.mem" packageNames TRACK)

    bde_log(VERBOSE "[${groupName}] Processing packages\n")

    # Process packages
    foreach(packageName IN LISTS packageNames)
        bde_log(
            VERBOSE
            "[${packageName}] Processing package"
        )

        set(packageFileName "${rootDir}/${packageName}/package/${packageName}.cmake")
        unset(package)
        bde_load_local_customization(${packageFileName})
        process_package(package ${packageFileName} ${installOpts})
        bde_cleanup_local_customization()

        bde_struct_check_return(
            "${package}" BDE_PACKAGE_TYPE "${packageName}'s process_package()"
        )

        bde_uor_use_package(${uor} ${package})

        bde_log(VERBOSE "[${packageName}] Done\n")
    endforeach()
endfunction()

function(bde_package_group_setup_interface uor listFile)
    uor_setup_interface(${uor} ${listFile})
    bde_process_dependencies(${uor} ${listFile})
endfunction()

function(bde_package_group_setup_test_interface uor listFile)
    bde_process_test_dependencies(${uor} ${listFile})

    bde_create_uor_test_metatarget(${uor})

    # By default, tests should be linking with the UOR result
    bde_link_target_to_tests(${uor})
endfunction()

function(bde_package_group_install_meta uor listFile installOpts)
    bde_assert_no_extra_args()

    bde_struct_get_field(component ${installOpts} COMPONENT)

    # Install meta files
    bde_expand_list_file(${listFile} LISTDIR listDir)

    install(
        DIRECTORY ${listDir}
        COMPONENT "${component}-meta"
        DESTINATION "share/bdemeta/groups/${component}"
        EXCLUDE_FROM_ALL
    )
endfunction()
