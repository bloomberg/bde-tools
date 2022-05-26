include(bde_include_guard)
bde_include_guard()

include(bde_struct)
include(bde_utils)
include(bde_runtest)
include(bde_log)

bde_register_struct_type(
    BDE_COMPONENT_TYPE
        SOURCE
        HEADER
        TEST_TARGET
)

find_package(Python3 3.8...<4 REQUIRED)

# Find perl, but it's ok if it's missing
find_package(Perl)

# Find sim_cpp11_features.pl.  It's ok if it's missing, as it will be during
# dpkg builds.
if(PERL_FOUND AND NOT MSVC)
    bde_log(VERBOSE
            "Found perl version ${PERL_VERSION_STRING} at ${PERL_EXECUTABLE}")
    find_program(SIM_CPP11
                 "sim_cpp11_features.pl"
                 PATHS ${CMAKE_MODULE_PATH}/../contrib/sim_cpp11
                 )
    if(SIM_CPP11)
        bde_log(QUIET "Found sim_cpp11_features.pl in ${SIM_CPP11}")

        option(BDE_CPP11_VERIFY_NO_CHANGE "Verify that sim_cpp11_features generates no changes" OFF)
    endif()
else()
    bde_log(QUIET "Perl not found and/or on Windows - sim_cpp11_features.pl disabled")
endif()

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

function(bde_component_generate_cpp03 srcFile)
    if(SIM_CPP11)
        if(${srcFile} MATCHES "_cpp03\.")
            set(cpp11VerifyOption "")
            set(cpp11Operation "generation")

            if(BDE_CPP11_VERIFY_NO_CHANGE)
                set(cpp11VerifyOption "--verify-no-change")
                set(cpp11Operation "validation")
            endif()

            string(REPLACE "_cpp03." "." cpp11SrcFile ${srcFile})
            bde_log(VERY_VERBOSE "sim_cpp11 ${cpp11Operation}: ${cpp11SrcFile} -> ${srcFile}")

            if (BDE_USE_WAFSTYLEOUT)
                get_property(wafstyleout GLOBAL PROPERTY WAFSTYLEOUT_PATH)

                add_custom_command(
                    OUTPUT    "${srcFile}"
                    COMMAND   "${Python3_EXECUTABLE}" "${wafstyleout}" "${PERL_EXECUTABLE}" "${SIM_CPP11}" ${cpp11VerifyOption} "${cpp11SrcFile}"
                    DEPENDS   "${cpp11SrcFile}"
                    )
            else()
                add_custom_command(
                    OUTPUT    "${srcFile}"
                    COMMAND   "${PERL_EXECUTABLE}" "${SIM_CPP11}" ${cpp11VerifyOption} "${cpp11SrcFile}"
                    DEPENDS   "${cpp11SrcFile}"
                    )
            endif()
        endif()
    endif()
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

    bde_component_generate_cpp03("${source}")
    bde_component_generate_cpp03("${header}")
endfunction()

function(bde_component_find_tests component rootDir)
    bde_assert_no_extra_args()

    bde_struct_get_field(componentName ${component} NAME)
    set(baseName "${rootDir}/${componentName}")

    # Test driver
    if (NOT BDE_TEST_REGEX OR ${componentName} MATCHES "${BDE_TEST_REGEX}")
        bde_utils_glob_files(tests ${baseName} ".t.cpp;.*.t.cpp;.t.c;.*.t.c")
        foreach(test IN LISTS tests)
            get_filename_component(testName ${test} NAME_WLE)
            bde_add_test_executable(${testName} ${testName} ${test})
            bde_struct_append_field(${component} TEST_TARGET ${testName})
            bde_component_generate_cpp03("${test}")
        endforeach()
        bde_struct_get_field(componentTestTargets ${component} TEST_TARGET)
        bde_create_test_metatarget(componentT "${componentTestTargets}" ${componentName})
    endif()
endfunction()
