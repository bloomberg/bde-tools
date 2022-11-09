include_guard()

include(CMakePrintHelpers)

# Find perl, but it's ok if it's missing
find_package(Perl)

# Find sim_cpp11_features.pl.  It's ok if it's missing, as it will be during
# dpkg builds.
if(PERL_FOUND AND NOT WIN32)
    message(TRACE
            "Found perl version ${PERL_VERSION_STRING} at ${PERL_EXECUTABLE}")
    find_program(SIM_CPP11
                 "sim_cpp11_features.pl"
                 PATHS ${CMAKE_CURRENT_LIST_DIR}/scripts
                 )
    if(SIM_CPP11)
        message(STATUS "Found sim_cpp11_features.pl in ${SIM_CPP11}")

        option(BBS_CPP11_VERIFY_NO_CHANGE "Verify that sim_cpp11_features generates no changes" OFF)
    else()
        message(STATUS "${CMAKE_CURRENT_LIST_DIR}")
        message(STATUS "sim_cpp11_features.pl not found - disabled")
    endif()
else()
    message(STATUS "Perl not found and/or on Windows - sim_cpp11_features.pl disabled")
endif()

option(BBS_USE_WAFSTYLEOUT "Use waf-style output wrapper" OFF)
if (BBS_USE_WAFSTYLEOUT)
    find_file(WAF_STYLE_OUT
              "wafstyleout.py"
              PATHS ${CMAKE_CURRENT_LIST_DIR}/scripts
              )

    if(WAF_STYLE_OUT)
        find_package(Python3 3.6 REQUIRED)

        # The compiler/linker launchers need a string
        set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${Python3_EXECUTABLE} ${WAF_STYLE_OUT}")
        set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "${Python3_EXECUTABLE} ${WAF_STYLE_OUT}")
        # Generic waf wrapper (for compilation and tests) needs a list
        set_property(GLOBAL PROPERTY BBS_CMD_WRAPPER "${Python3_EXECUTABLE}" "${WAF_STYLE_OUT}")
    else()
        message(FATAL_ERROR "waf style wrapper is not found")
    endif()
else()
    set_property(GLOBAL PROPERTY BBS_CMD_WRAPPER "")
endif()

#.rst:
# .. command:: bbs_add_target_include_dirs
#
# Add include directories for this target.
function(bbs_add_target_include_dirs target scope)
    foreach(arg ${ARGN})
        get_filename_component(dir ${arg} ABSOLUTE)
        target_include_directories(${target} ${scope} $<BUILD_INTERFACE:${dir}>
                                                      $<INSTALL_INTERFACE:include>)
    endforeach()
endfunction()

function(_bbs_defer_target_import target)
    set(_deferred_deps) # empty list
    foreach(dep ${ARGN})
        if (NOT TARGET ${dep})
            list(APPEND _deferred_deps ${dep})
        endif()
    endforeach()

    if (_deferred_deps)
        if (NOT WIN32)
            message(VERBOSE "Resolving required link libraries for ${target} : ${_deferred_deps}")
            bbs_import_pkgconfig_targets(${_deferred_deps})
        else()
            message(FATAL_ERROR "Unresolved external dependancies: ${_deferred_deps}")
        endif()
    endif()
endfunction()

#.rst:
# .. command:: bbs_import_target_dependencies
#
# Import dependencies of the target
function(bbs_import_target_dependencies target)
    if (WIN32)
        return()
    endif()

    set(_deferred_deps) # empty list
    foreach(dep ${ARGN})
        if (NOT TARGET ${dep})
            list(APPEND _deferred_deps ${dep})
        endif()
    endforeach()

    if (_deferred_deps)
        cmake_language(EVAL CODE "
        cmake_language(DEFER DIRECTORY ${CMAKE_SOURCE_DIR} CALL _bbs_defer_target_import [[${target}]] ${_deferred_deps})
        ")
    endif()

endfunction()

#.rst:
# .. command:: bbs_configure_target_tests
#
# Configure tests from the specified sources and
# add the target as their main build dependency.
function(bbs_configure_target_tests target)
    cmake_parse_arguments(""
                          ""
                          ""
                          "SOURCES;TEST_DEPS;LABELS"
                          ${ARGN})
    bbs_assert_no_unparsed_args("")

    if (NOT TARGET ${target}.t)
        add_custom_target(${target}.t)
    endif()

    if (NOT TARGET all.t)
        add_custom_target(all.t)
    endif()

    if (_SOURCES)
        bbs_add_component_tests(${target}
                                    SOURCES   ${_SOURCES}
                                    TEST_DEPS ${_TEST_DEPS}
                                    LABELS    ${_LABELS})
        set(${target}_TEST_TARGETS "${${target}_TEST_TARGETS}" PARENT_SCOPE)
    endif()
endfunction()



#.rst:
# .. command:: bbs_install_target_headers
#
# Generate installation command for target headers.
function (bbs_install_target_headers target)
    get_target_property(uor_name ${target} NAME)

    set(_install_include_dir "include") # the default.

    set(_install_interface_found FALSE)
    get_property(_target_interface_include
                 TARGET ${target}
                 PROPERTY INTERFACE_INCLUDE_DIRECTORIES)

    foreach(_i ${_target_interface_include})
        string(REGEX MATCH "^\\$<(BUILD|INSTALL)_INTERFACE:(.+)>"
               _match ${_i})
        if (_match)
            set(EXPRESSION_TYPE ${CMAKE_MATCH_1})
            set(EXPRESSION_DIR ${CMAKE_MATCH_2})
            if (EXPRESSION_TYPE STREQUAL "INSTALL")
                set(_install_interface_found TRUE)
                set(_install_include_dir ${EXPRESSION_DIR})
            endif()
        endif()
    endforeach(_i)

    if(NOT _install_interface_found)
        set_property(TARGET ${target}
                     APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     "$<INSTALL_INTERFACE:include>")
    endif()

    install(FILES ${${target}_INCLUDE_FILES}
            DESTINATION ${_install_include_dir}
            COMPONENT ${uor_name}-headers)
endfunction()

#.rst:
# .. command:: bbs_install_library
#
# Generate installation command for target.
function (bbs_install_library target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          ""
    )
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    # default the component to the target name normalized as a dpkg name
    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    get_target_property(_target_type ${target} TYPE)
    if (   _target_type STREQUAL "STATIC_LIBRARY"
        OR _target_type STREQUAL "SHARED_LIBRARY")
        install(TARGETS ${target}
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT ${_COMPONENT})
        bbs_install_target_headers(${target})

    elseif (_target_type STREQUAL "EXECUTABLE")
        install(
            TARGETS ${target}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            COMPONENT ${_COMPONENT})
    endif()
endfunction()

#.rst:
# .. command:: bbs_emit_pkg_config
#
# Emit package config for the target
function (bbs_emit_pkg_config target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          ""
    )
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    # default the component to the target name normalized as a dpkg name
    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    find_package(EmitPkgConfigFile QUIET)

    if (EmitPkgConfigFile_FOUND)
        emit_pkgconfig_file(TARGET ${target}
                            PREFIX "${CMAKE_INSTALL_PREFIX}"
                            VERSION "${BB_BUILDID_PKG_VERSION}" # todo: add real version
                            INSTALL_COMPONENT "${_COMPONENT}-pkgconfig")
    endif()
endfunction()

#.rst:
# .. command:: bbs_emit_bde_metadata
#
# Emit bde metadata for the target
# OBSOLETE
function (bbs_emit_bde_metadata target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          ""
    )
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    # default the component to the target name normalized as a dpkg name
    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    find_package(GenBDEMetadata QUIET)

    if (GenBDEMetadata_FOUND)
        gen_bde_metadata(TARGET ${target}
                         INSTALL_COMPONENT "${_COMPONENT}-bdemeta")
    endif()
endfunction()

#.rst:
# .. command:: bbs_generate_cpp03_sources
#
# Generate cpp03 source files.
function (bbs_generate_cpp03_sources srcFiles)
    if(SIM_CPP11)
        get_property(cmd_wrapper GLOBAL PROPERTY BBS_CMD_WRAPPER)

        foreach(srcFile ${srcFiles})
            if(${srcFile} MATCHES "_cpp03\.")
                set(cpp11VerifyOption "")
                set(cpp11Operation "generation")

                if(BBS_CPP11_VERIFY_NO_CHANGE)
                    set(cpp11VerifyOption "--verify-no-change")
                    set(cpp11Operation "validation")
                endif()

                string(REPLACE "_cpp03." "." cpp11SrcFile ${srcFile})
                message(TRACE "sim_cpp11 ${cpp11Operation}: ${cpp11SrcFile} -> ${srcFile}")

                add_custom_command(
                    OUTPUT    "${srcFile}"
                    COMMAND   ${cmd_wrapper} "${PERL_EXECUTABLE}" "${SIM_CPP11}" ${cpp11VerifyOption} "${cpp11SrcFile}"
                    DEPENDS   "${cpp11SrcFile}")
            endif()
        endforeach()
    endif()
endfunction()

#.rst:
# .. command:: bbs_setup_target_uor
#
# Parse metadata and populate UOR target.
function(bbs_setup_target_uor target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          "SKIP_TESTS;NO_GEN_BDE_METADATA;NO_EMIT_PKG_CONFIG_FILE"
                          "SOURCE_DIR"
                          "CUSTOM_PACKAGES")
    bbs_assert_no_unparsed_args("")

    # Get the name of the unit from the target
    get_target_property(uor_name ${target} NAME)

    message(VERBOSE "Processing target \"${target}\"")

    # Use the current source directory if none is specified
    if (NOT _SOURCE_DIR)
        set(_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    endif()

    if (DEFINED BUILD_TESTING AND NOT BUILD_TESTING)
        set(_SKIP_TESTS TRUE)
    endif()

    # Check that BDE metadata exists and load it
    if (EXISTS ${_SOURCE_DIR}/group)
        bbs_read_metadata(GROUP ${uor_name}
                          SOURCE_DIR ${_SOURCE_DIR}
                          CUSTOM_PACKAGES "${_CUSTOM_PACKAGES}")
    else()
        if (EXISTS ${_SOURCE_DIR}/package)
            bbs_read_metadata(PACKAGE ${uor_name}
                              SOURCE_DIR ${_SOURCE_DIR})
        endif()
    endif()

    if (NOT ${uor_name}_METADATA_DIRS)
        message(FATAL_ERROR "Failed to find metadata for BDE unit: ${uor_name}")
    endif()

    # Check if the target is a library or executable
    get_target_property(_target_type ${target} TYPE)

    if (   _target_type STREQUAL "STATIC_LIBRARY"
        OR _target_type STREQUAL "SHARED_LIBRARY"
        OR _target_type STREQUAL "OBJECT_LIBRARY")
        # Ensure that the unit has at least one source file
        if (NOT ${uor_name}_SOURCE_FILES)
            message(FATAL_ERROR "No source files found for library: ${uor_name}")
        endif()

        # Check that there is no main file
        if (${uor_name}_MAIN_SOURCE)
            get_filename_component(_main_file ${${uor_name}_MAIN_SOURCE} NAME)
            message(FATAL_ERROR "Main file found in library ${uor_name}: ${_main_file}")
        endif()

        # Each package in the groups is an individual OBJECT library
        if (${uor_name}_PACKAGES)
            foreach(pkg ${${uor_name}_PACKAGES})
                # Check if this is customized package
                if (${pkg} IN_LIST _CUSTOM_PACKAGES)
                    message(TRACE "Processing customized ${pkg}")
                    add_subdirectory(${_SOURCE_DIR}/${pkg})

                    # Custom package can "export" ether OBJECT library target (if it contains
                    # compilable sources) or INTERFACE library target if it is header-only
                    # package. All we do here is to add group dependencies to the package
                    # and add it as a dependency to the group.
                    if (TARGET ${pkg}-obj)
                        target_link_libraries(${pkg}-obj PUBLIC ${${uor_name}_PCDEPS})
                        target_link_libraries(${target} PUBLIC ${pkg}-obj)
                    elseif (TARGET ${pkg}-iface)
                        target_link_libraries(${pkg}-iface INTERFACE ${${uor_name}_PCDEPS})
                        target_link_libraries(${target} INTERFACE ${pkg}-iface)
                    endif()
                else()
                    message(TRACE "Processing ${pkg}")

                    add_library(${pkg}-obj OBJECT ${${pkg}_SOURCE_FILES} ${${pkg}_INCLUDE_FILES})
                    set_target_properties(${pkg}-obj PROPERTIES LINKER_LANGUAGE CXX)
                    bbs_add_target_include_dirs(${pkg}-obj PUBLIC ${${pkg}_INCLUDE_DIRS})
                    target_link_libraries(${pkg}-obj PUBLIC bbs_bde_flags)

                    add_library(${pkg}-iface INTERFACE)
                    target_link_libraries(${pkg}-iface INTERFACE ${pkg}-obj)

                    add_library(${pkg} STATIC)
                    target_link_libraries(${pkg} PUBLIC ${pkg}-obj)

                    # Important: link with DEPENDS and not PCDEPS for packages
                    # in a groups. For groups with underscores (z_bae) we do
                    # not want to use pc-fied name like z-baelu.
                    # For the group's dependencies (external) we use PCDEPS.
                    # This is different from a standalone packages that can
                    # have only external PC dependencies.
                    foreach(p ${${pkg}_DEPENDS})
                        target_link_libraries(${pkg}-obj PUBLIC ${p}-iface)

                        target_link_libraries(${pkg} PUBLIC ${p})
                    endforeach()

                    target_link_libraries(${pkg}-obj PUBLIC ${${uor_name}_PCDEPS})

                    target_link_libraries(${target} PUBLIC ${pkg}-obj)

                    # Generating cpp03 header and implementation files if any
                    bbs_generate_cpp03_sources("${${pkg}_INCLUDE_FILES}")
                    bbs_generate_cpp03_sources("${${pkg}_SOURCE_FILES}")

                    if (NOT _SKIP_TESTS)
                        bbs_configure_target_tests(${pkg}
                                                   SOURCES   ${${pkg}_TEST_SOURCES}
                                                   TEST_DEPS ${${pkg}_DEPENDS}
                                                             ${${pkg}_TEST_DEPENDS}
                                                             ${${uor_name}_PCDEPS}
                                                             ${${uor_name}_TEST_PCDEPS}
                                                   LABELS    "all" ${target} ${pkg})
                    endif()
                endif()
            endforeach()

            set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)

            target_link_libraries(${target} PUBLIC ${${uor_name}_PCDEPS}
                                            INTERFACE bbs_threads bbs_bde_flags)

            bbs_import_target_dependencies(${target} ${${uor_name}_PCDEPS})

            if (NOT _SKIP_TESTS)
                if (NOT TARGET ${target}.t)
                    add_custom_target(${target}.t)
                endif()
                set(import_test_deps ON)
                foreach(pkg ${${uor_name}_PACKAGES})
                    if (${pkg}_TEST_TARGETS)
                        add_dependencies(${target}.t ${${pkg}_TEST_TARGETS})
                        if (import_test_deps)
                            # Import UOR test dependencies only once and only if we have at least
                            # one generated test target
                            bbs_import_target_dependencies(${target} ${${uor_name}_TEST_PCDEPS})
                            set(import_test_deps OFF)
                        endif()
                    endif()
                endforeach()
            endif()
        else()
            # Configure standalone library ( no packages ) and tests from BDE metadata
            message(VERBOSE "Adding library for ${target}")
            set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)
            target_sources(${target} PRIVATE ${${uor_name}_SOURCE_FILES})
            bbs_add_target_include_dirs(${target} PUBLIC ${${uor_name}_INCLUDE_DIRS})

            target_link_libraries(${target} PUBLIC    ${${uor_name}_PCDEPS}
                                            INTERFACE bbs_threads bbs_bde_flags)

            bbs_import_target_dependencies(${target} ${${uor_name}_PCDEPS})
            if (NOT _SKIP_TESTS)
                bbs_configure_target_tests(${target}
                                           SOURCES    ${${uor_name}_TEST_SOURCES}
                                           TEST_DEPS  ${${uor_name}_PCDEPS}
                                                      ${${uor_name}_TEST_PCDEPS}
                                           LABELS     "all" ${target})
                if (${target}_TEST_TARGETS)
                    bbs_import_target_dependencies(${target} ${${uor_name}_TEST_PCDEPS})
                endif()
            endif()
        endif()

        # Generating .pc file. This will be a noop in non-Bloomberg build env.
        if (NOT _NO_EMIT_PKG_CONFIG_FILE)
            bbs_emit_pkg_config(${target})
        endif()

        # Create an alias library with the pkgconfig name, if it is different from
        # the uor name and such a target doesn't exist yet.
        bbs_uor_to_pc_name(${uor_name} pc_name)
        if (NOT TARGET ${pc_name} AND NOT uor_name STREQUAL pc_name)
            add_library(${pc_name} ALIAS ${target})
        endif()

    elseif (_target_type STREQUAL "EXECUTABLE")
        # Configure application package from BDE metadata. Fail if we loaded
        # metadata for a package group.
        if (${uor_name}_PACKAGES)
            message(FATAL_ERROR "Cannot create executable from package group: ${uor_name}")
        endif()

        message(TRACE "Processing application ${uor_name}")
        # We need a main file to build

        if (NOT ${uor_name}_MAIN_SOURCE)
            message(FATAL_ERROR "No main source found for application package: ${uor_name}")
        endif()

        set(lib_target "${uor_name}_lib")

        # Create a static or interface library that can be reused by both the
        # executable and its test drivers. An static library must have sources and
        # is used if this package contains component files, otherwise an interface
        # library is created.
        if (${uor_name}_SOURCE_FILES)
            add_library(${lib_target} STATIC)

            set_target_properties(${lib_target} PROPERTIES LINKER_LANGUAGE CXX)
            target_sources(${lib_target} PRIVATE "${${uor_name}_SOURCE_FILES}")
            bbs_add_target_include_dirs(${lib_target} PUBLIC "${${uor_name}_INCLUDE_DIRS}")
            target_link_libraries(${lib_target} PUBLIC "${${uor_name}_PCDEPS}")

            # Copy properties from executable target to corresponding properties
            # of created ${lib_target} target. This will correctly set compiler/linker
            # flags for sources based on the flags specified for executable target by user.
            foreach(prop LINK_LIBRARIES INCLUDE_DIRECTORIES COMPILE_FEATURES COMPILE_DEFINITIONS COMPILE_OPTIONS)
                get_target_property(value ${target} ${prop})
                if (value)
                    # All ${uor_name}_SOURCE_FILES should have correct flags.
                    set_property(TARGET ${lib_target} APPEND PROPERTY ${prop} ${value})
                    # All dependencies (executable and test drivers) should have correct flags.
                    set_property(TARGET ${lib_target} APPEND PROPERTY INTERFACE_${prop} ${value})
                endif()
            endforeach()
        else()
            add_library(${lib_target} INTERFACE)

            target_link_libraries(${lib_target} INTERFACE "${${uor_name}_PCDEPS}")
            bbs_add_target_include_dirs(${lib_target} INTERFACE "${${uor_name}_INCLUDE_DIRS}")

            # Copy properties from executable target to corresponding INTERFACE_* properties
            # of created ${lib_target} target. This will correctly set compiler/linker
            # flags for sources based on the flags specified for executable target by user.
            foreach(prop LINK_LIBRARIES INCLUDE_DIRECTORIES COMPILE_FEATURES COMPILE_DEFINITIONS COMPILE_OPTIONS)
                get_target_property(value ${target} ${prop})
                if (value)
                    # All dependencies (executable and test drivers) should have correct flags.
                    set_property(TARGET ${lib_target} APPEND PROPERTY INTERFACE_${prop} ${value})
                endif()
            endforeach()
        endif()

        bbs_import_target_dependencies(${lib_target} "${${uor_name}_PCDEPS}")

        # Build the main source and link against the private library
        set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)
        target_sources(${target} PRIVATE ${${uor_name}_MAIN_SOURCE})
        target_link_libraries(${target} PRIVATE ${lib_target})

        # Set up tests and link against the private library
        if (NOT _SKIP_TESTS)
            bbs_configure_target_tests(${lib_target}
                                       SOURCES    ${${uor_name}_TEST_SOURCES}
                                       TEST_DEPS  ${${uor_name}_PCDEPS}
                                                  ${${uor_name}_TEST_PCDEPS}
                                       LABELS     "all" ${target})
            if (${lib_target}_TEST_TARGETS)
                bbs_import_target_dependencies(${lib_target} ${${uor_name}_TEST_PCDEPS})
            endif()
        endif()
    else()
        # Not a library or an application
        message( FATAL_ERROR "Invalid target type for BDE target: ${_TARGET_TYPE}")
    endif()

    # Installation
    if (_target_type STREQUAL "STATIC_LIBRARY")
        bbs_install_library(${target})
    endif()
endfunction()

function(bbs_setup_header_only_pkg pkg)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "SOURCE_DIR"
                          "")
    bbs_assert_no_unparsed_args("")

    bbs_read_package_metadata(${pkg} ${CMAKE_CURRENT_SOURCE_DIR})

    # Create package interface library with include folder.
    add_library(${pkg}-iface INTERFACE)
    bbs_add_target_include_dirs(${pkg}-iface INTERFACE ${${pkg}_INCLUDE_DIRS})

    # Create package library with transitive dependency on interface.
    add_library(${pkg} INTERFACE)
    target_link_libraries(${pkg} INTERFACE ${pkg}-iface)

    # Add inter-package dependencies for interface and package libraries.
    foreach(p ${${pkg}_PCDEPS})
        target_link_libraries(${pkg}-iface INTERFACE ${p}-iface)
        target_link_libraries(${pkg} INTERFACE ${p})
    endforeach()

    list(APPEND bsl_INCLUDE_FILES ${${pkg}_INCLUDE_FILES})
    set(bsl_INCLUDE_FILES  ${bsl_INCLUDE_FILES}  PARENT_SCOPE)
endfunction()
