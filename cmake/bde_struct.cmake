include(bde_include_guard)
bde_include_guard()

#####################################################################
# BDE struct
#####################################################################
function(bde_register_struct_type typeName)
    cmake_parse_arguments("" "" "INHERIT" "" ${ARGN})

    get_property(fields GLOBAL PROPERTY ${typeName})
    get_property(base GLOBAL PROPERTY ${typeName}_base)
    set(allFields "${_UNPARSED_ARGUMENTS}")
    if(NOT _INHERIT)
        list(APPEND allFields NAME)
    else()
        get_property(baseFields GLOBAL PROPERTY ${_INHERIT})
        if(NOT baseFields)
            message(
                FATAL_ERROR
                "Struct type attempting to inherit from unknown type ${_INHERIT}"
            )
        endif()
    endif()
    if(fields AND NOT "${fields}" STREQUAL "${allFields}")
        message(
            FATAL_ERROR
            "Struct type with name ${typeName} already registered with \
            different contents (${fields})"
        )
    endif()
    if(base AND NOT "${base}" STREQUAL "${_INHERIT}")
        message(
            FATAL_ERROR
            "Struct type with name ${typeName} already registered with \
            different base (${base})"
        )
    endif()

    set_property(GLOBAL PROPERTY ${typeName} ${allFields})
    set_property(GLOBAL PROPERTY ${typeName}_base "${_INHERIT}")
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
    internal_struct_set_field_raw(${name} STRUCT_TYPE ${type})

    set(baseType ${type})
    while(baseType)
        get_property(fields GLOBAL PROPERTY ${baseType})
        list(APPEND allFields ${fields})
        get_property(baseType GLOBAL PROPERTY ${baseType}_base)
    endwhile()

    if(NOT allFields)
        message(
            FATAL_ERROR
            "Struct type '${type}' is not registered \
            (see 'bde_register_struct_type')"
        )
    endif()

    cmake_parse_arguments(PARSE_ARGV 2 "init" "" "${allFields}" "")
    bde_assert_no_unparsed_args("init")

    if(NOT init_NAME)
        set(init_NAME "unnamed_struct")
    endif()

    foreach(field IN LISTS allFields)
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
    bde_return("'${humanReadableName}' [${type}]")
endfunction()

function(internal_struct_check_field name field)
    internal_struct_get_type_name(type ${name})
    while(type)
        get_property(fields GLOBAL PROPERTY ${type})
        if("${field}" IN_LIST fields)
            return()
        endif()
        get_property(type GLOBAL PROPERTY ${type}_base)
    endwhile()

    internal_struct_get_description(desc ${name})
    message(
        FATAL_ERROR
        "Field '${field}' does not exist in the struct ${desc}"
    )
endfunction()

function(internal_struct_check_field_non_const name field)
    internal_struct_get_field_raw(constFields ${name} INTERNAL_CONST_FIELDS)
    if("${field}" IN_LIST constFields)
        internal_struct_get_description(desc ${name})
        message(
            WARNING
            "Field '${field}' has been marked as const in struct ${desc}.\
             Modifying it after it was marked const would not achieve the\
             desired effect. Please revise your code."
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
    internal_struct_check_field_non_const(${name} ${field})
    internal_struct_append_field_raw(${name} ${field} "${value}" ${ARGN})
endfunction()

function(bde_struct_set_field name field value)
    internal_struct_check_field(${name} ${field})
    internal_struct_check_field_non_const(${name} ${field})
    internal_struct_set_field_raw(${name} ${field} "${value}" ${ARGN})
endfunction()

function(bde_struct_get_field retFieldValue name field)
    internal_struct_check_field(${name} ${field})
    internal_struct_get_field_raw(val ${name} ${field})
    bde_return(${val})
endfunction()

function(bde_struct_mark_field_const name field)
    internal_struct_check_field(${name} ${field})
    internal_struct_append_field_raw(${name} INTERNAL_CONST_FIELDS ${field})
    bde_return(${val})
endfunction()

#[[ This was created and later removed because it adds lots of complexity
function(bde_struct_field_generator_expression retExpr name field)
    internal_struct_check_field(${name} ${field})
    bde_return("$<TARGET_PROPERTY:${name},INTERFACE_${field}>")
endfunction()
]]

function(bde_struct_check_return name expectedType callee)
    set(messagePrologue
        "${callee} failed to return a struct of type '${expectedType}':\
         returned"
    )
    if (NOT TARGET ${name})
        message(FATAL_ERROR "${messagePrologue} non-existing '${name}'.")
    endif()

    internal_struct_get_type_name(type ${name})
    while(type)
        if (type STREQUAL expectedType)
            return()
        endif()
        get_property(type GLOBAL PROPERTY ${type}_base)
    endwhile()
    internal_struct_get_description(desc ${name})
    message(FATAL_ERROR "${messagePrologue} '${desc}'.")
endfunction()
