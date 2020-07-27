include(bde_include_guard)
bde_include_guard()

include(bde_log)

function(bde_load_local_customization fileName)
    bde_assert_no_extra_args()

    bde_record_overrides()
    if(EXISTS ${fileName})
        bde_log(VERBOSE "    CUSTOM processing from ${fileName}")
        include(${fileName})
    else()
        bde_log(VERY_VERBOSE "    Default processing for ${fileName}")
    endif()
endfunction()

macro(bde_cleanup_local_customization)
    bde_remove_recorded_overrides()
endmacro()

function(bde_record_overrides)
    bde_assert_no_extra_args()

    get_property(uniqueIdx GLOBAL PROPERTY BDE_RECORD_OVERRIDE_IDX)
    if(NOT uniqueIdx)
        set(uniqueIdx 1)
    else()
        math(EXPR uniqueIdx "${uniqueIdx} + 1")
    endif()
    set_property(GLOBAL PROPERTY BDE_RECORD_OVERRIDE_IDX ${uniqueIdx})

    set_property(GLOBAL APPEND PROPERTY BDE_RECORD_VAR_STACK "bde_overrides_${uniqueIdx}")
endfunction()

function(bde_remove_recorded_overrides)
    bde_assert_no_extra_args()

    get_property(stack GLOBAL PROPERTY BDE_RECORD_VAR_STACK)
    list(LENGTH stack idx)
    math(EXPR idx "${idx} - 1")
    list(GET stack ${idx} recordVar)
    list(REMOVE_AT stack ${idx})
    set_property(GLOBAL PROPERTY BDE_RECORD_VAR_STACK ${stack})

    get_property(overrides GLOBAL PROPERTY ${recordVar})
    foreach(override IN LISTS overrides)
        string(REPLACE "^" ";" fnInfo ${override})
        list(GET fnInfo 0 fnName)
        list(GET fnInfo 1 overridingFnName)
        bde_remove_override(${fnName} ${overridingFnName})
    endforeach()
    set_property(GLOBAL PROPERTY ${recordVar} "")
endfunction()


function(internal_get_prologue ret fnName)
    set(${ret}
"macro(${fnName}_base curFn)\n\
    if(\"\${curFn}\" STREQUAL \"__head__\")\n"
    PARENT_SCOPE)
endfunction()

function(internal_get_override_block ret fnName overridingFnName)
    set(${ret}
"        ${overridingFnName}(\${ARGN})\n\
    elseif(\"\${curFn}\" STREQUAL \"${overridingFnName}\" OR \"\${curFn}\" STREQUAL \"\")\n"
    PARENT_SCOPE)
endfunction()

function(internal_vtbl_file retFileName fnName)
    bde_assert_no_extra_args()
    bde_return("${CMAKE_BINARY_DIR}/${fnName}.vtbl.cmake")
endfunction()

function(bde_create_virtual_function fnName baseFnName)
    bde_assert_no_extra_args()
    internal_vtbl_file(fileName ${fnName})
    internal_get_prologue(prologue ${fnName})
    file(WRITE ${fileName}
"${prologue}\
        ${baseFnName}(\${ARGN})\n\
    else()\n\
       message(FATAL_ERROR \"\${curFn} does not override ${fnName}\")\n\
    endif()\n\
endmacro()\n\
macro(${fnName})\n\
    ${fnName}_base(__head__ \${ARGN})\n\
endmacro()"
    )
    include(${fileName})
endfunction()

function(bde_override fnName overridingFnName)
    bde_assert_no_extra_args()
    internal_vtbl_file(fileName ${fnName})
    file(READ ${fileName} content)

    string(FIND ${content} ${overridingFnName} pos)
    if(pos GREATER_EQUAL 0)
        message(FATAL_ERROR "${overridingFnName} has already been defined as override of ${fnName}")
    endif()

    internal_get_prologue(prologue ${fnName})
    internal_get_override_block(overrideBlock ${fnName} ${overridingFnName})
    string(REPLACE
        ${prologue}
        "${prologue}${overrideBlock}"
        content
        "${content}"
    )
    file(WRITE ${fileName} ${content})
    include(${fileName})

    get_property(stack GLOBAL PROPERTY BDE_RECORD_VAR_STACK)
    list(LENGTH stack idx)
    math(EXPR idx "${idx} - 1")
    list(GET stack ${idx} recordVar)
    set_property(GLOBAL APPEND PROPERTY ${recordVar} "${fnName}^${overridingFnName}")
endfunction()

function(bde_remove_override fnName overridingFnName)
    bde_assert_no_extra_args()
    internal_vtbl_file(fileName ${fnName})
    file(READ ${fileName} content)

    internal_get_override_block(overrideBlock ${fnName} ${overridingFnName})
    string(REPLACE
        ${overrideBlock}
        ""
        content
        "${content}"
    )
    file(WRITE ${fileName} ${content})
    include(${fileName})
endfunction()

# Convenience functions
macro(bde_prefixed_override uniquePrefix fn)

    # Hack to change interface name "component_find_test" to "component_find_tests"
    if("${fn}" STREQUAL "component_find_test")
        bde_override("${fn}s" "${uniquePrefix}_${fn}")
    else()
        bde_override(${fn} ${uniquePrefix}_${fn})
    endif()
endmacro()
