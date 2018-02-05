if(BDE_STANDALONE_INCLUDED)
    return()
endif()
set(BDE_STANDALONE_INCLUDED true)

include(bde_log)
include(bde_package)
include(bde_uor)

macro(internal_process_standalone listFile uorType)
    get_filename_component(uorName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_log(VERBOSE "[${uorName}]: Start processing")

    bde_process_package(package ${listFile} ${uorName})

    # Standalone dependencies should be interpreted as UOR
    # dependencies in 'bde_prepare_uor'
    bde_struct_get_field(packageDeps ${package} DEPENDS)
    bde_struct_set_field(${package} DEPENDS "")

    set(standaloneUOR ${uorName}-standalone)
    bde_prepare_uor(${uorName} ${standaloneUOR} "${packageDeps}" ${uorType})
    bde_project_add_uor(${standaloneUOR} ${package})

    bde_log(VERBOSE "[${uorName}]: Done")
    bde_return(${standaloneUOR})
endmacro()

function(bde_process_standalone_package retStandalonePackage listFile)
    bde_assert_no_extra_args()
    internal_process_standalone(${listFile} LIBRARY)
endfunction()

function(bde_process_application retApplication listFile)
    bde_assert_no_extra_args()
    internal_process_standalone(${listFile} APPLICATION)
endfunction()
