include_guard()

# On windows we will invoke the python script directly
# On unix - the shell wrapper will find the interperter and 
# invoke the implementation file.
find_file(BBS_RUNTEST bbs_runtest.py
          PATHS "${CMAKE_CURRENT_LIST_DIR}/scripts")

if (NOT BBS_RUNTEST)
    message(FATAL_ERROR "Failed to find bbs_runtest")
endif()

find_package(Python3 3.6 REQUIRED)
set(BBS_RUNTEST ${Python3_EXECUTABLE} ${BBS_RUNTEST})

if (BBS_USE_WAFSTYLEOUT)
    get_property(cmd_wrapper GLOBAL PROPERTY BBS_CMD_WRAPPER)
    set(BBS_RUNTEST ${cmd_wrapper} ${BBS_RUNTEST})
endif()

# bbs_add_bde_style_test(target
#                        [ WORKING_DIRECTORY     dir       ]
#                        [ TEST_VERBOSITY        verbosity ]
#                        [ EXTRA_ARGS            args ...  ]
#                        [ LABELS                prop value ... ]
#                       )
# adds the target as a test using the bde test driver script
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

# bbs_add_component_tests(target SOURCES source1.t.cpp [source2.t.cpp ...]
#                         [ WORKING_DIRECTORY      dir            ]
#                         [ TEST_VERBOSITY         verbosity      ]
#                         [ EXTRA_ARGS             test_arg   ... ]
#                         [ PROPERTIES             prop value ... ]
#                         [ TEST_DEPS              lib1 lib2  ... ]
#                         [ TEST_TARGET_PROPERTIES prop value ... ]
#                        )
function(bbs_add_component_tests target)
    cmake_parse_arguments(PARSE_ARGV 1
                          ""
                          ""
                          "TEST_VERBOSITY;TEST_REGEX"
                          "EXTRA_ARGS;LABELS;SOURCES;TEST_DEPS")
    bbs_assert_no_unparsed_args("")

    if (NOT _SOURCES)
        message(FATAL_ERROR "No sources for the test ${target}")
    endif()

    set(test_targets)

    foreach(test_src ${_SOURCES})
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

        target_link_libraries(${test_target_name}.t PUBLIC ${target} ${_TEST_DEPS})

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

    set(${target}_TEST_TARGETS "${test_targets}" PARENT_SCOPE)
endfunction()
