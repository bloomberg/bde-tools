if(BDE_INTERFACE_TARGET_INCLUDED)
    return()
endif()
set(BDE_INTERFACE_TARGET_INCLUDED true)

include(bde_utils)

#####################################################################
# Interface target
#####################################################################

function(bde_add_interface_target name)
    bde_assert_no_extra_args()
    add_library(${name}-INTERFACE INTERFACE)
    add_library(${name}-PRIVATE INTERFACE)
endfunction()

function(bde_target_link_interface_target target name)
    cmake_parse_arguments("" "INTERFACE_ONLY" "" "" ${ARGN})
    bde_assert_no_unparsed_args("")

    set(types PRIVATE INTERFACE)
    if(_INTERFACE_ONLY)
        set(types INTERFACE)
    endif()

    foreach(type IN LISTS types)
        target_link_libraries(
            ${target}
            ${type} ${name}-${type}
        )
    endforeach()
endfunction()

# Merge the requirements from 'other_target' to 'target'
function(bde_interface_target_assimilate target other_target)
    cmake_parse_arguments("" "INTERFACE_ONLY" "" "" ${ARGN})
    bde_assert_no_unparsed_args("")

    set(types PRIVATE INTERFACE)
    if(_INTERFACE_ONLY)
        set(types INTERFACE)
    endif()

    foreach(type IN LISTS types)
        target_link_libraries(
            ${target}-${type}
            INTERFACE ${other_target}-${type}
        )
    endforeach()
endfunction()

# Unfortunately, the functions below are copy-pasted
# because a function cannot be called if its name is
# stored in a variable
macro(internal_parse_and_join_arguments prefix)
    cmake_parse_arguments(${prefix} "" "" "PUBLIC;PRIVATE;INTERFACE" ${ARGN})
    bde_assert_no_unparsed_args(${prefix})

    if (${prefix}_PUBLIC)
        list(APPEND ${prefix}_PRIVATE ${${prefix}_PUBLIC})
        list(APPEND ${prefix}_INTERFACE ${${prefix}_PUBLIC})
    endif()
endmacro()

function(bde_interface_target_include_directories name)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            target_include_directories(
                ${name}-${type}
                INTERFACE ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

function(bde_interface_target_compile_options name)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            target_compile_options(
                ${name}-${type}
                INTERFACE ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

function(bde_interface_target_compile_definitions name)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            target_compile_definitions(
                ${name}-${type}
                INTERFACE ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

function(bde_interface_target_compile_features name)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            target_compile_features(
                ${name}-${type}
                INTERFACE ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

function(bde_interface_target_link_libraries name)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            target_link_libraries(
                ${name}-${type}
                INTERFACE ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

function(bde_interface_target_set_property name property)
    internal_parse_and_join_arguments(args ${ARGN})

    foreach(type INTERFACE PRIVATE)
        if(args_${type})
            set_target_properties(
                ${name}-${type}
                PROPERTIES INTERFACE_${property} ${args_${type}}
            )
        endif()
    endforeach()
endfunction()

# Get actual interface target names
function(bde_interface_target_names retTargetNames name)
    bde_assert_no_extra_args()
    bde_return(${name}-INTERFACE ${name}-PRIVATE)
endfunction()

# Install INTERFACE targets
function(bde_install_interface_target name)
    bde_interface_target_names(target_names ${name})
    install(
        TARGETS ${target_names}
        ${ARGN}
    )
endfunction()
