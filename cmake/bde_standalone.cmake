if(BDE_STANDALONE_INCLUDED)
    return()
endif()
set(BDE_STANDALONE_INCLUDED true)

include(bde_log)
include(bde_package)
include(bde_uor)

macro(internal_process_standalone outInfoTarget listFile uorType)
    get_filename_component(uorName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_log(VERBOSE "[${uorName}]: Start processing")

    bde_process_package(packageInfoTarget ${listFile} ${uorName})

    # Standalone dependencies should be interpreted as UOR
    # dependencies in 'bde_prepare_uor'
    bde_struct_get_field(packageDeps ${packageInfoTarget} DEPENDS)
    bde_struct_set_field(${packageInfoTarget} DEPENDS "")

    set(infoTarget ${uorName}-standalone)
    bde_prepare_uor(${uorName} ${infoTarget} "${packageDeps}" ${uorType})
    bde_project_add_uor(${infoTarget} ${packageInfoTarget})
    set(${outInfoTarget} ${infoTarget} PARENT_SCOPE)

    bde_log(VERBOSE "[${uorName}]: Done")
endmacro()

function(bde_process_standalone_package outInfoTarget listFile)
    bde_assert_no_extra_args()
    internal_process_standalone(
        ${outInfoTarget} ${listFile} LIBRARY
    )
endfunction()

function(bde_process_application outInfoTarget listFile)
    bde_assert_no_extra_args()
    internal_process_standalone(
        ${outInfoTarget} ${listFile} APPLICATION
    )
endfunction()
