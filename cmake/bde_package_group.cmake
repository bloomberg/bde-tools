if(BDE_PACKAGE_GROUP_INCLUDED)
    return()
endif()
set(BDE_PACKAGE_GROUP_INCLUDED true)

include(bde_log)
include(bde_package)
include(bde_process_with_default)
include(bde_uor)
include(bde_utils)

function(bde_process_package_group outInfoTarget listFile)
    bde_assert_no_extra_args()

    get_filename_component(uorName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_log(VERBOSE "[${uorName}]: Start processing package group")

    # Sources and headers
    bde_utils_add_meta_file("${listDir}/${uorName}.mem" packages TRACK)

    # Dependencies
    bde_utils_add_meta_file("${listDir}/${uorName}.dep" dependencies TRACK)

    # Process packages
    set(packageInfoTargets)
    foreach(packageName IN LISTS packages)
        bde_log(
            VERBOSE
            "[${uorName}]: Processing package [${packageName}]"
        )

        set(packageFileName "${rootDir}/${packageName}/package/${packageName}.cmake")
        unset(packageInfoTarget)
        bde_process_with_default(
            ${packageFileName}
            defaults/bde_process_package
            # Arguments passed to the process() function:
            packageInfoTarget
            ${packageFileName}
            ${uorName}
        )

        bde_struct_check_return(
            "${packageInfoTarget}" BDE_PACKAGE_TYPE "${packageName}'s process()"
        )

        list(APPEND packageInfoTargets ${packageInfoTarget})
    endforeach()

    bde_prepare_uor(${uorName} ${uorName} "${dependencies}" LIBRARY)
    bde_project_add_uor(${uorName} "${packageInfoTargets}")
    set(${outInfoTarget} ${uorName} PARENT_SCOPE)

    bde_log(VERBOSE "[${uorName}]: Done")
endfunction()
