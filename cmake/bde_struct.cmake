if(BDE_STRUCT_INCLUDED)
    return()
endif()
set(BDE_STRUCT_INCLUDED true)

#####################################################################
# BDE struct
#####################################################################
function(bde_struct_create type name)
    # An INTERFACE library, so it doesn't show up in MSVC solution
    add_library(${name}-INFO INTERFACE)
    if(NOT ${type})
        message(
            FATAL_ERROR
            "Attempted to create a struct of undefined type '${type}'"
        )
    endif()

    internal_struct_set_field_raw(${name} STRUCT_TYPE ${type})
endfunction()

macro(internal_struct_get_type out name)
    internal_struct_get_field_raw(${out} ${name} STRUCT_TYPE)
endmacro()

function(internal_struct_check_field name field)
    internal_struct_get_type(type ${name})
    if(NOT "${field}" IN_LIST ${type})
        message(
            FATAL_ERROR
            "Field '${field}' does not exist in the struct '${name}' of type\
             '${type}'"
        )
    endif()
endfunction()

function(internal_struct_append_field_raw name field value)
    set_property(
        TARGET ${name}-INFO
        APPEND PROPERTY INTERFACE_${field} ${value} ${ARGN}
    )
endfunction()

function(internal_struct_set_field_raw name field value)
    set_property(
        TARGET ${name}-INFO
        PROPERTY INTERFACE_${field} ${value} ${ARGN}
    )
endfunction()

function(internal_struct_get_field_raw retFieldValue name field)
    get_target_property(val ${name}-INFO INTERFACE_${field})
    if("${val}" STREQUAL "val-NOTFOUND")
        set(val "")
    endif()
    bde_return(${val})
endfunction()

function(bde_struct_append_field name field value)
    internal_struct_check_field(${name} ${field})
    internal_struct_append_field_raw(${name} ${field} "${value}" ${ARGN})
endfunction()

function(bde_struct_set_field name field value)
    internal_struct_check_field(${name} ${field})
    internal_struct_set_field_raw(${name} ${field} "${value}" ${ARGN})
endfunction()

function(bde_struct_get_field retFieldValue name field)
    internal_struct_check_field(${name} ${field})
    internal_struct_get_field_raw(val ${name} ${field})
    bde_return(${val})
endfunction()

function(bde_struct_check_return name expectedType callee)
    set(messagePrologue
        "${callee} failed to return a struct of type '${expectedType}':\
         returned '${name}'"
    )
    if (NOT TARGET ${name}-INFO)
        message(FATAL_ERROR "${messagePrologue} which is not a struct.")
    endif()

    internal_struct_get_type(type ${name})
    if (NOT type STREQUAL expectedType)
        message(FATAL_ERROR "${messagePrologue} of type '${type}'.")
    endif()
endfunction()
