include_guard()

#[[.rst:
BdeTestDriverUtils
------------------
This module provide a set of function to generate BDE tests
#]]

# On windows we will invoke the python script directly
# On unix - the shell wrapper will find the interperter and
# invoke the implementation file.
find_package(Python3 3.6 REQUIRED)

find_file(BBS_RUNTEST bbs_runtest.py
          PATHS "${CMAKE_CURRENT_LIST_DIR}/scripts")

if (NOT BBS_RUNTEST)
    message(FATAL_ERROR "Failed to find bbs_runtest")
endif()

set(BBS_RUNTEST ${Python3_EXECUTABLE} ${BBS_RUNTEST})

if (BBS_USE_WAFSTYLEOUT)
    get_property(cmd_wrapper GLOBAL PROPERTY BBS_CMD_WRAPPER)
    set(BBS_RUNTEST ${cmd_wrapper} ${BBS_RUNTEST})
endif()

find_file(BBS_SPLIT_TEST bde_xt_cpp_splitter.py
          PATHS "${CMAKE_CURRENT_LIST_DIR}/scripts/bde_xt_cpp_splitter")

if (BBS_SPLIT_TEST)
    set(BBS_SPLIT_TEST ${Python3_EXECUTABLE} ${BBS_SPLIT_TEST})

    if (BBS_USE_WAFSTYLEOUT)
        get_property(cmd_wrapper GLOBAL PROPERTY BBS_CMD_WRAPPER)
        set(BBS_SPLIT_TEST ${cmd_wrapper} ${BBS_SPLIT_TEST})
    endif()
else()
    message(FATAL_ERROR "Failed to find test split generator")
endif()

#[[.rst:
.. command:: bbs_add_bde_style_test

Add the [executable] ``target`` as a BDE test and create ctest labels for it.

.. code-block:: cmake

   bbs_add_bde_style_test(target
                          [ WORKING_DIRECTORY     dir       ]
                          [ TEST_VERBOSITY        verbosity ]
                          [ EXTRA_ARGS            args ...  ]
                          [ LABELS                prop value ... ]
                         )

#]]

function(bbs_add_bde_style_test target)
    cmake_parse_arguments(""
                          ""
                          "WORKING_DIRECTORY;TEST_VERBOSITY"
                          "EXTRA_ARGS;LABELS"
                          ${ARGN})
    bbs_assert_no_unparsed_args("")

    if (NOT _WORKING_DIRECTORY)
        set(_WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}")
    endif()

    if (NOT _TEST_VERBOSITY)
        set(_TEST_VERBOSITY 0)
    endif()

    add_test(NAME ${target}
             COMMAND ${BBS_RUNTEST} -v ${_TEST_VERBOSITY} ${_EXTRA_ARGS} $<TARGET_FILE:${target}>
             WORKING_DIRECTORY ${_WORKING_DIRECTORY})

    foreach (label ${_LABELS})
        set_property(TEST ${target} APPEND PROPERTY LABELS ${label} "${label}.t")
    endforeach()
endfunction()

#[[.rst:
.. command:: bbs_add_component_tests

Generate build targets [executables] for the specified ``TEST_SOURCES``, add them as
BDE tests and generate necessary build dependencies and test labels.

.. code-block:: cmake

   bbs_add_component_tests(target
                           TEST_SOURCES source1.t.cpp [source2.t.cpp ...]
                           SPLIT_SOURCES source3.xt.cpp [source4.xt.cpp]
                           [ WORKING_DIRECTORY      dir            ]
                           [ TEST_VERBOSITY         verbosity      ]
                           [ EXTRA_ARGS             test_arg   ... ]
                           [ PROPERTIES             prop value ... ]
                           [ TEST_DEPS              lib1 lib2  ... ]
                           [ TEST_TARGET_PROPERTIES prop value ... ]
                          )

#]]
function(bbs_add_component_tests target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "TEST_VERBOSITY;TEST_REGEX"
                          "EXTRA_ARGS;LABELS;TEST_SOURCES;SPLIT_SOURCES;TEST_DEPS")
    bbs_assert_no_unparsed_args("")

    if (NOT _TEST_SOURCES AND NOT _SPLIT_SOURCES)
        message(FATAL_ERROR "No sources for the test ${target}")
    endif()

    # This function can be called few times for BDE tests, gtest and split tests.
    # We want to "continue" to populate the list set by previous calls.
    set(test_targets ${${target}_TEST_TARGETS})

    foreach(test_src ${_TEST_SOURCES})
        # Stripping all extentions from the test source ( including numbers
        # from the numbered tests )
        get_filename_component(test_name ${test_src} NAME_WE)
        if (BDE_TEST_REGEX AND NOT ${test_name} MATCHES "${BDE_TEST_REGEX}")
            # Generate test target only for matching test regex, if any.
            continue()
        endif()

        # Stripping last 2 extentions from the test source (.t.cpp)
        get_filename_component(test_target_name ${test_src} NAME_WLE)
        get_filename_component(test_target_name ${test_target_name} NAME_WLE)
        add_executable(${test_target_name}.t EXCLUDE_FROM_ALL ${test_src})
        set_target_properties(
            ${test_target_name}.t
            PROPERTIES
            RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests")
        add_custom_command(TARGET ${test_target_name}.t
            POST_BUILD
            COMMAND
            ${CMAKE_COMMAND} -E create_hardlink
            "$<TARGET_FILE:${test_target_name}.t>"
            "$<TARGET_FILE_DIR:${test_target_name}.t>/${test_target_name}${CMAKE_EXECUTABLE_SUFFIX}"
        )

        # Explicitely adding flags here because we do not want those flags to be
        # PUBLIC for standalone libraries.
        bbs_add_target_bde_flags(${test_target_name}.t PRIVATE)
        bbs_add_target_thread_flags(${test_target_name}.t PRIVATE)

        target_link_libraries(${test_target_name}.t PUBLIC ${target} ${_TEST_DEPS})

        if (BDE_BUILD_TARGET_FUZZ)
            target_link_libraries(${test_target_name}.t PRIVATE "-fsanitize=fuzzer")
        endif()

        set(test_src_labels ${test_name})
        if (NOT test_name STREQUAL test_target_name)
            list(APPEND test_src_labels ${test_target_name})
        endif()

        bbs_add_bde_style_test(${test_target_name}.t
                                   WORKING_DIRECTORY "${_WORKING_DIRECTORY}"
                                   TEST_VERBOSITY    "${_TEST_VERBOSITY}"
                                   EXTRA_ARGS        "${_EXTRA_ARGS}"
                                   LABELS            "${_LABELS}"
                                                     "${test_src_labels}")

        # Adding package test target
        if (NOT TARGET ${target}.t)
            add_custom_target(${target}.t)
        endif()

        if (NOT TARGET all.t)
            add_custom_target(all.t)
        endif()

        add_dependencies(${target}.t ${test_target_name}.t)
        add_dependencies(all.t ${test_target_name}.t)

        list(APPEND test_targets ${test_target_name}.t)

        # Adding top test target for numbered ( aka bslstl_vector for bslstl_vector.[0123].t )
        # True for numbered tests
        if (NOT test_name STREQUAL test_target_name)
            if (NOT TARGET ${test_name}.t)
                add_custom_target(${test_name}.t)
            endif()

            message(TRACE "Adding ${test_name}.t -> ${test_target_name}.t")
            add_dependencies(${test_name}.t ${test_target_name}.t)
        endif()
    endforeach()

    set(split_cpp03_test_srcs ${_SPLIT_SOURCES})
    list(FILTER split_cpp03_test_srcs INCLUDE REGEX "_cpp03\.")

    foreach(test_src ${_SPLIT_SOURCES})
        # Stripping all extentions from the test source ( including numbers
        # from the numbered tests )
        get_filename_component(test_name ${test_src} NAME_WE)
        if (BDE_TEST_REGEX AND NOT ${test_name} MATCHES "${BDE_TEST_REGEX}")
            # Generate test target only for matching test regex, if any.
            continue()
        endif()

        # Stripping last 2 extentions from the test source (.xt.cpp)
        get_filename_component(test_target_name ${test_src} NAME_WLE)
        get_filename_component(test_target_name ${test_target_name} NAME_WLE)

        # Check if _cpp03 version of this test exists
        if (${split_cpp03_test_srcs} MATCHES "${test_target_name}_cpp03\.xt\.cpp")
            set(test_has_cpp03 TRUE)
        else()
            set(test_has_cpp03 FALSE)
        endif()

        # Creating output folder
        set(td_output_dir "${CMAKE_CURRENT_BINARY_DIR}/${test_name}_split")

        # remove temp file if it exists so that it will only contain what we generate
        if(NOT EXISTS "${td_output_dir}")
            file(MAKE_DIRECTORY "${td_output_dir}")
        endif()

        set(stamp_file ${td_output_dir}/${test_name}.stamp)

        set(command ${BBS_SPLIT_TEST} -o ${td_output_dir} -s ${test_name}.stamp ${test_src})
        execute_process(
            COMMAND ${command}
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            COMMAND_ERROR_IS_FATAL ANY)

        file(STRINGS ${stamp_file} td_cpp_files)

        set(outputs ${stamp_file})
        foreach(split_test ${td_cpp_files})
            list(APPEND outputs ${td_output_dir}/${split_test})
        endforeach()

        if( ${CMAKE_VERSION} VERSION_GREATER_EQUAL 3.27.0)
            set(command_extra_flags DEPENDS_EXPLICIT_ONLY)
            set(configure_dependency ${stamp_file})
        else()
            set(command_extra_flags)
            set(configure_dependency ${test_src})
        endif()

        add_custom_command(
            OUTPUT ${outputs}
            COMMAND ${command}
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            MAIN_DEPENDENCY ${test_src}
            ${command_extra_flags})
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${configure_dependency})

        if("${td_cpp_files}" STREQUAL "")
            message(FATAL_ERROR "Test splitter generated no files")
        endif()

        # Adding package test target
        if (NOT TARGET ${test_name}.t)
            add_custom_target(${test_name}.t)
        endif()

        if (NOT TARGET ${target}.t)
            add_custom_target(${target}.t)
        endif()

        if (NOT TARGET all.t)
            add_custom_target(all.t)
        endif()

        # Processing individual tests and adding them to the target test
        foreach(split_test ${td_cpp_files})
            get_filename_component(split_target_name ${split_test} NAME_WLE)
            get_filename_component(split_target_name ${split_target_name} NAME_WLE)

            if (${test_name} MATCHES "_cpp03")
                # Add a custom target for dependency handling, but no executable for _cpp03 splits
                add_custom_target(${split_target_name}.t SOURCES ${td_output_dir}/${split_test})
            else()
                add_executable(${split_target_name}.t EXCLUDE_FROM_ALL ${td_output_dir}/${split_test})
                set_target_properties(
                    ${split_target_name}.t
                    PROPERTIES
                    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tests")

                bbs_add_target_bde_flags(${split_target_name}.t PRIVATE)
                bbs_add_target_thread_flags(${split_target_name}.t PRIVATE)

                target_link_libraries(${split_target_name}.t PUBLIC ${target} ${_TEST_DEPS})

                if (BDE_BUILD_TARGET_FUZZ)
                    target_link_libraries(${split_target_name}.t PRIVATE "-fsanitize=fuzzer")
                endif()

                bbs_add_bde_style_test(${split_target_name}.t
                                    WORKING_DIRECTORY "${_WORKING_DIRECTORY}"
                                    TEST_VERBOSITY    "${_TEST_VERBOSITY}"
                                    EXTRA_ARGS        "${_EXTRA_ARGS}"
                                    LABELS            "${_LABELS}"
                                                        "${test_name}")

                if (test_has_cpp03)
                    target_include_directories(${split_target_name}.t PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/${test_name}_cpp03_split")
                endif()
            endif()

            message(TRACE "Adding ${test_name}.t -> ${split_target_name}.t")
            add_dependencies(${test_name}.t ${split_target_name}.t)
        endforeach()

        add_dependencies(${target}.t ${test_name}.t)
        add_dependencies(all.t ${test_name}.t)

        list(APPEND test_targets ${test_name}.t)
    endforeach()

    set(${target}_TEST_TARGETS "${test_targets}" PARENT_SCOPE)
endfunction()
