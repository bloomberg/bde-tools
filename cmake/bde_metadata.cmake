## bde_metadata.cmake
## ------------------
#
#  This CMake module exposes a set of generic functions for parsing BDE
#  Metadata to get the UOR's components/packages and dependencies
#
## OVERVIEW
## --------
# o bde_project_parse_group_metadata.......: Parses BDE Metadata for a Package
#                                            Group by parsing the top level
#                                            group folder for the packages and
#                                            dependencies, and then each of the
#                                            package's package folder for the
#                                            individual components.
# o bde_project_parse_package_metadata.....: Parses BDE Metadata for a Standalone
#                                            package by parsing the package folder
#                                            for individual components and
#                                            dependencies.
# o bde_project_parse_application_metadata.: Parses BDE Metadata for an Application
#                                            by parsing either the application or
#                                            package folder for the individual
#                                            components and dependencies.
#
## ========================================================================= ##

if(BDE_METADATA_INCLUDED)
    return()
endif()
set(BDE_METADATA_INCLUDED true)

# Standard CMake modules.
include(CMakeParseArguments)

# BDE Cmake modules.
include(bde_utils)

# :: bde_project_parse_group_metadata ::
# ----------------------------------------------------------------------------- 
# This function parses the metadata (.dep and .mem files) of the specified
# 'groupName' group library, and exports the following variables:
#
#  o <groupName>_PACKAGES:     List of packages in the library
#  o <groupName>_COMPONENTS:   List of relative path to all the components in the
#                              library
#  o <groupName>_HEADERS:      List of relative path to all .h headers in the
#                              library
#  o <groupName>_SOURCES:      List of relative path to all .cpp source files in
#                              the library
#  o <groupName>_DEPENDS:      List of 'raw' dependencies of the library
#  o <groupName>_TEST_DEPENDS: List of 'raw' 'extra' TEST dependencies of the
#                              library
#
# Options
# -------
#  o PACKAGES_FILTER: If set, packages not matching this RegExp will be ignored
#
# NOTE: This function must be called from within a 'src/groups/<groupName>/' 
#       directory
#
function(bde_project_parse_group_metadata groupName)
    # Extract list of packages from the group/<grpName>.mem
    bde_utils_add_meta_file(
        "${CMAKE_CURRENT_LIST_DIR}/${groupName}.mem" packages
        TRACK
    )

    # Get list of all dependencies from the group/<groupName>.dep
    bde_utils_add_meta_file(
        "${CMAKE_CURRENT_LIST_DIR}/${groupName}.dep" depends
        TRACK
    )

    # Get list of all TEST dependencies from the group/<groupName>.t.dep
    if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${groupName}.t.dep")
        bde_utils_add_meta_file(
            "${CMAKE_CURRENT_LIST_DIR}/${groupName}.t.dep"
            testDepends
            TRACK
        )
    endif()

    # Export to caller the various variables
    set(${groupName}_PACKAGES      ${packages}     PARENT_SCOPE)
    set(${groupName}_DEPENDS       ${depends}      PARENT_SCOPE)
    set(${groupName}_TEST_DEPENDS  ${testDepends}  PARENT_SCOPE)
endfunction()

# :: bde_project_parse_package_metadata ::
# ----------------------------------------------------------------------------- 
# This function parses the metadata (.dep and .mem files) of the specified
# 'packageName' standalone package library, and exports the following
# variables:
#  o <packageName>_COMPONENTS:    List of relative path to all the components
#                                 in the library
#
#  o <packageName>_HEADERS:       List of relative path to all .h headers in
#                                 the library
#
#  o <packageName>_SOURCES:       List of relative path to all .cpp source
#                                 files in the library
#
#  o <packageName>_DEPENDS:       List of 'raw' dependencies of the library
#
#  o <packageName>_TEST_DEPENDS:  List of 'raw' 'extra' TEST dependencies of
#                                 the library
#
# NOTE: This function must be called from within a '<package>/' directory
#
function(bde_project_parse_package_metadata packageName)
    # Get the list of all sources by looking at the .mem of each packages
    # Also generate a list of all headers (useful for install rules)
    set(headers)
    set(sources)

    bde_utils_add_meta_file(
        "${packageName}/package/${packageName}.mem"
        components
        TRACK
    )

    foreach(component ${components})
        list(APPEND headers "${packageName}/${component}.h")
        if(EXISTS "${CMAKE_CURRENT_LIST_DIR}/${packageName}/${component}.cpp")
            list(APPEND sources "${packageName}/${component}.cpp")
        else()
            message(FATAL_ERROR ".cpp file for ${component} not found.")
        endif()
    endforeach()

    # Get list of all dependencies from the <folderName>/<packageName>.dep
    bde_utils_add_meta_file(
        "${packageName}/package/${packageName}.dep"
        depends
        TRACK
    )

    # Get list of all TEST dependencies from the
    # <packageName>/package/<packageName>.t.dep
    if(EXISTS "${packageName}/package/${packageName}.t.dep")
        bde_utils_add_meta_file(
            "${packageName}/package/${packageName}.t.dep"
            testDepends
            TRACK
        )
    endif()

    # Export to caller the various variables
    set(${packageName}_COMPONENTS    ${components}   PARENT_SCOPE)
    set(${packageName}_HEADERS       ${headers}      PARENT_SCOPE)
    set(${packageName}_SOURCES       ${sources}      PARENT_SCOPE)
    set(${packageName}_DEPENDS       ${depends}      PARENT_SCOPE)
    set(${packageName}_TEST_DEPENDS  ${testDepends}  PARENT_SCOPE)
endfunction()

# :: bde_project_parse_application_metadata ::
# -----------------------------------------------------------------------------
# This function parses the metadata (.dep and .mem files) of the specified
# 'appName' application, and exports the following variables:
#  o <appName>_HEADERS:       List of relative path to all .h headers in the
#                             application
#
#  o <appName>_SOURCES:       List of relative path to all .cpp source files in
#                             the application
#
#  o <appName>_DEPENDS:       List of 'raw' dependencies of the application
#
#  o <appName>_TEST_DEPENDS:  List of 'raw' 'extra' TEST dependencies of the
#                             application
#
# NOTE: This function must be called from within a '<app>/' directory
#
function(bde_project_parse_application_metadata appname)
    if(
        EXISTS "${CMAKE_CURRENT_LIST_DIR}/application/${appName}.dep" AND
        EXISTS "${CMAKE_CURRENT_LIST_DIR}/application/${appName}.mem"
    )
        bde_project_parse_package_metadata(${appName} "application")
    else()
        bde_project_parse_package_metadata(${appName} "package")
    endif()

    # It's possible that 'appName.m' is not listed in components, add it, if
    # needed
    list(FIND ${appName}_COMPONENTS "${appName}.m" mainIndex)
    if(
        mainIndex EQUAL -1 AND
        EXISTS "${CMAKE_CURRENT_LIST_DIR}/${appName}.m.cpp"
    )
        list(APPEND ${appName}_COMPONENTS "${appName}.m")
        list(APPEND ${appName}_SOURCES "${appName}.m.cpp")
    endif()

    # Get actual task/application name from ${appName} (without the 'm_', if
    # present)
    STRING(REGEX REPLACE "(m_)?(.+)" "\\2" tskName ${appName})

    # It's possible that 'tskName.m' is not listed in components, add it, if needed
    list(FIND ${appName}_COMPONENTS "${tskName}.m" mainIndex)
    if(
        mainIndex EQUAL -1 AND
        EXISTS "${CMAKE_CURRENT_LIST_DIR}/${tskName}.m.cpp"
    )
        list(APPEND ${appName}_COMPONENTS "${tskName}.m")
        list(APPEND ${appName}_SOURCES "${tskName}.m.cpp")
    endif()

    # Export to caller the various variables
    set(${appName}_COMPONENTS    ${${appName}_COMPONENTS}    PARENT_SCOPE)
    set(${appName}_HEADERS       ${${appName}_HEADERS}       PARENT_SCOPE)
    set(${appName}_SOURCES       ${${appName}_SOURCES}       PARENT_SCOPE)
    set(${appName}_DEPENDS       ${${appName}_DEPENDS}       PARENT_SCOPE)
    set(${appName}_TEST_DEPENDS  ${${appName}_TEST_DEPENDS}  PARENT_SCOPE)
endfunction()
