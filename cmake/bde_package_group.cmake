if(BDE_PACKAGE_GROUP_INCLUDED)
    return()
endif()
set(BDE_PACKAGE_GROUP_INCLUDED true)

include(bde_log)
include(bde_package)
include(bde_process_with_default)
include(bde_uor)
include(bde_utils)

function(bde_process_package_group retPackageGroup listFile)
    bde_assert_no_extra_args()

    get_filename_component(uorName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_log(VERBOSE "[${uorName}]: Start processing package group")

    # Sources and headers
    bde_utils_add_meta_file("${listDir}/${uorName}.mem" packageNames TRACK)

    # Dependencies
    bde_utils_add_meta_file("${listDir}/${uorName}.dep" dependencies TRACK)

    # Process packages
    set(packages)
    foreach(packageName IN LISTS packageNames)
        bde_log(
            VERBOSE
            "[${uorName}]: Processing package [${packageName}]"
        )

        set(packageFileName "${rootDir}/${packageName}/package/${packageName}.cmake")
        unset(package)
        bde_process_with_default(
            ${packageFileName}
            defaults/bde_process_package
            # Arguments passed to the process() function:
            package
            ${packageFileName}
            ${uorName}
        )

        bde_struct_check_return(
            "${package}" BDE_PACKAGE_TYPE "${packageName}'s process()"
        )

        list(APPEND packages ${package})
    endforeach()

    add_library(${uorName} "")
    bde_struct_create(
        uor
        BDE_UOR_TYPE
        NAME "${uorName}"
        TARGET "${uorName}"
        DEPENDS "${dependencies}"
    )
    bde_project_add_uor(${uor} "${packages}")

    bde_log(VERBOSE "[${uorName}]: Done")
    bde_return(${uor})
endfunction()
