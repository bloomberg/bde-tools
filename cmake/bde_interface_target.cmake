include(bde_include_guard)
bde_include_guard()

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
    bde_assert_no_extra_args()
    foreach(type PRIVATE INTERFACE)
        target_link_libraries(
            ${target}
            ${type} ${name}-${type}
        )
    endforeach()
endfunction()

# Merge the requirements from 'other_target' to 'target'
function(bde_interface_target_assimilate target other_target)
    bde_assert_no_extra_args()
    foreach(type PRIVATE INTERFACE)
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

# Get actual interface target name
function(bde_interface_target_name retTargetName name type)
    bde_assert_no_extra_args()
    set(knownTypes INTERFACE PRIVATE)
    if(NOT ${type} IN_LIST knownTypes)
        message(
            "Unknown interface target type '${type}'. Only PRIVATE and \
            INTERFACE are valid types of the interface target."
        )
    endif()
    bde_return(${name}-${type})
endfunction()

# Install INTERFACE targets
function(bde_install_interface_target name)
    install(
        TARGETS ${name}-INTERFACE ${name}-PRIVATE
        ${ARGN}
    )
endfunction()
