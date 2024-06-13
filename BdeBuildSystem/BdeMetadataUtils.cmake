include_guard()

#[[.rst:
BdeMetadataUtils
----------------
This module provide a set of function to parse BDE metadata files.
#]]

#[[.rst:
.. command:: bbs_read_metadata

This command reads BDE group or package level metadata files and populates a
set of list variables that describe the content of the groups and/pr package(s)
respectively.

.. code-block:: cmake

   bbs_read_metadata(PACKAGE <package>
                     [SOURCE_DIR <dir>])

PACKAGE mode reads the bde metadata file for a single package from the
optionally specified ``SOURCE_DIR`` (if not specified, the value of
``CMAKE_CURRENT_SOURCE_DIR`` is used) and sets the following list variables in
the parent scope:

    * <package>_COMPONENTS
    * <package>_DEPENDS
    * <package>_PCDEPS
    * <package>_INCLUDE_DIRS
    * <package>_INCLUDE_FILES
    * <package>_SOURCE_DIRS
    * <package>_SOURCE_FILES
    * <package>_MAIN_SOURCE
    * <package>_TEST_DEPENDS
    * <package>_TEST_PCDEPS
    * <package>_TEST_SOURCES
    * <package>_GTEST_SOURCES
    * <package>_METADATA_DIR

.. code-block:: cmake

   bbs_read_metadata(GROUP <group>
                     [SOURCE_DIR <dir>]
                     [CUSTOM_PACKAGES <pkg list>]
                     [PRIVATE_PACKAGES <pkg list>])

GROUP mode reads the bde group metadata files from the optionally specified
``SOURCE_DIR`` (if not specified, the value of ``CMAKE_CURRENT_SOURCE_DIR`` is
used) skipping the optionally specified ``CUSTOM_PACKAGES`` folders.
Additionally for all ``PRIVATE`` packages the include files will not be added
to the  ``INCLUDE_FILES`` variable for the group.
Subfolder in the ``SOURCE_DIR`` s treatead as a folder containing a package.
In addition to package list variables, it sets the following group list
variables in the parent scope:

    * <group>_PACKAGES
    * <group>_COMPONENTS
    * <group>_DEPENDS
    * <group>_PCDEPS
    * <group>_INCLUDE_DIRS
    * <group>_INCLUDE_FILES
    * <group>_SOURCE_DIRS
    * <group>_SOURCE_FILES
    * <group>_TEST_DEPENDS
    * <group>_TEST_PCDEPS
    * <group>_TEST_SOURCES
    * <group>_GTEST_SOURCES
    * <group>_METADATA_DIRS
#]]
function(bbs_read_metadata)
    cmake_parse_arguments(PARSE_ARGV 0
                          ""
                          ""
                          "PACKAGE;GROUP;SOURCE_DIR"
                          "CUSTOM_PACKAGES;PRIVATE_PACKAGES")
    bbs_assert_no_unparsed_args("")

    if (_PACKAGE AND _GROUP)
        message(FATAL_ERROR "Cannot specify both PACKAGE and GROUP")
    endif()

    if (NOT _SOURCE_DIR)
        set(_SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR})
    else()
        get_filename_component(_SOURCE_DIR ${_SOURCE_DIR} ABSOLUTE)
    endif()

    if (_PACKAGE)
        bbs_read_package_metadata(${_PACKAGE} ${_SOURCE_DIR})
    elseif (_GROUP)
        bbs_read_group_metadata(${_GROUP}
                                ${_SOURCE_DIR}
                                CUSTOM_PACKAGES "${_CUSTOM_PACKAGES}"
                                PRIVATE_PACKAGES "${_PRIVATE_PACKAGES}")
    endif()

endfunction()

# reads the package metadata in the given directory
macro(bbs_read_package_metadata pkg dir)
    set(_meta_dir ${dir}/package)
    set(${pkg}_METADATA_DIRS ${_meta_dir})

    unset(mems)

    _bbs_read_bde_metadata(${_meta_dir}/${pkg}.mem mems)
    _bbs_set_bde_component_lists(${dir} ${pkg} mems)

    if (EXISTS ${_meta_dir}/${pkg}.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${pkg}.dep ${pkg}_DEPENDS)
        set(${pkg}_DEPENDS ${${pkg}_DEPENDS} PARENT_SCOPE)

        bbs_uor_to_pc_list("${${pkg}_DEPENDS}" ${pkg}_PCDEPS)
        set(${pkg}_PCDEPS ${${pkg}_PCDEPS} PARENT_SCOPE)
    endif()


    if (EXISTS ${_meta_dir}/${pkg}.t.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${pkg}.t.dep ${pkg}_TEST_DEPENDS)
        set(${pkg}_TEST_DEPENDS ${${pkg}_TEST_DEPENDS} PARENT_SCOPE)

        bbs_uor_to_pc_list("${${pkg}_TEST_DEPENDS}" ${pkg}_TEST_PCDEPS)
        set(${pkg}_TEST_PCDEPS ${${pkg}_TEST_PCDEPS} PARENT_SCOPE)
    endif()

    set(${pkg}_METADATA_DIRS ${${pkg}_METADATA_DIRS} PARENT_SCOPE)
endmacro()

macro(bbs_read_group_metadata group dir)
    cmake_parse_arguments(""
                          ""
                          ""
                          "CUSTOM_PACKAGES;PRIVATE_PACKAGES"
                          ${ARGN})
    bbs_assert_no_unparsed_args("")

    set(_meta_dir ${dir}/group)
    list(APPEND ${group}_METADATA_DIRS ${_meta_dir})

    unset(pkgs)

    _bbs_read_bde_metadata(${_meta_dir}/${group}.mem pkgs)

    set(${group}_DEPENDS "")
    set(${group}_PCDEPS  "")
    if (EXISTS ${_meta_dir}/${group}.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${group}.dep ${group}_DEPENDS)
        set(${group}_DEPENDS ${${group}_DEPENDS})
        bbs_uor_to_pc_list("${${group}_DEPENDS}" ${group}_PCDEPS)
        set(${group}_PCDEPS ${${group}_PCDEPS})
    endif()

    set(${group}_TEST_DEPENDS "")
    set(${group}_TEST_PCDEPS  "")
    if (EXISTS ${_meta_dir}/${group}.t.dep)
        _bbs_read_bde_metadata(${_meta_dir}/${group}.t.dep ${group}_TEST_DEPENDS)
        set(${group}_TEST_DEPENDS ${${group}_TEST_DEPENDS})
        bbs_uor_to_pc_list("${${group}_TEST_DEPENDS}" ${group}_TEST_PCDEPS)
        set(${group}_TEST_PCDEPS ${${group}_TEST_PCDEPS})
    endif()

    foreach(pkg ${pkgs})
        list(APPEND ${group}_PACKAGES ${pkg})
        if (${pkg} IN_LIST _CUSTOM_PACKAGES)
            message(TRACE "Skipping metadata for custom ${pkg}")
        else()
            message(TRACE "Parsing metadata for package ${pkg}")
            bbs_read_package_metadata(${pkg} ${_SOURCE_DIR}/${pkg})
            set(propagate_properties COMPONENTS INCLUDE_DIRS INCLUDE_FILES
                                     SOURCE_DIRS SOURCE_FILES
                                     TEST_SOURCES GTEST_SOURCES METADATA_DIRS)

            # Private packages do not propagate their include files to the group
            if (${pkg} IN_LIST _PRIVATE_PACKAGES)
                message (TRACE "Package ${pkg} is private: skipping headers")
                list(REMOVE_ITEM propagate_properties INCLUDE_FILES)
            endif()

            foreach(var ${propagate_properties})
                list(APPEND ${group}_${var}     ${${pkg}_${var}})
            endforeach()

            foreach(dep ${${pkg}_DEPENDS})
                if (NOT dep IN_LIST pkgs)
                    message(WARNING "Package \"${pkg}\" has \"${dep}\" dependency outside of package group (${pkgs}). Check ${pkg}/package/${pkg}.dep file.")
                endif()
            endforeach()
        endif()
    endforeach()

    foreach(var PACKAGES DEPENDS PCDEPS TEST_DEPENDS TEST_PCDEPS COMPONENTS
                INCLUDE_DIRS INCLUDE_FILES SOURCE_DIRS SOURCE_FILES
                TEST_SOURCES GTEST_SOURCES METADATA_DIRS)
        set(${group}_${var} ${${group}_${var}} PARENT_SCOPE)
    endforeach()
endmacro()

# reads each line of the file into the 'items' list
macro(_bbs_read_bde_metadata filename items)
    # reconfigure if this file changes
    bbs_track_file(${filename})

    # Read all lines from 'filename'
    file(STRINGS "${filename}" lines)

    foreach(line IN LISTS lines)
        # Remove comments, leading & trailing spaces, squash spaces
        if (line)
            string(REGEX REPLACE " *#.*$" "" line "${line}")
            string(STRIP "${line}" line)
        endif()

        if (line)
            # Handle lines with multiple entries.
            string(REGEX REPLACE " +" ";" line_list "${line}")
            list(APPEND ${items} ${line_list})
        endif()
    endforeach()
endmacro()

macro(_bbs_set_bde_component_lists dir package mems)
    list(APPEND ${package}_INCLUDE_DIRS ${dir})
    list(APPEND ${package}_SOURCE_DIRS  ${dir})

    foreach(mem IN LISTS ${mems})
        list(APPEND ${package}_COMPONENTS ${mem})

        # This variable is used to generate a warning for the mem entries that
        # do not have any existing headers/source files.
        set(component_found FALSE)

        # Special case entry in .mem file points to the actual file and not the
        # component
        if (EXISTS ${dir}/${mem})
            get_filename_component(file_suffix ${mem} EXT)
            set(header_extensions ".h" ".fwd.h")
            set(source_extensions ".c" ".cpp")
            if ("${file_suffix}" IN_LIST header_extensions)
                list(APPEND ${package}_INCLUDE_FILES ${dir}/${mem})
                continue() # Not strictly needed, but speeds thing up
            elseif("${file_suffix}" IN_LIST source_extensions)
                list(APPEND ${package}_SOURCE_FILES ${dir}/${mem})
                continue() # Not strictly needed, but speeds thing up
            else()
                message(WARNING "Unrecognized entry in .mem file: ${mem}")
            endif()
        endif()

        if (EXISTS ${dir}/${mem}.h)
            set(component_found TRUE)
            list(APPEND ${package}_INCLUDE_FILES ${dir}/${mem}.h)
        endif()

        if (EXISTS ${dir}/${mem}.fwd.h)
            set(component_found TRUE)
            list(APPEND ${package}_INCLUDE_FILES ${dir}/${mem}.fwd.h)
        endif()

        if (EXISTS ${dir}/${mem}.cpp)
            set(component_found TRUE)
            list(APPEND ${package}_SOURCE_FILES ${dir}/${mem}.cpp)

            if (EXISTS ${dir}/${mem}.t.cpp)
                list(APPEND ${package}_TEST_SOURCES ${dir}/${mem}.t.cpp)
            elseif(EXISTS ${dir}/${mem}.g.cpp)
                list(APPEND ${package}_GTEST_SOURCES ${dir}/${mem}.g.cpp)
            endif()

            # finding numbered and forwarding header tests
            file(GLOB numbered_tests "${dir}/${mem}.*.t.cpp")
            foreach(ntest IN LISTS numbered_tests)
                list(APPEND ${package}_TEST_SOURCES ${ntest})
            endforeach()
        endif()

        if (EXISTS ${dir}/${mem}.c)
            set(component_found TRUE)
            list(APPEND ${package}_SOURCE_FILES ${dir}/${mem}.c)

            if (EXISTS ${dir}/${mem}.t.c)
                list(APPEND ${package}_TEST_SOURCES ${dir}/${mem}.t.c)
            endif()
            # No numbered/forwarding test drivers for C. Add if needed.
        endif()

        if (NOT component_found)
            message(WARNING "No source files for component ${mem} found")
        endif()
    endforeach()

    # Check for a main file that is not listed as a component
    if (NOT ${package}_MAIN_SOURCE AND EXISTS ${dir}/${package}.m.cpp)
        list(APPEND ${package}_MAIN_SOURCE ${dir}/${package}.m.cpp)
    endif()

    # propagate the lists to the caller
    foreach(var COMPONENTS INCLUDE_DIRS INCLUDE_FILES
                SOURCE_DIRS SOURCE_FILES MAIN_SOURCE
                TEST_SOURCES GTEST_SOURCES)
        set(${package}_${var} ${${package}_${var}} PARENT_SCOPE)
    endforeach()
endmacro()
