# No include guard - may be reloaded

bde_prefixed_override(gtest component_find_tests)
function(gtest_component_find_tests component rootDir)
    component_find_tests_base(gtest_component_find_tests ${ARGV})

    bde_struct_get_field(componentName ${component} NAME)
    bde_utils_find_file_extension(test "${rootDir}/${componentName}" ".g.cpp")

    bde_struct_get_field(testTarget ${component} TEST_TARGET)
    if(test)
        if(testTarget)
            message(
                WARNING
                "Found GTest test driver, but test target ${testTarget} is \
                 already created for component ${componentName}."
            )
        else()
            gtest_add_test_executable(testName ${componentName} ${test})
            bde_struct_set_field(${component} TEST_TARGET "${testName}")
        endif()
    endif()
endfunction()

function(gtest_add_test_executable retTestName name src)
    bde_assert_no_extra_args()

    set(testName ${name}.t)
    add_executable(${testName} EXCLUDE_FROM_ALL ${src})
    add_test(
        NAME ${testName}
        COMMAND $<TARGET_FILE:${testName}>
    )
    bde_append_test_labels(${testName} ${name})

    bde_return(${testName})
endfunction()
