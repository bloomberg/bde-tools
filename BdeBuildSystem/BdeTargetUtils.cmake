include_guard()

#[[.rst:
BdeTargetUtils
--------------
This module provide a set of function to create and populate bde targets.
#]]

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
              NO_DEFAULT_PATH
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

find_file(CHECK_CYCLES
          "check_cycles.py"
          PATHS ${CMAKE_CURRENT_LIST_DIR}/scripts
          NO_DEFAULT_PATH
          )

if(CHECK_CYCLES)
    message(STATUS "Found check_cycles.py in ${CHECK_CYCLES}")
endif()

if (NOT BBS_UOR_CONFIG_IN)
    find_file(BBS_UOR_CONFIG_IN
              "uorConfig.cmake.in"
              PATHS ${CMAKE_CURRENT_LIST_DIR}/support
              )
endif()

#[[.rst:
.. command:: bbs_add_target_include_dirs

  Add include directories for this target.
#]]
function(bbs_add_target_include_dirs target scope)
    foreach(arg ${ARGN})
        get_filename_component(dir ${arg} ABSOLUTE)
        target_include_directories(${target} ${scope} $<BUILD_INTERFACE:${dir}>
                                                      $<INSTALL_INTERFACE:include>)
    endforeach()
endfunction()

# Try to find an external dependency passed via arguments
function(_bbs_defer_target_import target)
    bbs_load_conan_build_info()

    foreach(dep ${ARGN})
        if (NOT dep OR TARGET ${dep})
            continue()
        endif()

        if(NOT WIN32)
            bbs_import_pkgconfig_targets(${dep})

            if (TARGET ${dep})
                continue()
            endif()
        endif()

        bbs_import_conan_target(${dep})

        if (TARGET ${dep})
            continue()
        endif()

        bbs_import_cmake_config(${dep})

        if (TARGET ${dep})
            continue()
        endif()

        bbs_import_raw_library(${dep})

        if (TARGET ${dep})
            continue()
        endif()


        message(WARNING "Unresolved external dependency: ${dep}")
    endforeach()
endfunction()

#[[.rst:
.. command:: bbs_import_target_dependencies

  Import dependencies of the target
#]]

function(bbs_import_target_dependencies target)
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

#[[.rst:
.. command:: bbs_configure_target_tests

  Configure tests from the specified sources and
  add the target as their main build dependency.
#]]
function(bbs_configure_target_tests target)
    cmake_parse_arguments(""
                          ""
                          ""
                          "TEST_SOURCES;GTEST_SOURCES;TEST_DEPS;LABELS"
                          ${ARGN})
    bbs_assert_no_unparsed_args("")

    if (_TEST_SOURCES)
        bbs_add_component_tests(${target}
                                TEST_SOURCES  ${_TEST_SOURCES}
                                TEST_DEPS     ${_TEST_DEPS}
                                LABELS        ${_LABELS})
        set(${target}_TEST_TARGETS "${${target}_TEST_TARGETS}" PARENT_SCOPE)
    endif()
    if (_GTEST_SOURCES)
        bbs_add_component_gtests(${target}
                                 GTEST_SOURCES ${_GTEST_SOURCES}
                                 TEST_DEPS     ${_TEST_DEPS}
                                 LABELS        ${_LABELS})
        set(${target}_TEST_TARGETS "${${target}_TEST_TARGETS}" PARENT_SCOPE)
    endif()
endfunction()

#[[.rst:
.. command:: bbs_install_target_headers

  Generate installation command for target headers.
#]]
function (bbs_install_target_headers target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          "")
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    set(_install_include_dir "include") # the default.

    set(_install_interface_found FALSE)

    get_property(_target_include_install_path
                 TARGET ${target}
                 PROPERTY INCLUDES_INSTALL_PATH)

    if (_target_include_install_path)
        set(_install_interface_found TRUE)
        set(_install_include_dir ${_target_include_install_path})
    else()
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
    endif()

    if(NOT _install_interface_found)
        set_property(TARGET ${target}
                     APPEND PROPERTY INTERFACE_INCLUDE_DIRECTORIES
                     "$<INSTALL_INTERFACE:include>")
    endif()

    install(FILES ${${target}_INCLUDE_FILES}
            DESTINATION ${_install_include_dir}
            COMPONENT ${_COMPONENT}-headers)

    install(FILES ${${target}_INCLUDE_FILES}
            DESTINATION ${_install_include_dir}
            COMPONENT ${_COMPONENT}-all)
endfunction()

#.rst:
# .. command:: bbs_install_target
#
# Generate installation command for target.
function (bbs_install_target target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          "")
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    # default the component to the target name normalized as a dpkg name
    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    get_target_property(_target_type ${target} TYPE)
    if (   _target_type STREQUAL "STATIC_LIBRARY"
        OR _target_type STREQUAL "SHARED_LIBRARY"
        OR _target_type STREQUAL "INTERFACE_LIBRARY")

        foreach(p ${${uor_name}_PACKAGES})
            if (TARGET ${p}-iface)
                install(TARGETS ${p}-iface
                        EXPORT  ${uor_name}Targets)
            endif()
        endforeach()

        install(TARGETS ${target}
                EXPORT  ${uor_name}Targets)
        install(EXPORT  ${uor_name}Targets
                DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${uor_name}
                COMPONENT ${_COMPONENT})

        install(TARGETS ${target}
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT ${_COMPONENT})
        install(TARGETS ${target}
                ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
                COMPONENT ${_COMPONENT}-all)

        # generate/install <Package>Config.cmake
        # Note template uses uor_name and uor_deps variables
        include(CMakePackageConfigHelpers)

        set(uor_deps ${${target}_DEPENDS})
        configure_package_config_file(
            ${BBS_UOR_CONFIG_IN}
            ${CMAKE_CURRENT_BINARY_DIR}/${uor_name}Config.cmake
            INSTALL_DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${uor_name})
        install(FILES  ${CMAKE_CURRENT_BINARY_DIR}/${uor_name}Config.cmake
                DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/${uor_name}
                COMPONENT ${_COMPONENT})

        bbs_install_target_headers(${target})

    elseif (_target_type STREQUAL "EXECUTABLE")
        install(
            TARGETS ${target}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            COMPONENT ${_COMPONENT})
        install(
            TARGETS ${target}
            RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
            COMPONENT ${_COMPONENT}-all)
    endif()
endfunction()

#[[.rst:
.. command:: bbs_emit_pkg_config

  Emit package config for the target
#]]
function (bbs_emit_pkg_config target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          "")
    bbs_assert_no_unparsed_args("")

    get_target_property(uor_name ${target} NAME)

    # default the component to the target name normalized as a dpkg name
    if (NOT _COMPONENT)
        string(REPLACE "_" "-" _COMPONENT ${uor_name})
    endif()

    bbs_emit_pkgconfig_file(TARGET ${target}
                            PREFIX "${CMAKE_INSTALL_PREFIX}"
                            VERSION "${BB_BUILDID_PKG_VERSION}" # todo: add real version
                            COMPONENT ${_COMPONENT})
endfunction()

#.rst:
# .. command:: bbs_emit_bde_metadata
#
# Emit bde metadata for the target.
function (bbs_emit_bde_metadata target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "COMPONENT"
                          "")
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
        gen_bde_metadata(TARGET ${target}
                         INSTALL_COMPONENT "${_COMPONENT}-all")
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
# .. command:: bbs_check_cycles_target
#
# Generate custom target to check uor cycles.
function (bbs_emit_check_cycles target)
    if(CHECK_CYCLES)
        get_property(cmd_wrapper GLOBAL PROPERTY BBS_CMD_WRAPPER)

        get_target_property(uor_name ${target} NAME)

        LIST(APPEND src ${${target}_INCLUDE_FILES})
        LIST(APPEND src ${${target}_SOURCE_FILES})
        LIST(APPEND src ${${target}_TEST_SOURCES})
        add_custom_target(${uor_name}.check_cycles
            COMMAND   ${cmd_wrapper} "${Python3_EXECUTABLE}" "${CHECK_CYCLES}" ${src}
        )

        if (NOT TARGET check_cycles)
            add_custom_target(check_cycles)
        endif()
        add_dependencies(check_cycles ${uor_name}.check_cycles)
    endif()
endfunction()

#.rst:
# .. command:: bbs_setup_target_uor
#
#  Parse metadata and populate UOR target.
#  This command is a bbs equivalent of configure_bb_target().
#
#  * CUSTOM_PACKAGES  list of packages that provide their custom CML
#  * PRIVATE_PACKAGES  list of packages that provide implementation details
#    headers for those packages should not be installed.
function(bbs_setup_target_uor target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          "SKIP_TESTS;NO_GEN_BDE_METADATA;NO_EMIT_PKG_CONFIG_FILE"
                          "SOURCE_DIR"
                          "CUSTOM_PACKAGES;PRIVATE_PACKAGES")
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
                          CUSTOM_PACKAGES "${_CUSTOM_PACKAGES}"
                          PRIVATE_PACKAGES "${_PRIVATE_PACKAGES}")
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

        # Each package in the groups is an individual OBJECT or INTERFACE library
        if (${uor_name}_PACKAGES)
            foreach(pkg ${${uor_name}_PACKAGES})
                # Check if this is customized package
                if (${pkg} IN_LIST _CUSTOM_PACKAGES)
                    message(TRACE "Processing customized ${pkg}")
                    add_subdirectory(${_SOURCE_DIR}/${pkg})

                    # Custom package must "export" and interface library that can be ether
                    # OBJECT library target (if it contains compilable sources) or INTERFACE
                    # library target if it is header-only package. All we do here is to add
                    # group dependencies to the package interface and add it as a dependency
                    # to the group.
                    if (TARGET ${pkg}-iface)
                        get_target_property(_pkg_type ${pkg}-iface TYPE)
                        if (_pkg_type STREQUAL "OBJECT_LIBRARY")
                            target_link_libraries(${pkg}-iface PRIVATE ${${uor_name}_PCDEPS})
                            target_link_libraries(${target} PUBLIC ${pkg}-iface)
                        else()
                            target_link_libraries(${target} INTERFACE ${pkg}-iface)
                        endif()

                    else()
                        message(FATAL_ERROR "Custom package should produce an interface library")
                    endif()
                else()
                    message(TRACE "Processing ${pkg}")

                    # If the library contains only header files, we will create an INTERFACE
                    # library; otherwise, we will create an OBJECT library
                    if (${pkg}_SOURCE_FILES)
                        message(TRACE "Adding OBJECT library ${pkg}-iface")
                        add_library(${pkg}-iface
                                    OBJECT ${${pkg}_SOURCE_FILES} ${${pkg}_INCLUDE_FILES})
                        set_target_properties(${pkg}-iface PROPERTIES LINKER_LANGUAGE CXX)
                        bbs_add_target_include_dirs(${pkg}-iface PUBLIC ${${pkg}_INCLUDE_DIRS})

                        bbs_add_target_bde_flags(${pkg}-iface PRIVATE)
                        bbs_add_target_thread_flags(${pkg}-iface PRIVATE)

                        target_link_libraries(${pkg}-iface PRIVATE ${${uor_name}_PCDEPS})

                        # Adding library for the package as real static library
                        add_library(${pkg} STATIC)
                        target_link_libraries(${pkg} PUBLIC ${pkg}-iface)

                        # Important: link with DEPENDS and not PCDEPS for packages
                        # in a groups. For groups with underscores (z_bae) we do
                        # not want to use pc-fied name like z-baelu.
                        # For the group's dependencies (external) we use PCDEPS.
                        # This is different from a standalone packages that can
                        # have only external PC dependencies.
                        foreach(p ${${pkg}_DEPENDS})
                            target_link_libraries(${pkg}-iface PUBLIC ${p}-iface)
                            target_link_libraries(${pkg} INTERFACE ${p})
                        endforeach()

                        target_link_libraries(${target} PUBLIC ${pkg}-iface)
                    else()
                        message(TRACE "Adding INTERFACE library ${pkg}-iface")
                        add_library(${pkg}-iface INTERFACE ${${pkg}_INCLUDE_FILES})
                        bbs_add_target_include_dirs(${pkg}-iface INTERFACE ${${pkg}_INCLUDE_DIRS})

                        # Adding library for the package as an interface library
                        add_library(${pkg} INTERFACE)
                        target_link_libraries(${pkg} INTERFACE ${pkg}-iface)

                        foreach(p ${${pkg}_DEPENDS})
                            target_link_libraries(${pkg}-iface INTERFACE ${p}-iface)
                            target_link_libraries(${pkg} INTERFACE ${p})
                        endforeach()
                        target_link_libraries(${target} INTERFACE ${pkg}-iface)
                    endif()

                    # Generating cpp03 headers, implementation and test files if any
                    bbs_generate_cpp03_sources("${${pkg}_INCLUDE_FILES}")
                    bbs_generate_cpp03_sources("${${pkg}_SOURCE_FILES}")
                    bbs_generate_cpp03_sources("${${pkg}_TEST_SOURCES}")

                    if (NOT _SKIP_TESTS)
                        bbs_configure_target_tests(${pkg}
                                                   TEST_SOURCES   ${${pkg}_TEST_SOURCES}
                                                   GTEST_SOURCES  ${${pkg}_GTEST_SOURCES}
                                                   TEST_DEPS      ${${pkg}_DEPENDS}
                                                                  ${${pkg}_TEST_DEPENDS}
                                                                  ${${uor_name}_PCDEPS}
                                                                  ${${uor_name}_TEST_PCDEPS}
                                                   LABELS         "all" ${target} ${pkg})
                    endif()
                endif()
            endforeach()

            set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)
            set_target_properties(${target} PROPERTIES BB_UOR_IS_GROUP TRUE)

            target_link_libraries(${target} PUBLIC ${${uor_name}_PCDEPS})
            bbs_add_target_bde_flags(${target} PRIVATE)
            bbs_add_target_thread_flags(${target} PRIVATE)

            bbs_import_target_dependencies(${target} ${${uor_name}_PCDEPS})

            if (NOT _SKIP_TESTS)
                set(import_test_deps ON)
                set(import_gtest_deps ON)
                foreach(pkg ${${uor_name}_PACKAGES})
                    if (${pkg}_TEST_TARGETS)
                        if (NOT TARGET ${target}.t)
                            add_custom_target(${target}.t)
                        endif()
                        add_dependencies(${target}.t ${${pkg}_TEST_TARGETS})
                        if (import_test_deps)
                            # Import UOR test dependencies only once and only if we have at least
                            # one generated test target
                            bbs_import_target_dependencies(${target} ${${uor_name}_TEST_PCDEPS})
                            set(import_test_deps OFF)
                        endif()
                        if (${pkg}_GTEST_SOURCES)
                            if (import_gtest_deps)
                                # Import UOR test dependencies only once and only if we have gtests
                                bbs_import_target_dependencies(${target} gtest)
                                set(import_gtest_deps OFF)
                            endif()
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

            target_link_libraries(${target} PUBLIC ${${uor_name}_PCDEPS})
            bbs_add_target_bde_flags(${target} PRIVATE)
            bbs_add_target_thread_flags(${target} PRIVATE)

            bbs_import_target_dependencies(${target} ${${uor_name}_PCDEPS})
            if (NOT _SKIP_TESTS)
                bbs_configure_target_tests(${target}
                                           TEST_SOURCES   ${${uor_name}_TEST_SOURCES}
                                           GTEST_SOURCES  ${${uor_name}_GTEST_SOURCES}
                                           TEST_DEPS      ${${uor_name}_PCDEPS}
                                                          ${${uor_name}_TEST_PCDEPS}
                                           LABELS         "all" ${target})
                if (${target}_TEST_TARGETS)
                    bbs_import_target_dependencies(${target} ${${uor_name}_TEST_PCDEPS})
                endif()
                if (${target}_GTEST_SOURCES)
                    bbs_import_target_dependencies(${target} gtest)
                endif()
            endif()
        endif()

        # Generating .pc file. This will be a noop in non-Bloomberg build env (TODO:fix)
        if (NOT _NO_EMIT_PKG_CONFIG_FILE)
            bbs_emit_pkg_config(${target})
        endif()

        # Generate/install bdemetadata files. This will be a noop in non-Bloomberg build env.
        if (NOT _NO_GEN_BDE_METADATA)
            bbs_emit_bde_metadata(${target})
        endif()

        # Create an alias library with the pkgconfig name, if it is different from
        # the uor name and such a target doesn't exist yet.
        bbs_uor_to_pc_name(${uor_name} pc_name)
        if (NOT TARGET ${pc_name} AND NOT uor_name STREQUAL pc_name)
            add_library(${pc_name} ALIAS ${target})
        endif()

        # Create a custom target for checking UOR dependency cycles
        bbs_emit_check_cycles(${target})

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

            bbs_add_target_bde_flags(${lib_target} PUBLIC)
            bbs_add_target_thread_flags(${lib_target} PUBLIC)

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

            bbs_add_target_bde_flags(${lib_target} INTERFACE)
            bbs_add_target_thread_flags(${lib_target} INTERFACE)

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

        # Create an alias for the application library to be used as an external
        # pkg-config compatible dependency
        bbs_uor_to_pc_name(${lib_target} pc_name)
        if (NOT TARGET ${pc_name} AND NOT ${lib_target} STREQUAL pc_name)
            add_library(${pc_name} ALIAS ${lib_target})
        endif()

        bbs_import_target_dependencies(${lib_target} "${${uor_name}_PCDEPS}")

        # Build the main source and link against the private library
        set_target_properties(${target} PROPERTIES LINKER_LANGUAGE CXX)
        target_sources(${target} PRIVATE ${${uor_name}_MAIN_SOURCE})
        target_link_libraries(${target} PRIVATE ${lib_target})

        # Set up tests and link against the private library
        if (NOT _SKIP_TESTS)
            bbs_configure_target_tests(${lib_target}
                                       TEST_SOURCES   ${${uor_name}_TEST_SOURCES}
                                       GTEST_SOURCES  ${${uor_name}_GTEST_SOURCES}
                                       TEST_DEPS      ${${uor_name}_PCDEPS}
                                                      ${${uor_name}_TEST_PCDEPS}
                                       LABELS         "all" ${target})
            if (TARGET ${lib_target}.t)
                if (NOT TARGET ${target}.t)
                    add_custom_target(${target}.t)
                endif()
                add_dependencies(${target}.t ${lib_target}.t)
            endif()

            if (${lib_target}_TEST_TARGETS)
                bbs_import_target_dependencies(${lib_target} ${${uor_name}_TEST_PCDEPS})
            endif()
        endif()
    else()
        # Not a library or an application
        message( FATAL_ERROR "Invalid target type for BDE target: ${_TARGET_TYPE}")
    endif()

    # Installation
    if (_target_type STREQUAL "STATIC_LIBRARY" OR
        _target_type STREQUAL "EXECUTABLE")
        bbs_install_target(${target})
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

function(bbs_setup_header_only_pkg2 target pkg)
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

    list(APPEND ${target}_INCLUDE_FILES ${${pkg}_INCLUDE_FILES})
    set(${target}_INCLUDE_FILES  ${${target}_INCLUDE_FILES}  PARENT_SCOPE)
endfunction()
