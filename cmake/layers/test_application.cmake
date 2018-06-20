bde_prefixed_override(testApp application_initialize)
function(testApp_application_initialize retUor appName)
    bde_assert_no_extra_args()

    # Create a custom output target for this application
    add_executable(${appName} EXCLUDE_FROM_ALL "")
    add_test(NAME ${appName} COMMAND $<TARGET_FILE:${appName}>)
    bde_append_test_labels(${appName} ${appName})

    bde_uor_initialize(uor ${appName})

    bde_return(${uor})
endfunction()

bde_prefixed_override(testApp application_install)
function(testApp_application_install)
    # Do nothing
endfunction()
