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
function(bde_add_test_executable retTestName testName src)
    bde_assert_no_extra_args()
    get_bde_test_runner(cmd)

    add_executable(${testName} EXCLUDE_FROM_ALL ${src})
    add_test(
        NAME ${testName}
        COMMAND ${cmd} $<TARGET_FILE:${testName}>
    )

    # Adding 2 labels - without .t and without .*.t 
    get_filename_component(labelName ${testName} NAME_WLE)
    bde_append_test_labels(${testName} ${labelName})

    get_filename_component(labelName ${labelName} NAME_WLE)
    bde_append_test_labels(${testName} ${labelName})

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

function(bde_component_find_tests component rootDir)
    bde_assert_no_extra_args()

    bde_struct_get_field(componentName ${component} NAME)
    set(baseName "${rootDir}/${componentName}")

    # Test driver
    if (NOT BDE_TEST_REGEX OR ${baseName} MATCHES "${BDE_TEST_REGEX}")
        bde_utils_glob_files(tests ${baseName} ".t.cpp;.*.t.cpp;.t.c;.*.t.c")
        foreach(test IN LISTS tests)
            get_filename_component(testName ${test} NAME_WLE)
            bde_add_test_executable(${testName} ${testName} ${test})
            bde_struct_append_field(${component} TEST_TARGET ${testName})
        endforeach()
        bde_struct_get_field(componentTestTargets ${component} TEST_TARGET)
        bde_create_test_metatarget(componentT "${componentTestTargets}" ${componentName})
    endif()
endfunction()
