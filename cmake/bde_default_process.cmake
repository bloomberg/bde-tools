# Make a function with a particular name undefined
function(bde_reset_function functionName)
    set_property(GLOBAL PROPERTY BDE_RESET_FUNCTION_NAME ${functionName})
    function(${functionName})
        get_property(functionName GLOBAL PROPERTY BDE_RESET_FUNCTION_NAME)
        message(FATAL_ERROR "${functionName} was not defined.")
    endfunction()
endfunction()

function(_bde_check_info_target infoTarget name)
    bde_info_target_name(target ${infoTarget})
    if (NOT TARGET ${target})
        message(
            FATAL_ERROR
            "${name} failed to create "
            "info target (see bde_add_info_target)."
        )
    endif()
endfunction()

# Include the package cmake file if it exists.
# If it doesn't, use default processing
macro(bde_default_process fileName defaultFileName)
    bde_reset_function(process)
    if(EXISTS ${fileName})
        include(${fileName})
    else()
        include(${defaultFileName})
    endif()
    process(${ARGN})
endmacro()

# Use default processing facility for a UOR and ensure that an
# info target is created after processing
function(bde_default_process_uor outInfoTarget rootDir intermediateDir type)
    get_filename_component(entityName ${rootDir} NAME)
    set(entityFileName "${rootDir}/${intermediateDir}/${entityName}.cmake")

    bde_default_process(
        ${entityFileName}
        bde_default_process_${type}
        infoTarget
        ${entityFileName}
        ${ARGN}
    )

    _bde_check_info_target(${infoTarget} ${entityName})
    set(${outInfoTarget} ${infoTarget} PARENT_SCOPE)
endfunction()
