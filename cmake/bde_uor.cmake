## bde_our.cmake
## ~~~~~~~~~~~~~~~
#  This CMake module exposes a set of functions for adding UOR with BDE
#  Metadata. Three types of UORs are supported:
#    - Package Group
#    - Standalone Package
#    - Application
#
## OVERVIEW
## --------
# o bde_project_add_group..............: Add a Package Group UOR to build.
# o bde_project_add_standalone_package.: Add a Standalone Package UOR to build.
# o bde_project_add_application........: Add an Application UOR to build.
# o bde_project_add_uor................: Add a UOR to build. The above are
#                                        convenience wrappers to this function.
# o bde_project_add_uor_subdirectory...: Add the subdirectory of a UOR only if
#                                        that UOR should be installed. (mostly
#                                        usefull on repositories with multiple
#                                        independently released UORs).
#
## ========================================================================= ##
if(BDE_UOR_INCLUDED)
  return()
endif()
set(BDE_UOR_INCLUDED true)

# Standard CMake modules.

# BDE CMake modules.
include(bde_test_drivers)
include(bde_metadata)
include(bde_special_targets)
include(bde_utils)

function(bde_append_test_labels test)
    set_property(
        TEST ${test}
        APPEND PROPERTY
        LABELS ${ARGN}
    )
endfunction()

function(bde_target_objlib_sources target)
    bde_list_template_substitute(objSources "%" "$<TARGET_OBJECTS:%>" ${ARGN})
    target_sources(${target} PRIVATE ${objSources})
endfunction()

function(bde_process_standard_package outInfoTarget listFile uorName)
    get_filename_component(packageName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_add_info_target(${packageName})
    set(${outInfoTarget} ${packageName} PARENT_SCOPE)

    # Sources and headers
    bde_utils_add_meta_file("${listDir}/${packageName}.mem" components TRACK)
    bde_list_template_substitute(sources "%" "${rootDir}/%.cpp" ${components})
    bde_list_template_substitute(headers "%" "${rootDir}/%.h" ${components})
    bde_info_target_set_property(${packageName} SOURCES "${sources}")
    bde_info_target_set_property(${packageName} HEADERS "${headers}")

    # Dependencies
    bde_utils_add_meta_file("${listDir}/${packageName}.dep" dependencies TRACK)
    bde_info_target_set_property(${packageName} DEPENDS "${dependencies}")

    # Tests
    bde_list_template_substitute(test_targets "%" "%.t" ${components})
    foreach (component ${components})
        add_test_executable(${component} ${rootDir}/${component}.t.cpp)
    endforeach()
    bde_info_target_set_property(${packageName} TEST_TARGETS "${test_targets}")

    # Include directories
    bde_add_interface_target(${packageName})
    bde_info_target_set_property(${packageName} INTERFACE_TARGET ${packageName})
    bde_interface_target_include_directories(
        ${packageName}
        PUBLIC
            $<BUILD_INTERFACE:${rootDir}>
            $<INSTALL_INTERFACE:"include">
    )

    # By default all headers are installed in 'include'.
    install(
        FILES ${headers}
        DESTINATION "include"
        COMPONENT "${uorName}-headers"
    )
endfunction()

function(bde_install_uor uorInfoTarget)
    bde_info_target_get_property(uorName ${uorInfoTarget} TARGET)
    bde_info_target_get_property(depends ${uorInfoTarget} DEPENDS)
    bde_info_target_get_property(interfaceTargets ${uorInfoTarget} INTERFACE_TARGETS)

    # Install main target
    install(
        TARGETS ${uorName}
        EXPORT ${uorName}Targets
        COMPONENT "${uorName}"
        ARCHIVE DESTINATION ${bde_install_lib_suffix}/${bde_install_ufid}
        LIBRARY DESTINATION ${bde_install_lib_suffix}/${bde_install_ufid}
        RUNTIME DESTINATION ${bde_install_lib_suffix}/${bde_install_ufid}
    )

    if(CMAKE_HOST_UNIX)
        # This code will create a symlink to a corresponding "ufid" build.
        # Use with care.
        set(libName "${CMAKE_STATIC_LIBRARY_PREFIX}${uorName}${CMAKE_STATIC_LIBRARY_SUFFIX}")
        set(symlink_val "${bde_install_ufid}/${libName}")
        set(symlink_file "\$ENV{DESTDIR}/\${CMAKE_INSTALL_PREFIX}/${bde_install_lib_suffix}/${libName}")

        install(
            CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink ${symlink_val} ${symlink_file})"
            COMPONENT "${uorName}-symlinks"
            EXCLUDE_FROM_ALL
        )
    endif()

    install(
        EXPORT ${uorName}Targets
        DESTINATION "${bde_install_lib_suffix}/${bde_install_ufid}/cmake"
        COMPONENT "${uorName}"
    )

    # Install interface targets
    foreach(interfaceTarget ${interfaceTargets})
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
        DESTINATION "${bde_install_lib_suffix}/${bde_install_ufid}/cmake"
        NAMESPACE "${uorName}::"
        COMPONENT "${uorName}"
    )

    # Create the groupConfig.cmake for the build tree
    set(group ${uorName})
    configure_file(
        "${CMAKE_MODULE_PATH}/groupConfig.cmake.in"
        "${PROJECT_BINARY_DIR}/${uorName}Config.cmake"
        @ONLY
    )

    install(
        FILES "${PROJECT_BINARY_DIR}/${uorName}Config.cmake"
        DESTINATION "${bde_install_lib_suffix}/${bde_install_ufid}/cmake"
        COMPONENT "${uorName}"
    )

    # Create the group.pc for the build tree
    # In CMake a list is a string with ';' as an item separator.
    set(pc_depends ${depends})
    string(REPLACE ";" " " pc_depends "${pc_depends}")
    configure_file(
        "${CMAKE_MODULE_PATH}/group.pc.in"
        "${PROJECT_BINARY_DIR}/${uorName}.pc"
        @ONLY
    )

    install(
        FILES "${PROJECT_BINARY_DIR}/${uorName}.pc"
        DESTINATION "${bde_install_lib_suffix}/${bde_install_ufid}/pkgconfig"
        COMPONENT "${uorName}"
    )

    set(extra_install_arg)
    if(MSVC)
        set(extra_install_arg "-DBUILD_TYPE=${CMAKE_CFG_INTDIR}")
    endif()

    add_custom_target(
        "install.${uorName}"
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${uorName}"
            ${extra_install_arg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        COMMAND ${CMAKE_COMMAND}
            -DCOMPONENT="${uorName}-headers"
            ${extra_install_arg}
            -P ${CMAKE_BINARY_DIR}/cmake_install.cmake
        DEPENDS ${uorName}
    )
endfunction()

function(bde_prepare_uor uorName uorInfoTarget uorDepends uorType)
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

    bde_add_info_target(${uorInfoTarget})
    bde_info_target_set_property(${uorInfoTarget} TARGET "${uorName}")
    bde_info_target_set_property(${uorInfoTarget} DEPENDS "${uorDepends}")
endfunction()

function(bde_project_add_uor uorInfoTarget packageInfoTargets)
    bde_info_target_get_property(uorName ${uorInfoTarget} TARGET)
    bde_info_target_get_property(uorDeps ${uorInfoTarget} DEPENDS)

    # uorInterfaceTarget contains _only_ the build requirements
    # specified for the UOR itself. It does NOT contain the requirements
    # transitively included from the member packages. This interface
    # target is only used directly by the test targets.
    set(uorInterfaceTarget ${uorInfoTarget})
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
    bde_info_target_set_property(${uorInfoTarget} TEST_TARGETS ${uorTestTarget})

    # Process packages using their info targets
    bde_info_target_set_property(
        ${uorInfoTarget}
        INTERFACE_TARGETS
            ${uorInterfaceTarget}
            ${uorFullInterfaceTarget}
    )
    foreach(packageInfoTarget ${packageInfoTargets})
        set(packageName ${packageInfoTarget})
        bde_info_target_get_property(
            packageInterfaceTarget ${packageInfoTarget} INTERFACE_TARGET
        )

        # Add package usage requirements to the UOR target
        bde_interface_target_assimilate(${uorFullInterfaceTarget} ${packageInterfaceTarget})
        bde_info_target_append_property(
            ${uorInfoTarget}
            INTERFACE_TARGETS
                ${packageInterfaceTarget}
        )

        bde_info_target_get_property(packageSrcs ${packageInfoTarget} SOURCES)
        bde_info_target_get_property(packageHdrs ${packageInfoTarget} HEADERS)
        bde_info_target_get_property(packageDeps ${packageInfoTarget} DEPENDS)

        bde_log(
            VERBOSE
            "[${uorName}]: Incorporating package [${packageName}] (${packageDeps})"
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
            bde_target_objlib_sources(${packageLibrary} ${packageObjLibrary})

            # Add object files as sources to the package froup target
            bde_target_objlib_sources(${uorName} ${packageObjLibrary})
        else()
            # Add IDE target (https://gitlab.kitware.com/cmake/cmake/issues/15234)
            add_custom_target(${packageLibrary}-headers SOURCES ${packageHdrs})

            # target for tests
            add_library(${packageLibrary} INTERFACE)
        endif()

        # Add usage requirements to the package target for tests
        target_link_libraries(${packageLibrary} INTERFACE ${allPackageDepends})

        # Process package tests
        bde_info_target_get_property(tests ${packageInfoTarget} TEST_TARGETS)
        if (tests)
            foreach (test ${tests})
                target_link_libraries(${test} ${packageLibrary})
                bde_append_test_labels(${test} ${uorName} ${packageName})
            endforeach()

            set(packageTestTarget ${packageLibrary}.t)
            add_custom_target(${packageTestTarget})
            add_dependencies(${uorTestTarget} ${packageTestTarget})
            add_dependencies(${packageTestTarget} ${tests})
        endif()
    endforeach()
endfunction()


# :: bde_project_add_group ::
# -----------------------------------------------------------------------------
# Function to add a new group library having the specified 'groupName' name.
#
# Options
# -------
#
# Target Properties
# -----------------
# The following properties are set on the target:
#  o BDE_GROUP_COMPONENTS: list of components part of this group (in the format
#                          'grppkg/grppkg_component')
#  o BDE_INSTALL_MANIFEST: list of all files installed by this target (in a
#                          location relative to CMAKE_PREFIX_PATH). Note that
#                          the property is only populated if the target is in
#                          the INSTALL_TARGETS.
#
# NOTE
# ----
#  o If 'groupName' is left blank, it will be derived from the name of the
#    current directory.
#
function(bde_project_add_group outInfoTarget listFile)
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
    foreach(packageName ${packages})
        bde_log(
            VERBOSE
            "[${uorName}]: Processing package [${packageName}]"
        )

        bde_default_process_uor(
            packageInfoTarget "${rootDir}/${packageName}"
            package package ${uorName}
        )
        list(APPEND packageInfoTargets ${packageInfoTarget})
    endforeach()

    bde_prepare_uor(${uorName} ${uorName} "${dependencies}" LIBRARY)
    bde_project_add_uor(${uorName} "${packageInfoTargets}" ${ARGN})
    set(${outInfoTarget} ${uorName} PARENT_SCOPE)

    bde_log(VERBOSE "[${uorName}]: Done")
endfunction()

macro(_bde_project_add_standalone outInfoTarget listFile uorType)
    get_filename_component(uorName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)
    get_filename_component(rootDir ${listDir} DIRECTORY)

    bde_log(VERBOSE "[${uorName}]: Start processing")

    bde_process_standard_package(packageInfoTarget ${listFile} ${uorName})

    # Standalone dependencies should be interpreted as UOR
    # dependencies in 'bde_prepare_uor'
    bde_info_target_get_property(packageDeps ${packageInfoTarget} DEPENDS)
    bde_info_target_set_property(${packageInfoTarget} DEPENDS "")

    set(infoTarget ${uorName}-standalone)
    bde_prepare_uor(${uorName} ${infoTarget} "${packageDeps}" ${uorType})
    bde_project_add_uor(${infoTarget} ${packageInfoTarget} ${ARGN})
    set(${outInfoTarget} ${infoTarget} PARENT_SCOPE)

    bde_log(VERBOSE "[${uorName}]: Done")
endmacro()

function(bde_project_add_standalone_package outInfoTarget listFile)
    _bde_project_add_standalone(${outInfoTarget} ${listFile} LIBRARY ${ARGN})
endfunction()

function(bde_project_add_application outInfoTarget listFile)
    _bde_project_add_standalone(${outInfoTarget} ${listFile} APPLICATION ${ARGN})
endfunction()

# :: bde_project_add_application ::
# -----------------------------------------------------------------------------
# Function to add a new application having the specified 'appName'.
#
# Options
# -------
#
# Target Properties
# -----------------
#
# NOTE
# ----
#  o If 'appName' is left blank, it will be derived from the name of the
#    current directory.
#
