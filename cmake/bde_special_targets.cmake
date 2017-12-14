if(BDE_SPECIAL_TARGETS_INCLUDED)
    return()
endif()
set(BDE_SPECIAL_TARGEST_INCLUDED true)

#####################################################################
# Info target
#####################################################################
function(bde_add_info_target name)
    # An INTERFACE library, so it doesn't show up in MSVC solution
    add_library(${name}-INFO INTERFACE)
endfunction()

function(bde_info_target_append_property name property value)
    set_property(
        TARGET ${name}-INFO
        APPEND PROPERTY INTERFACE_${property} ${value} ${ARGN}
    )
endfunction()

function(bde_info_target_set_property name property value)
    set_property(
        TARGET ${name}-INFO
        PROPERTY INTERFACE_${property} ${value} ${ARGN}
    )
endfunction()

function(bde_info_target_get_property output name property)
    get_target_property(val ${name}-INFO INTERFACE_${property})
    if("${val}" STREQUAL "val-NOTFOUND")
        set(val "")
    endif()
    set(${output} ${val} PARENT_SCOPE)
endfunction()

function(bde_info_target_name out name)
    set(${out} ${name}-INFO PARENT_SCOPE)
endfunction()

#####################################################################
# Interface target
#####################################################################

function(bde_add_interface_target name)
    add_library(${name}-INTERFACE INTERFACE)
    add_library(${name}-PRIVATE INTERFACE)
endfunction()

function(bde_target_link_interface_target target name)
    target_link_libraries(
        ${target}
        INTERFACE ${name}-INTERFACE
        PRIVATE ${name}-PRIVATE
    )
endfunction()

# Merge the requirements from 'other_target' to 'target'
function(bde_interface_target_assimilate target other_target)
    foreach(type INTERFACE PRIVATE)
        target_link_libraries(
            ${target}-${type}
            INTERFACE ${other_target}-${type}
        )
    endforeach()
endfunction()

# Unfortunately, the functions below are copy-pasted
# because a function cannot be called if its name is
# stored in a variable
macro(_parse_and_join_arguments prefix)
    cmake_parse_arguments(${prefix} "" "" "PUBLIC;PRIVATE;INTERFACE" ${ARGN})

    if (${prefix}_PUBLIC)
        list(APPEND ${prefix}_PRIVATE ${${prefix}_PUBLIC})
        list(APPEND ${prefix}_INTERFACE ${${prefix}_PUBLIC})
    endif()
endmacro()

function(bde_interface_target_include_directories name)
    _parse_and_join_arguments(args ${ARGN})

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
    _parse_and_join_arguments(args ${ARGN})

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
    _parse_and_join_arguments(args ${ARGN})

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
    _parse_and_join_arguments(args ${ARGN})

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
    _parse_and_join_arguments(args ${ARGN})

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
    _parse_and_join_arguments(args ${ARGN})

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
function(bde_interface_target_names out name)
    set(${out} ${name}-INTERFACE ${name}-PRIVATE PARENT_SCOPE)
endfunction()

# Install INTERFACE targets
function(bde_install_interface_target name)
    bde_interface_target_names(target_names ${name})
    install(
        TARGETS ${target_names}
        ${ARGN}
    )
endfunction()
