if(WAFSTYLEOUT_INCLUDED)
    return()
endif()
set(WAFSTYLEOUT_INCLUDED true)

function(internal_setup_wafstyleout)
    set(absolutePyFilename ${CMAKE_CURRENT_LIST_DIR}/wafstyleout.py)
    set_property(GLOBAL PROPERTY RULE_LAUNCH_COMPILE "python ${absolutePyFilename}")
    set_property(GLOBAL PROPERTY RULE_LAUNCH_LINK "python ${absolutePyFilename}")
        # The compiler/linker launchers need a string
    set_property(GLOBAL PROPERTY BDE_RULE_LAUNCH_TEST python ${absolutePyFilename})
        # The test launcher needs a list
endfunction()
internal_setup_wafstyleout() # Call immediately for correctness of ${CMAKE_CURRENT_LIST_DIR}
