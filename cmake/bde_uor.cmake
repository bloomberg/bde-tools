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

function(bde_list_template_substitute output placeholder template)
    set(out)
    foreach(target ${ARGN})
        string(REPLACE ${placeholder} ${target} elem ${template})
        list(APPEND out ${elem})
    endforeach()
    set(${output} ${out} PARENT_SCOPE)
endfunction()

function(bde_target_objlib_sources target)
    bde_list_template_substitute(objSources "%" "$<TARGET_OBJECTS:%>" ${ARGN})
    target_sources(${target} PRIVATE ${objSources})
endfunction()

function(bde_process_standard_package outName list_file uorName)
    get_filename_component(packageName ${list_file} NAME_WE)
    get_filename_component(list_dir ${list_file} DIRECTORY)
    get_filename_component(root_dir ${list_dir} DIRECTORY)

    bde_add_info_target(${packageName})
    set(${outName} ${packageName} PARENT_SCOPE)

    # Sources and headers
    bde_utils_add_meta_file("${list_dir}/${packageName}.mem" components TRACK)
    bde_list_template_substitute(sources "%" "${root_dir}/%.cpp" ${components})
    bde_list_template_substitute(headers "%" "${root_dir}/%.h" ${components})
    bde_info_target_set_property(${packageName} SOURCES "${sources}")
    bde_info_target_set_property(${packageName} HEADERS "${headers}")

    # Dependencies
    bde_utils_add_meta_file("${list_dir}/${packageName}.dep" dependencies TRACK)
    bde_info_target_set_property(${packageName} DEPENDS "${dependencies}")

    # Tests
    bde_list_template_substitute(test_targets "%" "%.t" ${components})
    foreach (component ${components})
        add_test_executable(${component} ${root_dir}/${component}.t.cpp)
    endforeach()
    bde_info_target_set_property(${packageName} TEST_TARGETS "${test_targets}")

    # Include directories
    bde_add_interface_target(${packageName})
    bde_info_target_set_property(${packageName} INTERFACE_TARGET ${packageName})
    bde_interface_target_include_directories(
        ${packageName} 
        PUBLIC
            $<BUILD_INTERFACE:${root_dir}>
            $<INSTALL_INTERFACE:"include">
    )

    # By default all headers are installed in 'include'.
    install(
        FILES ${headers}
        DESTINATION "include"
        COMPONENT "${uorName}-headers"
    )
endfunction()

# Include the package cmake file if it exists.
# If it doesn't, use default processing
function(_bde_include_package outName groupRootDir package uorName)
    set(packageFileName "${groupRootDir}/${package}/package/${package}.cmake")
    if(EXISTS "${packageFileName}")
        bde_reset_function(process_package)
        include("${packageFileName}")
        process_package(infoTarget "${packageFileName}" "${uorName}")
    else()
        bde_process_standard_package(infoTarget "${packageFileName}" "${uorName}")
    endif()

    bde_info_target_name(info_target ${infoTarget})
    if (NOT TARGET ${info_target})
        message(
            FATAL_ERROR
            "${package} failed to create "
            "info target (see bde_add_info_target)."
        )
    endif()
    set(${outName} ${infoTarget} PARENT_SCOPE)
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
function(bde_project_add_group outName list_file)
    #TODO: implement additional options.
    get_filename_component(uorName ${list_file} NAME_WE)
    get_filename_component(list_dir ${list_file} DIRECTORY)
    get_filename_component(root_dir ${list_dir} DIRECTORY)

    message(STATUS "[${uorName}]: Start processing")

    bde_add_info_target(${uorName})
    set(${outName} ${uorName} PARENT_SCOPE)
    bde_info_target_set_property(${uorName} TARGET "${uorName}")
    bde_info_target_set_property(${uorName} TEST_TARGETS "${uorName}.t")

    # Sources and headers
    bde_utils_add_meta_file("${list_dir}/${uorName}.mem" packages TRACK)

    # Dependencies
    bde_utils_add_meta_file("${list_dir}/${uorName}.dep" dependencies TRACK)
    bde_info_target_set_property(${uorName} DEPENDS "${dependencies}")

    # ${uorName} interface target contains _only_ the build requirements
    # specified for the UOR itself. It does NOT contain the requirements
    # transitively included from the member packages. This interface
    # target is only used directly by the test targets.
    bde_add_interface_target(${uorName})
    bde_interface_target_names(uor_interface_targets ${uorName})
    bde_interface_target_link_libraries(${uorName} PUBLIC ${dependencies})

    cmake_parse_arguments("" "" "COMMON_INTERFACE_TARGET" "" ${ARGN})
    if (_COMMON_INTERFACE_TARGET)
        bde_interface_target_assimilate(${uorName} ${_COMMON_INTERFACE_TARGET})
    endif()

    # ${uorName}-full interface target contains both the requirements of
    # the UOR itself and all the requirements of the member packages.
    # This interface target is used for the building the final library
    # as well as the external users.
    bde_add_interface_target(${uorName}-full)
    bde_interface_target_names(uor_full_interface_targets ${uorName}-full)
    bde_interface_target_assimilate(${uorName}-full ${uorName})

    # Declare the library, with compiler and linker flags
    add_library(${uorName} "")
    bde_target_link_interface_target(${uorName} ${uorName}-full)
    set_target_properties(${uorName} PROPERTIES LINKER_LANGUAGE CXX)

    # process packages
    add_custom_target("${uorName}.t")
    foreach(package ${packages})
        _bde_include_package(packageInfoName ${root_dir} ${package} ${uorName})
        bde_info_target_get_property(interface_target ${packageInfoName} INTERFACE_TARGET)

        # Add package usage requirements to the package group target
        bde_interface_target_assimilate(${uorName}-full ${interface_target})
        bde_install_interface_target(${interface_target} EXPORT ${uorName}InterfaceTargets)

        bde_info_target_get_property(srcs ${packageInfoName} SOURCES)
        bde_info_target_get_property(hdrs ${packageInfoName} HEADERS)
        bde_info_target_get_property(hdrs_suffix ${packageInfoName} HEADERS_INSTALL_SUFFIX)
        bde_info_target_get_property(deps ${packageInfoName} DEPENDS)

        message(
            STATUS
            "[${uorName}]: Processing package [${package}] "
            "(${deps})"
        )

        bde_interface_target_names(package_interface_targets ${interface_target})

        set(
            all_package_depends
            # Requirements specific to this particular package
            ${package_interface_targets}
            # Inter-package dependencies
            ${deps}
            # 'Pure' requirements of the package
            ${uor_interface_targets}
        )

        if(srcs)
            # object library
            add_library(
                ${package}-obj
                OBJECT EXCLUDE_FROM_ALL
                ${srcs} ${hdrs}
            )

            # CMake as of 3.10 does not allow calling target_link_libraries
            # on OBJECT libraries. This command, however successfully imports
            # the build requirements, such as compiler options and include
            # directories
            set_target_properties(
                ${package}-obj
                PROPERTIES
                    LINK_LIBRARIES "${all_package_depends}"
            )

            # target for tests
            add_library(${package} EXCLUDE_FROM_ALL "")
            set_target_properties(${package} PROPERTIES LINKER_LANGUAGE CXX)
            bde_target_objlib_sources(${package} ${package}-obj)

            # Add object files as sources to the package froup target
            bde_target_objlib_sources(${uorName} ${package}-obj)
        else()
            # Add IDE target (https://gitlab.kitware.com/cmake/cmake/issues/15234)
            add_custom_target(${package}-headers SOURCES ${hdrs})

            # target for tests
            add_library(${package} INTERFACE)
        endif()

        # Add usage requirements to the package target for tests
        target_link_libraries(${package} INTERFACE ${all_package_depends})

        # Process package tests
        bde_info_target_get_property(tests ${packageInfoName} TEST_TARGETS)
        if (tests)
            foreach (test ${tests})
                target_link_libraries(${test} ${package})
            endforeach()

            add_custom_target(${package}.t)
            add_dependencies(${package}.t ${tests})
            add_dependencies(${uorName}.t ${package}.t)
        endif()
    endforeach()

    message(STATUS "[${uorName}]: Dependencies are resolved")

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

        install(
            CODE "message(\" -- ${symlink_val} ${symlink_file}\")"
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
    bde_install_interface_target(${uorName}-full EXPORT ${uorName}InterfaceTargets)
    bde_install_interface_target(${uorName} EXPORT ${uorName}InterfaceTargets)
    if (_COMMON_INTERFACE_TARGET)
        bde_install_interface_target(
            ${_COMMON_INTERFACE_TARGET}
            EXPORT ${uorName}InterfaceTargets
        )
    endif()

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
    set(depends ${dependencies})
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

    message(STATUS "[${uorName}]: Done")
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
function(bde_project_add_application appName)
endfunction()
