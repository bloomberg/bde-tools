## bde_test_drivers.cmake
## ----------------------
#  This CMake module exposes a set of functions providing support for BDE style
#  test drivers where the test code for the component is in the same directory
#  as the production code, and each test file produces a single test executable.
#
## OVERVIEW
## --------
# o bde_project_find_testdriver.............: Finds the test driver source for a
#                                             component
#
# o add_test_executable.....................: Adds a test driver executable.
#
# o add_td_target...........................: Handles building a custom all.td
#                                             target.
#
# o bde_project_group_add_testdrivers.......: Finds and adds all the test drivers
#                                             for all the components in a Package
#                                             Group.
#
# o bde_project_standalone_add_testdrivers..: Finds and adds all the test drivers
#                                             for a Standalone Package.
#
# o bde_project_application_add_testdrivers.: Finds and adds all the test drivers
#                                             for an Application.
#
## ========================================================================= ##
if(BDE_TEST_DRIVERS_INCLUDED)
    return()
endif()
set(BDE_TEST_DRIVERS_INCLUDED true)

# :: bde_project_find_testdriver ::
# -----------------------------------------------------------------------------
# This functions looks for test drivers for 'component' in the locations
# specified at ${ARGV}. It looks for files ending either in '.t.cpp' (for
# bde test suites) or in '.g.cpp' (for GTest test suites). The path to the
# source file is returned in 'tdSrc'. The type of test - either 't' or 'g' - is
# returned in 'tdSuffix'.
function(bde_project_find_testdriver component tdSrc tdSuffix)
    set(srcDirs ${ARGV})
    list(REMOVE_AT srcDirs 0 1 2)

    foreach(srcDir ${srcDirs})
        foreach(type "t" "g")
            if(EXISTS "${srcDir}/${component}.${type}.cpp")
                list(APPEND tdSrcList "${srcDir}/${component}.${type}.cpp")
                set(tdSuffix ${type} PARENT_SCOPE)
            endif()
        endforeach()
    endforeach()

    list(LENGTH tdSrcList tdSrcListLength)

    if(${tdSrcListLength} GREATER 1)
        message(
            FATAL_ERROR
            "More than one test driver found for component 
            ${component}: ${tdSrcList}"
        )
    endif()

    set(tdSrc ${tdSrcList} PARENT_SCOPE)
endfunction()

# :: add_test_executable ::
# This function adds a target for test identified by 'name' and with the source
# file in 'src'. The make/test target is 'name.t'.
function(add_test_executable name src)
    add_executable("${name}.t" EXCLUDE_FROM_ALL ${src})
    if (CMAKE_HOST_UNIX)
        add_test(
            NAME
                "${name}.t"
            COMMAND
                "bde_runtest.py" "$<TARGET_FILE:${name}.t>"
        )
    else()
        add_test(
            NAME
                "${name}.t"
            COMMAND
                ${CMAKE_COMMAND} "-DTEST_PROG=$<TARGET_FILE:${name}.t>"
                "-P" "${CMAKE_MODULE_PATH}/bde_run_test.cmake"
        )
    endif()
endfunction()

# :: add_td_target ::
# This function adds a custom target 'name.td' to build all test drivers at once.
# Function also adds this target as a dependency to global target 'all.td'.
function(add_td_target name testDrivers)
    add_custom_target(${name}.t DEPENDS ${testDrivers})
    if(TARGET "all.t")
        add_dependencies(all.t ${name}.t)
    else()
        add_custom_target(all.t DEPENDS ${name}.t)
    endif()
endfunction()

# :: bde_project_group_add_testdrivers ::
# -----------------------------------------------------------------------------
# This functions adds targets to build the test drivers of the specified
# 'components' (if they have a corresponding '.[tg].cpp' file) belonging to the
# specified 'groupName'.

# o Each test driver will have a '<componentName>.t' rule to individually build
#   it. The rule will add extra libraries to the link line as specified by
#   'testDepsLibs'.
# o This will also add a meta rule '<grpName>.t' to build all the test
#   drivers.
#
# NOTE:
# o each test driver is linked with the full group library.
# o the 'components' list is similar to the one returned by the
#   'bde_project_group_metaparse' function.
#
# TEST DRIVER MANIFEST:
#   A '<groupName>_td.manifest' file is generated at the root of the build
#   directory, containing one line per test driver, in the following format:
#       <groupName_cmpName>: /full/path/to/component.t
#   This manifest can be used by test driver executor tools, such as rat.rb.
function(bde_project_group_add_testdrivers groupName components testDepsLibs)
    message(FATAL_ERROR "Invalid implementation")

    foreach(component ${components})
        # Each 'component' is formatted as <pkgName>/<componentName>, retrieve
        # each part.
        string(REGEX REPLACE "/.*$" "" packageName   ${component})
        string(REGEX REPLACE "^.*/" "" componentName ${component})

        # If a <package>/<componentName>.[tg].cpp exists, use it.
        bde_project_find_testdriver(
            ${componentName}
            tdSrc
            tdSuffix
            "${CMAKE_CURRENT_LIST_DIR}/${packageName}"
        )

        if(tdSrc)
            add_test_executable(${componentName} ${tdSuffix} ${tdSrc})
            target_link_libraries(
                "${componentName}.t"
                "${groupName};${testDepsLibs}"
            )
            list(APPEND testDrivers "${componentName}.t")
        else()
            set_property(
                GLOBAL
                APPEND
                PROPERTY "BDEMissingTests"
                "${component}"
            )
        endif()
    endforeach()

    # Add a custom target to build all test drivers at once
    add_td_target("${groupName}" "${testDrivers}")

    set(${groupName}_TEST_DRIVERS ${testDrivers} PARENT_SCOPE)
endfunction()

# :: bde_project_package_add_testdrivers ::
# -----------------------------------------------------------------------------
# This functions adds targets to build the test drivers of the specified
# 'components' (if they have a corresponding '.[tg].cpp' file) belonging to the
# specified 'packageName'.
#
# o Each test driver will have a '<componentName>.t' rule to individually build
#   it. The rule will add extra libraries to the link line as specified by
#   'testDepsLibs'.
#
# o This will also add a meta rule '<packageName>.t' to build all test
#   drivers for the specified package.
#
# NOTE:
#
# o each test driver is linked with the full package library.
#
# o the 'components' list is similar to the one returned by the
#   'bde_project_package_metaparse' function.
#
# TEST DRIVER MANIFEST:
#   A '<packageName>_td.manifest' file is generated at the root of the build
#   directory, containing one line per test driver, in the following format:
#       <packageName_cmpName>: /full/path/to/component.t.tsk
#   This manifest can be used by test driver executor tools, such as rat.rb.
function(
    bde_project_package_add_testdrivers
        packageName
        components
        testDepsLibs
)
    foreach(component ${components})
        # If a <packageName>/<component>.[tg].cpp exists, use it.
        bde_project_find_testdriver(
            ${component}
            tdSrc
            tdSuffix
            "${CMAKE_CURRENT_LIST_DIR}/${packageName}"
        )

        if(tdSrc)
            add_test_executable(${component} ${tdSuffix} ${tdSrc})

            target_link_libraries("${component}.t" "${testDepsLibs}")

            list(APPEND testDrivers "${component}.t")
            list(
                APPEND
                manifestContent
                "${component}: $<TARGET_FILE:${component}.t>"
            )
        else()
            set_property(
                GLOBAL
                APPEND
                PROPERTY "BDEMissingTests"
                "${component}"
            )
        endif()
    endforeach()

    # Add a custom target to build all test drivers at once
    add_td_target("${packageName}" "${testDrivers}")

    set(${packageName}_TEST_DRIVERS ${testDrivers} PARENT_SCOPE)
endfunction()

# :: bde_project_application_add_testdrivers ::
# -----------------------------------------------------------------------------
# This functions adds targets to build the test drivers of the specified
# 'components' (if they have a corresponding '.[tg].cpp' file) belonging to the
# specified 'appName' linked with the specified 'depsLibs'.
# o It first builds a "appName_tdlib" support library, composed of all the
#   components, excluding the .m.cpp. All test drivers will be linked against
#   that library. The rule will add extra libraries to the link line as
#   specified by 'testDepsLibs'.
# o Each test driver will have a '<componentName>.t' rule to individually build
#   it.
# o This will also add a meta rule '<appName>.td' to build all the test
#   drivers.
#
# NOTE:
# o the 'components' list is similar to the one returned by the
#   'BDEproject_application_metaparse' function.
#
# TEST DRIVER MANIFEST:
#   A '<appName>_td.manifest' file is generated at the root of the build
#   directory, containing one line per test driver, in the following format:
#       <cmpName>: /full/path/to/component.t.tsk
#   This manifest can be used by test driver executor tools, such as rat.rb.
#
function(bde_project_application_add_testdrivers appName components depsLibs)
    message(FATAL_ERROR "Invalid implementation")

    # 1. Remove the .m from the components list
    list(REMOVE_ITEM components "${appName}.m")

    # 2. If the list of components is empty (some 'gmock' test application are
    #    only composed of a single .m file), then return, nothing to do.
    list(LENGTH components nbComponents)
    if(nbComponents EQUAL 0)
        return()
    endif()

    # Build list of all the components sources
    foreach(cmp ${components})
        list(APPEND sources "${cmp}.cpp")
    endforeach()

    # Build a 'support' library, containing all the .cpp of the application's
    # components, so that the associated .o are generated only once for all
    # .t.tsk (otherwise, each test driver target would compile the .o).
    add_library("${appName}_tdlib" EXCLUDE_FROM_ALL ${sources})

    target_include_directories(
        "${appName}_tdlib"
        BEFORE
        PUBLIC
            "$<TARGET_PROPERTY:${appName},INCLUDE_DIRECTORIES>"
    )
    target_compile_options(
        "${appName}_tdlib"
        PUBLIC
            "$<TARGET_PROPERTY:${appName},COMPILE_OPTIONS>"
    )
    target_link_libraries("${appName}_tdlib" "${depsLibs}")

    foreach(component ${components})
        # If a test/<component>.[tg].cpp exists, use it, else check if
        # <component>.[tg].cpp exists.
        BDEproject_find_testdriver(
            ${component}
            tdSrc
            tdSuffix
            "${CMAKE_CURRENT_LIST_DIR}/test"
            "${CMAKE_CURRENT_LIST_DIR}"
        )

        if(tdSrc)
            add_test_executable(${component} ${tdSuffix} ${tdSrc})
            target_link_libraries("${component}.t" "${appName}_tdlib")

            list(APPEND testDrivers "${component}.t")
            list(
                APPEND
                manifestContent
                "${component}: $<TARGET_FILE:${component}.t>"
            )
        else()
            set_property(
                GLOBAL
                APPEND
                PROPERTY "BDEMissingTests"
                "${component}"
            )
        endif()
    endforeach()

    # Add a custom target to build all test drivers at once
    add_td_target("${appName}" "${testDrivers}")

    # Generate the test driver manifest for that group library
    string(REGEX REPLACE ";" "\n" manifestContent "${manifestContent}")
    file(
        GENERATE
        OUTPUT "${CMAKE_BINARY_DIR}/${appName}_td.manifest"
        CONTENT "${manifestContent}\n"
    )
    set(${appName}_TEST_DRIVERS ${testDrivers} PARENT_SCOPE)
endfunction()

