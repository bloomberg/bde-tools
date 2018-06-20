include(bde_include_guard)
bde_include_guard()

include(bde_struct)
include(bde_utils)
include(bde_runtest)

bde_register_struct_type(
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
    get_bde_test_runner(cmd)

    set(testName ${name}.t)
    add_executable(${testName} EXCLUDE_FROM_ALL ${src})
    add_test(
        NAME ${testName}
        COMMAND ${cmd} $<TARGET_FILE:${testName}>
    )
    bde_append_test_labels(${testName} ${name})

    bde_return(${testName})
endfunction()

function(bde_component_initialize retComponent componentName)
    bde_assert_no_extra_args()

    bde_struct_create(
        component
        BDE_COMPONENT_TYPE
        NAME ${componentName}
    )

    bde_return(${component})
endfunction()

function(bde_component_find_sources component rootDir)
    bde_assert_no_extra_args()

    bde_struct_get_field(componentName ${component} NAME)
    set(baseName "${rootDir}/${componentName}")

    # Source
    bde_utils_find_file_extension(source ${baseName} ".cpp;.c")
    if(NOT source)
        message(FATAL_ERROR "Source for ${componentName} not found.")
    endif()
    bde_struct_set_field(${component} SOURCE "${source}")

    # Header
    bde_utils_find_file_extension(header ${baseName} ".h")
    if(NOT header)
        message(FATAL_ERROR "Header for ${componentName} not found.")
    endif()
    bde_struct_set_field(${component} HEADER "${header}")
endfunction()

function(bde_component_find_test component rootDir)
    bde_assert_no_extra_args()

    bde_struct_get_field(componentName ${component} NAME)
    set(baseName "${rootDir}/${componentName}")

    # Test driver
    bde_utils_find_file_extension(test ${baseName} ".t.cpp;.t.c")
    if(test)
        bde_add_test_executable(testName ${componentName} ${test})
        bde_struct_set_field(${component} TEST_TARGET "${testName}")
    endif()
endfunction()