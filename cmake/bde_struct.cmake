if(BDE_STRUCT_INCLUDED)
    return()
endif()
set(BDE_STRUCT_INCLUDED true)

include(CMakeParseArguments)

#####################################################################
# BDE struct
#####################################################################
function(bde_register_struct_type typeName)
    get_property(fields GLOBAL PROPERTY ${typeName})
    set(allFields "NAME;${ARGN}")
    if(fields AND NOT "${fields}" STREQUAL "${allFields}")
        message(
            FATAL_ERROR
            "Struct type with name ${typeName} already registered with \
            different contents (${fields})"
        )
    endif()
    set_property(GLOBAL PROPERTY ${typeName} ${allFields})
endfunction()

function(bde_struct_create retStructName type)
    get_property(storageIndex GLOBAL PROPERTY bdeInternalStructStorageIndex)
    if(NOT storageIndex)
        set(storageIndex 0)
    endif()
    math(EXPR storageIndex "${storageIndex} + 1")
    set_property(GLOBAL PROPERTY bdeInternalStructStorageIndex ${storageIndex})

    # An INTERFACE library, so it doesn't show up in MSVC solution
    set(name _bde_struct_${storageIndex})
    add_library(${name} INTERFACE)
    get_property(fields GLOBAL PROPERTY ${type})
    if(NOT fields)
        message(
            FATAL_ERROR
            "Struct type '${type}' is not registered \
            (see 'bde_register_struct_type')"
        )
    endif()

    internal_struct_set_field_raw(${name} STRUCT_TYPE ${type})

    cmake_parse_arguments("init" "" "" "${fields}" ${ARGN})
    bde_assert_no_unparsed_args("init")

    if(NOT init_NAME)
        set(init_NAME "unnamed struct")
    endif()

    foreach(field IN LISTS fields)
        if(init_${field})
            internal_struct_set_field_raw(${name} ${field} "${init_${field}}")
        endif()
    endforeach()

    bde_return(${name})
endfunction()

macro(internal_struct_get_type_name out name)
    internal_struct_get_field_raw(${out} ${name} STRUCT_TYPE)
endmacro()

function(internal_struct_get_description out name)
    internal_struct_get_type_name(type ${name})
    internal_struct_get_field_raw(humanReadableName ${name} NAME)
    bde_return("${humanReadableName} [${type}]")
endfunction()

function(internal_struct_check_field name field)
    internal_struct_get_type_name(type ${name})
    get_property(fields GLOBAL PROPERTY ${type})
    if(NOT "${field}" IN_LIST fields)
        internal_struct_get_description(desc ${name})
        message(
            FATAL_ERROR
            "Field '${field}' does not exist in the struct ${desc}"
        )
    endif()
endfunction()

function(internal_struct_append_field_raw name field value)
    set_property(
        TARGET ${name}
        APPEND PROPERTY INTERFACE_${field} ${value} ${ARGN}
    )
endfunction()

function(internal_struct_set_field_raw name field value)
    set_property(
        TARGET ${name}
        PROPERTY INTERFACE_${field} ${value} ${ARGN}
    )
endfunction()

function(internal_struct_get_field_raw retFieldValue name field)
    get_target_property(val ${name} INTERFACE_${field})
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
         returned"
    )
    if (NOT TARGET ${name})
        message(FATAL_ERROR "${messagePrologue} non-existing '${name}'.")
    endif()

    internal_struct_get_type_name(type ${name})
    if (NOT type STREQUAL expectedType)
        internal_struct_get_description(desc ${name})
        message(FATAL_ERROR "${messagePrologue} '${desc}'.")
    endif()
endfunction()
