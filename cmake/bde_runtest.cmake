if(BDE_RUNTEST_INCLUDED)
    return()
endif()
set(BDE_RUNTEST_INCLUDED true)

find_package(Python3)

function(internal_setup_bde_test_runner)
    get_filename_component(dir ${CMAKE_CURRENT_LIST_DIR} DIRECTORY)
    set_property(GLOBAL PROPERTY BDE_RUNTEST_COMMAND ${Python_EXECUTABLE} ${dir}/bin/bde_runtest.py)
endfunction()
internal_setup_bde_test_runner() # Call immediately for correctness of ${CMAKE_CURRENT_LIST_DIR}

function(get_bde_test_runner val)
    get_property(prop GLOBAL PROPERTY BDE_RUNTEST_COMMAND)
    get_property(commandWrapper GLOBAL PROPERTY BDE_RULE_LAUNCH_TEST)
    set(${val} ${commandWrapper} ${prop} PARENT_SCOPE)
endfunction()
