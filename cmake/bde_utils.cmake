## bde_utils.cmake
## ---------------
#
#  This CMake module exposes a set of generic macros and functions providing
#  convenience utility.
#
## OVERVIEW
## --------
# o bde_utils_add_meta_file: parse content of the metadata file.
# o bde_utils_track_file:    track file changes to trigger a reconfiguration.
#
## ========================================================================= ##

if(BDE_UTILS_INCLUDED)
  return()
endif()
set(BDE_UTILS_INCLUDED true)

# :: bde_utils_add_meta_file ::
# -----------------------------------------------------------------------------
# Read the content of 'file' and store each token from it in the specified
# 'out' list.
#
# File is processed with respect to the following expected syntax:
#   o '#' with following text till the end of line is ignored
#   o ' ' is considered a token separator for splitting out multiple items from
#     a single line
#
## PARAMETERS
## ----------
# This function takes one optional parameter: 'TRACK'.  The 'file's content
# changes are not tracked by the build system unless 'TRACK' is specified.
#
## EXAMPLE
## -------
# If the 'file' contains the following:
#    a
#    b c d
#    # Comment
#    e # Comment
# The result will be: a;b;c;d;e
function(bde_utils_add_meta_file file out)
    # Parameters parse
    #   One optional parameter: TRACK
    cmake_parse_arguments(args "TRACK" "" "" ${ARGN})

    # Read all lines from 'file', ignoring the ones starting with '#'
    file(STRINGS "${file}" lines REGEX "^[^#].*")

    set(tmp)

    # For each line, split at ' '
    foreach(line ${lines})
        # Remove comment
        string(REGEX REPLACE " *#.*$" "" line ${line})

        # In CMake a list is a string with ';' as an item separator.
        string(REGEX REPLACE " " ";" line ${line})

        if(NOT "${line}" STREQUAL "")
            list(APPEND tmp ${line})
        endif()
    endforeach()

    # Set the result
    set(${out} ${tmp} PARENT_SCOPE)

    # Track file for changes if told so.
    if(args_TRACK)
        bde_utils_track_file(${file})
    endif()
endfunction()

# :: bde_utils_track_file ::
# -----------------------------------------------------------------------------
# This function adds the specified 'file' to a set of generator dependancies
# forcing the reconfiguration of the file content changes.  This function is
# used to track changes in the .mem and .dep files.

# We copy the file to a directory under the current build directory; and by
# CMake's 'configure_file' contract, if the content has changed, this will
# trigger a 'rebuild_cache'.
#
## NOTE
## ----
# The monitored file is copied under a '.track/' directory in the current
# binary directory. Because we would only copy the file and lose the full path,
# potentially leading to silent collisions, the copied files name correspond to
# the first 10 characters of the SHA1 of the absolute path of the input 'file'.
function( bde_utils_track_file file )
    # Get the real path to the file
    get_filename_component(realPath ${file} REALPATH)

    # Compute the SHA-1
    string(SHA1 sha ${realPath})

    # Keep the first ten characters
    string(SUBSTRING ${sha} 0 10 shortSha)

    # configure_file
    configure_file(
        ${file}
        "${CMAKE_CURRENT_BINARY_DIR}/.track/${shortSha}"
        COPYONLY
    )
endfunction()


function(bde_list_template_substitute output placeholder template)
    set(out)
    foreach(target ${ARGN})
        string(REPLACE ${placeholder} ${target} elem ${template})
        list(APPEND out ${elem})
    endforeach()
    set(${output} ${out} PARENT_SCOPE)
endfunction()

function(bde_filter_directories output)
    set(out)
    foreach(f ${ARGN})
        if(IS_DIRECTORY ${f})
            list(APPEND out ${f})
        endif()
    endforeach()
    set(${output} ${out} PARENT_SCOPE)
endfunction()
