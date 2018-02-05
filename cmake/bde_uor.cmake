if(BDE_UOR_INCLUDED)
    return()
endif()
set(BDE_UOR_INCLUDED true)

include(bde_interface_target)
include(bde_log)
include(bde_struct)
include(bde_utils)

set(
    BDE_UOR_TYPE
        SOURCES
        HEADERS
        DEPENDS
        TARGET
        INTERFACE_TARGETS
        TEST_TARGETS
)

function(internal_target_objlib_sources target)
    bde_utils_list_template_substitute(
        objSources "%" "$<TARGET_OBJECTS:%>" ${ARGN}
    )
    target_sources(${target} PRIVATE ${objSources})
endfunction()

#TODO: this is a weird function
function(bde_prepare_uor uorName uor uorDepends uorType)
    bde_assert_no_extra_args()

    set(knownUORTypes APPLICATION LIBRARY)
    if (NOT ${uorType} IN_LIST knownUORTypes)
        message(FATAL_ERROR "UOR type '${uorType}' is unknown.")
    endif()

    if (${uorType} STREQUAL APPLICATION)
        add_executable(${uorName} "")
        set_target_properties(
            ${uorName} PROPERTIES SUFFIX ".tsk${CMAKE_EXECUTABLE_SUFFIX}"
        )
    else()
        add_library(${uorName} "")
    endif()
    set_target_properties(${uorName} PROPERTIES LINKER_LANGUAGE CXX)

    bde_struct_create(BDE_UOR_TYPE ${uor})
    bde_struct_set_field(${uor} TARGET "${uorName}")
    bde_struct_set_field(${uor} DEPENDS "${uorDepends}")
endfunction()

function(bde_project_add_uor uor packages)
    bde_assert_no_extra_args()

    bde_struct_get_field(uorName ${uor} TARGET)
    bde_struct_get_field(uorDeps ${uor} DEPENDS)

    # uorInterfaceTarget contains _only_ the build requirements
    # specified for the UOR itself. It does NOT contain the requirements
    # transitively included from the member packages. This interface
    # target is only used directly by the test targets.
    set(uorInterfaceTarget ${uor})
    bde_add_interface_target(${uorInterfaceTarget})
    bde_interface_target_link_libraries(${uorInterfaceTarget} PUBLIC ${uorDeps})

    # uorFullInterfaceTarget contains both the requirements of
    # the UOR itself and all the requirements of all the member packages.
    # This interface target is used for the building the final UOR
    # as well as for the external users.
    set(uorFullInterfaceTarget ${uorInterfaceTarget}-full)
    bde_add_interface_target(${uorFullInterfaceTarget})
    bde_interface_target_assimilate(${uorFullInterfaceTarget} ${uorInterfaceTarget})
    bde_target_link_interface_target(${uorName} ${uorFullInterfaceTarget})

    set(uorTestTarget ${uorName}.t)
    add_custom_target(${uorTestTarget})
    bde_struct_set_field(${uor} TEST_TARGETS ${uorTestTarget})

    # Process packages using their info targets
    bde_struct_set_field(
        ${uor}
        INTERFACE_TARGETS
            ${uorInterfaceTarget}
            ${uorFullInterfaceTarget}
    )

    set(allInterpackageDeps)
    set(allPackageTargets)
    foreach(package IN LISTS packages)
        set(packageName ${package})
        bde_struct_get_field(
            packageInterfaceTarget ${package} INTERFACE_TARGET
        )

        # Add package usage requirements to the UOR target
        # Do not add private requirements as they should only affect the
        # package itself
        bde_interface_target_assimilate(
            ${uorFullInterfaceTarget}
            ${packageInterfaceTarget}
            INTERFACE_ONLY
        )
        bde_struct_append_field(
            ${uor}
            INTERFACE_TARGETS
                ${packageInterfaceTarget}
        )

        bde_struct_get_field(packageSrcs ${package} SOURCES)
        bde_struct_get_field(packageHdrs ${package} HEADERS)
        bde_struct_get_field(packageDeps ${package} DEPENDS)
        list(APPEND allInterpackageDeps ${packageDeps})

        bde_log(
            VERBOSE
            "[${uorName}]: Adding package [${packageName}] (${packageDeps})"
        )

        bde_interface_target_names(uorInterfaceTargets ${uorInterfaceTarget})
        bde_interface_target_names(packageInterfaceTargets ${packageInterfaceTarget})

        set(
            allPackageDepends
            # Requirements specific to this particular package
            ${packageInterfaceTargets}
            # Inter-package dependencies
            ${packageDeps}
            # 'Pure' requirements of the package
            ${uorInterfaceTargets}
        )

        # The package name may clash with uor name for standalone packages
        set(packageLibrary ${packageName})
        if (${uorName} STREQUAL ${packageName})
            set(packageLibrary ${packageName}-pkg)
        endif()
        list(APPEND allPackageTargets ${packageLibrary})

        if(packageSrcs)
            set(packageObjLibrary ${packageLibrary}-obj)

            # object library
            add_library(
                ${packageObjLibrary}
                OBJECT EXCLUDE_FROM_ALL
                ${packageSrcs} ${packageHdrs}
            )

            # CMake as of 3.10 does not allow calling target_link_libraries
            # on OBJECT libraries. This command, however successfully imports
            # the build requirements, such as compiler options and include
            # directories
            set_target_properties(
                ${packageObjLibrary}
                PROPERTIES
                    LINK_LIBRARIES "${allPackageDepends}"
            )

            # target for tests
            add_library(${packageLibrary} EXCLUDE_FROM_ALL "")
            set_target_properties(${packageLibrary} PROPERTIES LINKER_LANGUAGE CXX)
            internal_target_objlib_sources(${packageLibrary} ${packageObjLibrary})

            # Add object files as sources to the package froup target
            internal_target_objlib_sources(${uorName} ${packageObjLibrary})
        else()
            # Add IDE target (https://gitlab.kitware.com/cmake/cmake/issues/15234)
            add_custom_target(${packageLibrary}-headers SOURCES ${packageHdrs})

            # target for tests
            add_library(${packageLibrary} INTERFACE)
        endif()

        # Add usage requirements to the package target for tests
        target_link_libraries(${packageLibrary} INTERFACE ${packageDeps} ${uorInterfaceTargets})
        bde_target_link_interface_target(${packageLibrary} ${packageInterfaceTarget} INTERFACE_ONLY)

        # Process package tests
        bde_struct_get_field(tests ${package} TEST_TARGETS)
        if (tests)
            foreach(test IN LISTS tests)
                target_link_libraries(${test} PRIVATE ${packageLibrary})
                bde_target_link_interface_target(${test} ${packageInterfaceTarget})
                bde_append_test_labels(${test} ${uorName})
            endforeach()

            set(packageTestName ${packageLibrary}.t)
            add_custom_target(${packageTestName})
            add_dependencies(${uorTestTarget} ${packageTestName})
            add_dependencies(${packageTestName} ${tests})
        endif()
    endforeach()

    if(allInterpackageDeps)
        list(REMOVE_ITEM allInterpackageDeps ${allPackageTargets})
        if(allInterpackageDeps)
            message(
                FATAL_ERROR
                "Found unresolved inter-package dependencies: \
                ${allInterpackageDeps}"
            )
        endif()
    endif()

endfunction()

function(bde_install_uor uor)
    bde_assert_no_extra_args()

    bde_struct_get_field(uorName ${uor} TARGET)
    bde_struct_get_field(depends ${uor} DEPENDS)
    bde_struct_get_field(interfaceTargets ${uor} INTERFACE_TARGETS)

    set(ufidInstallDir ${bde_install_lib_suffix}/${bde_install_ufid})

    # Install main target
    install(
        TARGETS ${uorName}
        EXPORT ${uorName}Targets
        COMPONENT "${uorName}"
        ARCHIVE DESTINATION ${ufidInstallDir}
        LIBRARY DESTINATION ${ufidInstallDir}
        RUNTIME DESTINATION ${ufidInstallDir}
    )

    if(CMAKE_HOST_UNIX)
        # This code will create a symlink to a corresponding "ufid" build.
        # Use with care.
        set(libName "${CMAKE_STATIC_LIBRARY_PREFIX}${uorName}${CMAKE_STATIC_LIBRARY_SUFFIX}")
        set(symlinkVal "${bde_install_ufid}/${libName}")
        set(symlinkFile "\$ENV{DESTDIR}/\${CMAKE_INSTALL_PREFIX}/${bde_install_lib_suffix}/${libName}")

        install(
            CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink ${symlinkVal} ${symlinkFile})"
            COMPONENT "${uorName}-symlinks"
            EXCLUDE_FROM_ALL
        )
    endif()

    install(
        EXPORT ${uorName}Targets
        DESTINATION "ufidInstallDir/cmake"
        COMPONENT "${uorName}"
    )

    # Install interface targets
    foreach(interfaceTarget IN LISTS interfaceTargets)
        bde_install_interface_target(
            ${interfaceTarget}
            EXPORT ${uorName}InterfaceTargets
        )
    endforeach()

    # Namespace is needed for disambuguation of
    # common interface target if multiple UORs built by this
    # project are used by an external project
    install(
        EXPORT ${uorName}InterfaceTargets
        DESTINATION "ufidInstallDir/cmake"
        NAMESPACE "${uorName}::"
        COMPONENT "${uorName}"
    )

    # Create the groupConfig.cmake for the build tree
    find_file(configFile "groupConfig.cmake.in" PATHS ${CMAKE_MODULE_PATH})
    set(group ${uorName})
    configure_file(
        ${configFile}
        "${PROJECT_BINARY_DIR}/${uorName}Config.cmake"
        @ONLY
    )
    unset(configFile)

    install(
        FILES "${PROJECT_BINARY_DIR}/${uorName}Config.cmake"
        DESTINATION "ufidInstallDir/cmake"
        COMPONENT "${uorName}"
    )

    # Create the group.pc for the build tree
    # In CMake a list is a string with ';' as an item separator.
    find_file(configFile "group.pc.in" PATHS ${CMAKE_MODULE_PATH})
    set(pc_depends ${depends})
    string(REPLACE ";" " " pc_depends "${pc_depends}")
    configure_file(
        ${configFile}
        "${PROJECT_BINARY_DIR}/${uorName}.pc"
        @ONLY
    )
    unset(configFile)

    install(
        FILES "${PROJECT_BINARY_DIR}/${uorName}.pc"
        DESTINATION "ufidInstallDir/pkgconfig"
        COMPONENT "${uorName}"
    )

    set(extraInstallArg)
    if(MSVC)
        set(extraInstallArg "-DBUILD_TYPE=${CMAKE_CFG_INTDIR}")
    endif()

    add_custom_target(
        "install.${uorName}"
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${uorName}"
            ${extraInstallArg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${uorName}-headers"
            ${extraInstallArg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        DEPENDS ${uorName}
    )
endfunction()
