## bde_uor.cmake

#.rst:
# bde_uor
# -------
#
# This module provides methods to work with uors(Units Of Release).
#
# The main exposed functions are the following ones (refer to their individual
# documentation for more information about each):
#
# * :command:`bde_uor_initialize`
# * :command:`bde_uor_initialize_library`
# * :command:`bde_uor_initialize_application`
# * :command:`bde_uor_install_target`
# * :command:`bde_uor_use_package`

include(bde_include_guard)
bde_include_guard()

include(bde_interface_target)
include(bde_log)
include(bde_struct)
include(bde_utils)

bde_register_struct_type(
    BDE_UOR_TYPE
        VERSION_TAG
        PACKAGES

        TARGET
        INTERFACE_TARGET # build and usage requirements of the uor
        DEPENDS

        TEST_TARGETS
        TEST_INTERFACE_TARGET
        TEST_DEPENDS
)

#.rst:
# .. command:: bde_uor_initialize
#
# Create and initialize interface target for UOR.
function(bde_uor_initialize retUor uorTarget)
    bde_assert_no_extra_args()

    bde_create_struct_with_interfaces(uor BDE_UOR_TYPE NAME ${uorTarget})
    bde_struct_set_field(${uor} TARGET ${uorTarget})
    bde_struct_mark_field_const(${uor} TARGET)

    bde_return(${uor})
endfunction()

#.rst:
# .. command:: bde_uor_initialize_library
#
# Create interface target for the library UOR.
function(bde_uor_initialize_library retUor uorName)
    bde_assert_no_extra_args()

    add_library(${uorName} "")
    bde_uor_initialize(uor ${uorName})

    bde_return(${uor})
endfunction()

#.rst:
# .. command:: bde_uor_initialize_application
#
# Create interface target for the application UOR.
function(bde_uor_initialize_application retUor uorName)
    bde_assert_no_extra_args()

    bde_add_executable(${uorName} "")
    bde_uor_initialize(uor ${uorName})

    bde_return(${uor})
endfunction()

#.rst:
# .. command:: bde_uor_use_package
#
# Link the interface target of the specified package to the specified UOR.
function(bde_uor_use_package uor package)
    bde_assert_no_extra_args()

    bde_struct_append_field(${uor} PACKAGES ${package})

    bde_struct_get_field(uorTarget ${uor} TARGET)
    bde_struct_get_field(uorInterfaceTarget ${uor} INTERFACE_TARGET)
    bde_struct_get_field(uorTestInterfaceTarget ${uor} TEST_INTERFACE_TARGET)

    bde_struct_get_field(packageInterfaceTarget ${package} INTERFACE_TARGET)
    bde_struct_get_field(packageTestInterfaceTarget ${package} TEST_INTERFACE_TARGET)

    # Add package usage and build requirements to the UOR target
    bde_target_link_interface_target(${uorTarget} ${packageInterfaceTarget})

    # The UOR build requirements are also its packages' build requirements
    bde_interface_target_assimilate(
        ${packageInterfaceTarget}
        ${uorInterfaceTarget}
    )
    bde_interface_target_assimilate(
        ${packageTestInterfaceTarget}
        ${uorTestInterfaceTarget}
    )

    # Add sources to the UOR target
    bde_struct_get_field(packageSrcs ${package} SOURCES)
    bde_struct_mark_field_const(${package} SOURCES)
    bde_struct_get_field(packageHdrs ${package} HEADERS)
    bde_struct_mark_field_const(${package} HEADERS)
    target_sources(${uorTarget} PRIVATE ${packageSrcs} ${packageHdrs})

    # Add tests to the UOR target
    bde_struct_get_field(tests ${package} TEST_TARGETS)
    bde_struct_mark_field_const(${package} TEST_TARGETS)
    bde_struct_append_field(${uor} TEST_TARGETS "${tests}")
endfunction()

#.rst:
# .. command:: bde_uor_install_target
#
# Create an installation targets for for the UOR.
function(bde_uor_install_target uor listFile installOpts)
    bde_assert_no_extra_args()

    bde_struct_get_field(component ${installOpts} COMPONENT)
    bde_struct_get_field(exportSet ${installOpts} EXPORT_SET)
    bde_struct_get_field(archiveInstallDir ${installOpts} ARCHIVE_DIR)
    bde_struct_get_field(libInstallDir ${installOpts} LIBRARY_DIR)
    bde_struct_get_field(execInstallDir ${installOpts} EXECUTABLE_DIR)

    bde_struct_get_field(uorTarget ${uor} TARGET)

    # Install main target
    install(
        TARGETS ${uorTarget}
        EXPORT ${exportSet}Targets
        COMPONENT "${component}"
        ARCHIVE DESTINATION ${archiveInstallDir}
        LIBRARY DESTINATION ${libInstallDir}
        RUNTIME DESTINATION ${execInstallDir}
    )

    bde_add_component_install_target(${component} ${uorTarget})
endfunction()

function(bde_add_component_install_target component)
    if(TARGET install.${component})
        add_dependencies(install.${component} ${uorTarget})
        return()
    endif()

    set(extraInstallArg)
    if(MSVC)
        set(extraInstallArg "-DBUILD_TYPE=${CMAKE_CFG_INTDIR}")
    endif()

    add_custom_target(
        install.${component}
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${component}"
            ${extraInstallArg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${component}-headers"
            ${extraInstallArg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        DEPENDS ${uorTarget}
    )
endfunction()
