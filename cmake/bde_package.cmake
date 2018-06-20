include(bde_include_guard)
bde_include_guard()

include(bde_component)
include(bde_interface_target)
include(bde_struct)
include(bde_utils)

bde_register_struct_type(
    BDE_PACKAGE_TYPE
        SOURCES
        HEADERS
        INTERFACE_TARGET

        TEST_TARGETS
            # All test targets of the package
        TEST_INTERFACE_TARGET
            # Controls the build requirements of the tests. Since the tests are executables,
            # their usage requirements do not affect anything - use PRIVATE to set up the flags for tests.
            # Note that the tests are clients of the package target and therefore build requirements
            # of the package are not automatically applied to the tests.
        TEST_DEPENDS
)

function(bde_package_initialize retPackage packageName)
    bde_assert_no_extra_args()

    bde_create_struct_with_interfaces(package BDE_PACKAGE_TYPE NAME ${packageName})
    bde_return(${package})
endfunction()

function(bde_package_process_components package listFile)
    bde_assert_no_extra_args()

    bde_expand_list_file(
        ${listFile} FILENAME packageName LISTDIR listDir ROOTDIR rootDir
    )

    set(packageBasePath "${listDir}/${packageName}")
    bde_utils_add_meta_file("${packageBasePath}.mem" components TRACK)

    foreach(componentName IN LISTS components)
        unset(component)
        process_component(
            component ${rootDir} ${componentName}
        )
        bde_struct_check_return(
            ${component} BDE_COMPONENT_TYPE ${componentName}
        )

        foreach(prop HEADER SOURCE TEST_TARGET)
            bde_struct_get_field(val ${component} ${prop})
            bde_struct_append_field(${package} ${prop}S "${val}")
        endforeach()
    endforeach()
endfunction()

function(bde_package_setup_interface package listFile)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} ROOTDIR rootDir)

    bde_struct_get_field(packageInterface ${package} INTERFACE_TARGET)
    bde_interface_target_include_directories(
        ${packageInterface}
        PUBLIC
            $<BUILD_INTERFACE:${rootDir}>
    )
endfunction()

function(bde_package_install package listFile installOpts)
    bde_assert_no_extra_args()

    # By default all component's headers are installed in 'include'.
    bde_struct_get_field(headers ${package} HEADERS)
    bde_struct_mark_field_const(${package} HEADERS)
    bde_struct_get_field(component ${installOpts} COMPONENT)
    bde_struct_get_field(includeInstallDir ${installOpts} INCLUDE_DIR)
    install(
        FILES ${headers}
        DESTINATION ${includeInstallDir}
        COMPONENT ${component}-headers
    )
endfunction()

function(bde_package_setup_test_interface package listFile)
    bde_assert_no_extra_args()

    # Link the package test requirements directly to the tests.
    # The package requirements will be linked either through the package
    # target (if that is created) or throught the UOR target
    bde_struct_get_field(packageTestInterface ${package} TEST_INTERFACE_TARGET)
    bde_struct_get_field(testTargets ${package} TEST_TARGETS)
    foreach(test IN LISTS testTargets)
        bde_target_link_interface_target(${test} ${packageTestInterface})
    endforeach()

    bde_create_package_test_metatarget(${package})
endfunction()
