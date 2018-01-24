if(BDE_PROCESS_WITH_DEFAULT_INCLUDED)
    return()
endif()
set(BDE_PROCESS_WITH_DEFAULT_INCLUDED true)

# Make a function with a particular name undefined
function(bde_reset_function functionName)
    set_property(GLOBAL PROPERTY BDE_RESET_FUNCTION_NAME ${functionName})
    function(${functionName})
        get_property(functionName GLOBAL PROPERTY BDE_RESET_FUNCTION_NAME)
        message(FATAL_ERROR "${functionName} was not defined.")
    endfunction()
endfunction()

# Include the package cmake file if it exists.
# If it doesn't, use default processing
macro(bde_process_with_default fileName defaultFileName)
    # macro because it's impossible to know which parameters are 'output'
    bde_reset_function(process)
    if(EXISTS ${fileName})
        include(${fileName})
    else()
        include(${defaultFileName})
    endif()
    process(${ARGN})
    bde_reset_function(process)
endmacro()