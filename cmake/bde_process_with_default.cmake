if(BDE_PROCESS_WITH_DEFAULT_INCLUDED)
    return()
endif()
set(BDE_PROCESS_WITH_DEFAULT_INCLUDED true)

include(bde_log)

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
        bde_log(VERBOSE "    Using CUSTOM processing from ${fileName}")
        include(${fileName})
    else()
        bde_log(VERY_VERBOSE "    Default processing for ${fileName}")
        include(${defaultFileName})
    endif()
    process(${ARGN})
    bde_reset_function(process)
endmacro()

# Define macros that force use the default processing
macro(internal_force_default_process type)
    bde_process_with_default("" defaults/bde_process_${type} ${ARGN})
endmacro()

macro(bde_force_default_process_package)
    internal_force_default_process(package ${ARGN})
endmacro()

macro(bde_force_default_process_package_group)
    internal_force_default_process(package_group ${ARGN})
endmacro()

macro(bde_force_default_process_standalone_package)
    internal_force_default_process(standalone_package ${ARGN})
endmacro()

macro(bde_force_default_process_application)
    internal_force_default_process(application ${ARGN})
endmacro()

macro(bde_force_default_process_project)
    internal_force_default_process(project ${ARGN})
endmacro()