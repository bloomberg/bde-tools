if(BDE_COMPONENT_INCLUDED)
    return()
endif()
set(BDE_COMPONENT_INCLUDED true)

include(bde_struct)
include(bde_utils)

set(
    BDE_COMPONENT_TYPE
        SOURCE
        HEADER
        TEST_TARGET
)

# :: add_test_executable ::
# This function adds a target for test identified by 'name' and with the source
# file in 'src'. The make/test target is 'name.t'.
function(bde_add_test_executable retTestName name src)
    bde_assert_no_extra_args()

    set(testName ${name}.t)
    add_executable(${testName} EXCLUDE_FROM_ALL ${src})
    if (CMAKE_HOST_UNIX)
        set(testCommand "bde_runtest.py" "$<TARGET_FILE:${testName}>")
    else()
        set(testCommand
            ${CMAKE_COMMAND} "-DTEST_PROG=$<TARGET_FILE:${testName}>"
            "-P" "${CMAKE_MODULE_PATH}/bde_run_test.cmake"
        )
    endif()
    add_test(NAME ${testName} COMMAND ${testCommand})
    bde_append_test_labels(${testName} ${name} ${testName})

    bde_return(${testName})
endfunction()

function(bde_process_component retComponent rootDir componentName)
    bde_assert_no_extra_args()

    bde_struct_create(BDE_COMPONENT_TYPE ${componentName})

    # Header
    set(baseName "${rootDir}/${componentName}")
    bde_utils_find_file_extension(header ${baseName} ".h")
    if(NOT header)
        message(FATAL_ERROR "Header for ${componentName} not found.")
    endif()
    bde_struct_set_field(${componentName} HEADER ${header})

    # Source
    bde_utils_find_file_extension(source ${baseName} ".c;.cpp")
    if(NOT source)
        message(FATAL_ERROR "Source for ${componentName} not found.")
    endif()
    bde_struct_set_field(${componentName} SOURCE ${source})

    # Test driver
    bde_utils_find_file_extension(test ${baseName} ".t.c;.t.cpp")
    if(test)
        bde_add_test_executable(testName ${componentName} ${test})
        bde_struct_set_field(${componentName} TEST_TARGET "${testName}")
    else()
        message(WARNING "Test driver for ${componentName} not found.")
    endif()

    bde_return(${componentName})
endfunction()
