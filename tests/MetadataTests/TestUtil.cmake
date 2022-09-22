cmake_minimum_required( VERSION 3.15 )

function( __test_compare_lists inList outList )
    foreach( value ${inList} )
        get_filename_component( __filename ${value} NAME )
        list( APPEND __tmp "${__filename}" )
    endforeach()

    list( SORT __tmp )
    list( SORT outList )

    if ( NOT "${__tmp}" STREQUAL "${outList}" )
        message( FATAL_ERROR "[${__tmp}] not equal [${outList}]" )
    endif()
endfunction()
