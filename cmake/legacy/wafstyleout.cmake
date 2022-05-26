if(WAFSTYLEOUT_INCLUDED)
    return()
endif()
set(WAFSTYLEOUT_INCLUDED true)

find_package(Python3)

function(internal_setup_wafstyleout)
    set(absolutePyFilename ${CMAKE_CURRENT_LIST_DIR}/wafstyleout.py)
    set_property(GLOBAL PROPERTY WAFSTYLEOUT_PATH "${absolutePyFilename}")
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "${Python3_EXECUTABLE} ${absolutePyFilename}")
    set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "${Python3_EXECUTABLE} ${absolutePyFilename}")
    # The compiler/linker launchers need a string
    set_property(GLOBAL PROPERTY BDE_RULE_LAUNCH_TEST ${Python3_EXECUTABLE} ${absolutePyFilename})
    # The test launcher needs a list
endfunction()

option(BDE_USE_WAFSTYLEOUT "Use waf-style output wrapper" OFF)
if (BDE_USE_WAFSTYLEOUT)
    internal_setup_wafstyleout() # Call immediately for correctness of ${CMAKE_CURRENT_LIST_DIR}
endif()
