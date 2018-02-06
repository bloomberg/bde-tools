if(BDE_STANDALONE_INCLUDED)
    return()
endif()
set(BDE_STANDALONE_INCLUDED true)

include(bde_log)
include(bde_package)
include(bde_uor)
include(bde_utils)

macro(internal_process_standalone uorName)
    bde_log(VERBOSE "[${uorName}]: Start processing")

    bde_process_package(package ${listFile} ${uorName})

    # Standalone dependencies should be interpreted as UOR dependencies
    bde_struct_get_field(packageDeps ${package} DEPENDS)
    bde_struct_set_field(${package} DEPENDS "")

    bde_struct_create(
        uor
        BDE_UOR_TYPE
        NAME "${uorName}"
        TARGET "${uorName}"
        DEPENDS "${packageDeps}"
    )
    bde_project_add_uor(${uor} ${package})

    bde_log(VERBOSE "[${uorName}]: Done")
    bde_return(${uor})
endmacro()

function(bde_process_standalone_package retStandalonePackage listFile)
    bde_assert_no_extra_args()
    get_filename_component(uorName ${listFile} NAME_WE)
    add_library(${uorName} "")
    internal_process_standalone(${uorName})
endfunction()

function(bde_process_application retApplication listFile)
    bde_assert_no_extra_args()
    get_filename_component(uorName ${listFile} NAME_WE)
    bde_add_executable(${uorName} "")
    internal_process_standalone(${uorName})
endfunction()
