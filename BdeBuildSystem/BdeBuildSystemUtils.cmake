include_guard()

# :: bbs_assert_no_extra_args ::
# -----------------------------------------------------------------------------
# This macro verifies that no extra arguments were passed to the surrounding
# function.
macro(bbs_assert_no_extra_args)
    if (ARGN)
        # This 'conversion' is required to use the ARGN actually passed
        # to the surrounding function and not the macro itself
        set(args)
        foreach (var IN LISTS ARGN)
            list(APPEND args ${var})
        endforeach()

        message(FATAL_ERROR "Unexpected extra arguments passed to function: ${args}")

    endif()
endmacro()

# :: bbs_assert_no_unparsed_args ::
# -----------------------------------------------------------------------------
# This macro verifies that no unparsed arguments were passed to the surrounding
# function.
macro(bbs_assert_no_unparsed_args prefix)
    if (${prefix}_UNPARSED_ARGUMENTS)
        message(FATAL_ERROR "Unrecognized arguments: ${${prefix}_UNPARSED_ARGUMENTS}.")
    endif()
endmacro()

# :: bbs_track_file ::
# -----------------------------------------------------------------------------
# This function adds the specified 'file' to a set of generator dependencies
# forcing the reconfiguration of the file content changes.  This function is
# used to track changes in the .mem and .dep files.
function(bbs_track_file file)
    bbs_assert_no_extra_args()
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS ${file})
endfunction()

function(bbs_build_tests_with_all)
    if (NOT TARGET all.t)
        add_custom_target(all.t ALL)
    endif()
endfunction()
