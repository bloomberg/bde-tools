## bde_utils.cmake
## ---------------
#
#  This CMake module exposes a set of generic macros and functions providing
#  convenience utility.
#
## OVERVIEW
## --------
# o bde_utils_add_meta_file: parse content of the metadata file.
# o bde_utils_track_file:    track file changes to trigger a reconfiguration.
#
## ========================================================================= ##

include(bde_include_guard)
bde_include_guard()

# :: bde_utils_add_meta_file ::
# -----------------------------------------------------------------------------
# Read the content of 'file' and store each token from it in the specified
# 'out' list.
#
# File is processed with respect to the following expected syntax:
#   o '#' with following text till the end of line is ignored
#   o ' ' is considered a token separator for splitting out multiple items from
#     a single line
#
## PARAMETERS
## ----------
# This function takes one optional parameter: 'TRACK'.  The 'file's content
# changes are not tracked by the build system unless 'TRACK' is specified.
#
## EXAMPLE
## -------
# If the 'file' contains the following:
#    a
#    b c d
#    # Comment
#    e # Comment
# The result will be: a;b;c;d;e
function(bde_utils_add_meta_file file out)
    # Parameters parse
    #   One optional parameter: TRACK
    cmake_parse_arguments(args "TRACK" "" "" ${ARGN})
    bde_assert_no_unparsed_args(args)

    # Read all lines from 'file', ignoring the ones starting with '#'
    file(STRINGS "${file}" lines REGEX "^[^#].*")

    set(tmp)

    # For each line, split at ' '
    foreach(line IN LISTS lines)
        # Remove comment
        string(REGEX REPLACE " *#.*$" "" line ${line})

        # In CMake a list is a string with ';' as an item separator.
        string(REGEX REPLACE " " ";" line ${line})

        if(NOT "${line}" STREQUAL "")
            list(APPEND tmp ${line})
        endif()
    endforeach()

    # Set the result
    set(${out} ${tmp} PARENT_SCOPE)

    # Track file for changes if told so.
    if(args_TRACK)
        bde_utils_track_file(${file})
    endif()
endfunction()

# :: bde_utils_track_file ::
# -----------------------------------------------------------------------------
# This function adds the specified 'file' to a set of generator dependancies
# forcing the reconfiguration of the file content changes.  This function is
# used to track changes in the .mem and .dep files.
function( bde_utils_track_file file )
    bde_assert_no_extra_args()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${file})
endfunction()

macro(bde_return)
    list(GET ARGV 0 retVar)
        # Get the first argument passed to the surrounding function. Can't
        # use ${ARGV0} as it would replaced by cmake before macro execution.
    set(${retVar} ${ARGN} PARENT_SCOPE)
    return()
endmacro()

function(bde_utils_list_template_substitute retResult placeholder template)
    set(result)
    foreach(target IN LISTS ARGN)
        string(REPLACE ${placeholder} ${target} elem ${template})
        list(APPEND result ${elem})
    endforeach()
    bde_return(${result})
endfunction()

function(bde_utils_filter_directories retDirectories)
    set(dirs)
    foreach(f IN LISTS ARGN)
        if(IS_DIRECTORY ${f})
            list(APPEND dirs ${f})
        endif()
    endforeach()
    bde_return(${dirs})
endfunction()

function(bde_utils_find_file_extension retFullName baseName extensions)
    bde_assert_no_extra_args()

    foreach(ext IN LISTS extensions)
        set(fullName ${baseName}${ext})
        if(EXISTS ${fullName})
            bde_return(${fullName})
        endif()
    endforeach()

    bde_return("")
endfunction()

function(bde_utils_glob_files retFoundFiles baseName patterns)
    bde_assert_no_extra_args()

    set(found_files)
    foreach(pattern IN LISTS patterns)
        file(GLOB found ${baseName}${pattern})
        list(APPEND found_files ${found})
    endforeach()
    bde_return(${found_files})
endfunction()

function(bde_append_test_labels test)
    set_property(
        TEST ${test}
        APPEND PROPERTY
        LABELS ${ARGN}
    )
endfunction()

macro(bde_assert_no_extra_args)
    if (ARGN)
        # This 'conversion' is required to use the ARGN actually passed
        # to the surrounding function and not the macro itself
        set(args)
        foreach(var IN LISTS ARGN)
            list(APPEND args ${var})
        endforeach()

        message(
            FATAL_ERROR
            "Unexpected extra arguments passed to function: ${args}"
        )

    endif()
endmacro()

macro(bde_assert_no_unparsed_args prefix)
    if (${prefix}_UNPARSED_ARGUMENTS)
        message(
            FATAL_ERROR
            "Unknown arguments arguments passed to function:\
            ${${prefix}_UNPARSED_ARGUMENTS}."
        )
    endif()
endmacro()

function(bde_add_executable target)
    add_executable(${target} ${ARGN} "")
    set_target_properties(
        ${target} PROPERTIES SUFFIX ".tsk${CMAKE_EXECUTABLE_SUFFIX}"
    )
endfunction()

######
# Some common functions useful for all processing stages
######

# Create a test aggregation meta-target
function(bde_create_test_metatarget_for retMetaTarget struct)
    bde_assert_no_extra_args()

    bde_struct_get_field(allTestTargets ${struct} TEST_TARGETS)
    bde_struct_mark_field_const(${struct} TEST_TARGETS)
    bde_struct_get_field(testGroupName ${struct} NAME)
    bde_create_test_metatarget(metaT "${allTestTargets}" ${testGroupName})
    bde_return(${metaT})
endfunction()

function(bde_create_package_test_metatarget package)
    bde_create_test_metatarget_for(dummy ${package})
endfunction()

function(bde_create_uor_test_metatarget uor)
    bde_create_test_metatarget_for(metaT ${uor})
    if(metaT)
        bde_struct_get_field(mainTarget ${uor} TARGET)
        add_dependencies(${metaT} ${mainTarget})
            # Useful for test applications and ability to build
            # the final target by building "target.t" when package libs
            # are used
    endif()
endfunction()

function(bde_create_test_metatarget retMetaTarget allTestTargets testGroupName)
    bde_assert_no_extra_args()

    if(allTestTargets)
        if (NOT TARGET ${testGroupName}.t)
            add_custom_target(${testGroupName}.t)
        endif()
        add_dependencies(${testGroupName}.t ${allTestTargets})
        foreach(test IN LISTS allTestTargets)
            bde_append_test_labels(${test} ${testGroupName})
        endforeach()
        bde_return(${testGroupName}.t)
    endif()
    bde_return("")
endfunction()

function(bde_create_struct_with_interfaces retStruct type)
    bde_struct_create(
        struct
        ${type}
        ${ARGN}
    )

    bde_struct_get_field(name ${struct} NAME)
    bde_add_interface_target(${name})
    bde_struct_set_field(${struct} INTERFACE_TARGET ${name})
    bde_add_interface_target(TEST_${name})
    bde_struct_set_field(${struct} TEST_INTERFACE_TARGET TEST_${name})
    bde_interface_target_assimilate(TEST_${name} ${name})

    foreach(field INTERFACE_TARGET TEST_INTERFACE_TARGET)
        bde_struct_mark_field_const(${struct} ${field})
    endforeach()

    bde_return(${struct})
endfunction()

function(bde_link_target_to_tests struct)
    bde_struct_get_field(target ${struct} TARGET)
    bde_struct_get_field(testInterfaceTarget ${struct} TEST_INTERFACE_TARGET)
    bde_interface_target_link_libraries(${testInterfaceTarget} PRIVATE ${target})
endfunction()

function(internal_read_depends_file retDepends listFile ext)
    bde_assert_no_extra_args()

    get_filename_component(baseName ${listFile} NAME_WE)
    get_filename_component(listDir ${listFile} DIRECTORY)

    set(basePath "${listDir}/${baseName}")

    if(EXISTS "${basePath}.${ext}")
        bde_utils_add_meta_file("${basePath}.${ext}" depends TRACK)
        bde_return("${depends}")
    endif()

    bde_return("")
endfunction()

function(bde_process_dependencies targetStruct listFile)
    cmake_parse_arguments("" "NO_LINK" "" "" ${ARGN})
    bde_assert_no_unparsed_args("")

    internal_read_depends_file(depends ${listFile} "dep")
    bde_struct_append_field(${targetStruct} DEPENDS "${depends}")

    bde_struct_get_field(interfaceTarget ${targetStruct} INTERFACE_TARGET)
    if(NOT _NO_LINK)
        bde_interface_target_link_libraries(${interfaceTarget} PUBLIC "${depends}")
        bde_struct_mark_field_const(${targetStruct} DEPENDS)
    endif()

    if(depends)
        bde_struct_get_field(name ${targetStruct} NAME)
        bde_log(VERBOSE "[${name}] Dependencies: ${depends}")
    endif()
endfunction()

function(bde_process_test_dependencies targetStruct listFile)
    bde_assert_no_extra_args()

    internal_read_depends_file(depends ${listFile} "t.dep")
    bde_struct_append_field(${targetStruct} TEST_DEPENDS "${depends}")

    bde_struct_get_field(testInterfaceTarget ${targetStruct} TEST_INTERFACE_TARGET)
    bde_interface_target_link_libraries(${testInterfaceTarget} PRIVATE "${depends}")
    bde_struct_mark_field_const(${targetStruct} TEST_DEPENDS)

    if(depends)
        bde_struct_get_field(name ${targetStruct} NAME)
        bde_log(VERBOSE "[${name}] Test dependencies: ${depends}")
    endif()
endfunction()

function(bde_expand_list_file listFile)
    set(components FILENAME LISTDIR ROOTDIR)

    cmake_parse_arguments("" "" "${components}" "" ${ARGN})
    bde_assert_no_unparsed_args("")

    get_filename_component(FILENAME ${listFile} NAME_WE)
    get_filename_component(LISTDIR ${listFile} DIRECTORY)
    get_filename_component(ROOTDIR ${LISTDIR} DIRECTORY)
    foreach(component IN LISTS components)
        if(_${component})
            set(${_${component}} ${${component}} PARENT_SCOPE)
        endif()
    endforeach()
endfunction()
