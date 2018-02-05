if(BDE_PACKAGE_INCLUDED)
    return()
endif()
set(BDE_PACKAGE_INCLUDED true)

include(bde_component)
include(bde_interface_target)
include(bde_struct)
include(bde_utils)

set(
    BDE_PACKAGE_TYPE
        SOURCES
        HEADERS
        DEPENDS
        TEST_TARGETS
        INTERFACE_TARGET
)

function(bde_process_package retPackage listFile uorName)
    bde_assert_no_extra_args()

    get_filename_component(packageName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_struct_create(BDE_PACKAGE_TYPE ${packageName})

    # Populate sources, headers, test drivers and dependancies in the
    # info target.
    set(packageBaseName "${listDir}/${packageName}")
    bde_utils_add_meta_file("${packageBaseName}.mem" components TRACK)

    foreach(componentName IN LISTS components)
        unset(component)
        bde_process_component(
            component ${rootDir} ${componentName}
        )
        bde_struct_check_return(
            ${component} BDE_COMPONENT_TYPE ${componentName}
        )

        foreach(prop HEADER SOURCE TEST_TARGET)
            bde_struct_get_field(${prop}-val ${component} ${prop})
            bde_struct_append_field(${packageName} ${prop}S "${${prop}-val}")
        endforeach()

        if(TEST_TARGET-val)
            bde_append_test_labels(${TEST_TARGET-val} ${packageName})
        endif()
    endforeach()

    # Get list of all dependencies from the <folderName>/<packageName>.dep
    bde_utils_add_meta_file("${packageBaseName}.dep" depends TRACK)
    bde_struct_set_field(${packageName} DEPENDS "${depends}")

    # Get list of all TEST dependencies from the
    # <packageName>/package/<packageName>.t.dep
    if(EXISTS "${packageBaseName}.t.dep")
        bde_utils_add_meta_file("${packageBaseName}.t.dep" testDepends TRACK)
        bde_struct_set_field(${packageName} TEST_DEPENDS "${testDepends}")
    endif()

    # Include directories
    bde_add_interface_target(${packageName})
    bde_struct_set_field(${packageName} INTERFACE_TARGET ${packageName})
    bde_interface_target_include_directories(
        ${packageName}
        PUBLIC
            $<BUILD_INTERFACE:${rootDir}>
            $<INSTALL_INTERFACE:"include">
    )

    # By default all component's headers are installed in 'include'.
    bde_struct_get_field(headers ${packageName} HEADERS)
    install(
        FILES ${headers}
        DESTINATION "include"
        COMPONENT "${uorName}-headers"
    )

    bde_return(${packageName})
endfunction()
