include_guard()

function(bbs_emit_pkgconfig_file)
    set(singleValueArgs TARGET PKG VERSION PREFIX LIBDIR INCLUDEDIR COMPONENT)
    set(multiValueArgs DEPS UOR_DEPS OPTIONS)
    cmake_parse_arguments(args "" "${singleValueArgs}" "${multiValueArgs}" ${ARGN})

    if ( (NOT args_PKG) AND (NOT args_TARGET) )
        message(FATAL_ERROR "You need to supply PKG or TARGET to bbs_emit_pkgconfig_file")
    endif()

    if ( args_PKG AND args_TARGET )
        message(FATAL_ERROR "You can only specify one of PKG or TARGET to bbs_emit_pkgconfig_file")
    endif()

    if (NOT args_LIBDIR AND NOT CMAKE_INSTALL_LIBDIR)
        message(FATAL_ERROR "You need to supply LIBDIR to bbs_emit_pc_files or set CMAKE_INSTALL_LIBDIR")
    endif()

    if ( args_PKG )

        bbs_uor_to_pc_name( ${args_PKG} PC_NAME )
        bbs_pc_to_uor_name( ${args_PKG} TARGET_NAME )

        # note deps and uor_deps now work the same
        # we always normalize to the pc name
        if (args_DEPS)
            foreach( dep ${args_DEPS} )
                bbs_uor_to_pc_name( ${dep} ${dep}_PC )
                if( ${${dep}_PC} MATCHES "(^.*([:][:]).*$)" )
                    message(WARNING "Ignoring ${${dep}_PC} when generating ${args_PKG}.pc since it is unclear what pkg-config package supplies that dependency.")
                else()
                    list( APPEND pcDeps ${${dep}_PC} )
                endif()
            endforeach()
        endif(args_DEPS)

        if (args_UOR_DEPS)
            foreach( dep ${args_UOR_DEPS} )
                bbs_uor_to_pc_name( ${dep} ${dep}_PC )
                if( ${${dep}_PC} MATCHES "(^.*([:][:]).*$)" )
                    message(WARNING "Ignoring ${${dep}_PC} when generating ${args_PKG}.pc since it is unclear what pkg-config package supplies that dependency.")
                else()
                    list( APPEND pcDeps ${${dep}_PC} )
                endif()
            endforeach()
        endif(args_UOR_DEPS)

        string (REPLACE ";" " " my_OPTIONS "${args_OPTIONS}")
        set(PKG_OPTIONS "${my_OPTIONS}")

    else()

        get_property( TARGET_NAME TARGET ${args_TARGET} PROPERTY NAME  )
        bbs_uor_to_pc_name( ${TARGET_NAME} PC_NAME )

        get_property( UOR_LINK_LIBRARIES
                      TARGET ${args_TARGET}
                      PROPERTY LINK_LIBRARIES )

        foreach( l ${UOR_LINK_LIBRARIES} )
            if ( BB_${l}_HAS_NO_PKGCONFIG )
                message( STATUS "not adding ${l} to ${args_TARGET}.pc file" )
            elseif(${l} MATCHES "^-l.*")
                message(TRACE "adding ${l} to ${args_TARGET}.pc Libs instead of Requires")
                set(PKG_LIBS "${PKG_LIBS} ${l}")
            else()
                set(target_type "")
                if(TARGET ${l})
                    get_target_property(target_type ${l} TYPE)
                endif()

                if(NOT target_type STREQUAL "OBJECT_LIBRARY")
                    bbs_uor_to_pc_name(${l} pcname)
                    list( APPEND pcDeps ${pcname} )
                endif()
            endif()
        endforeach(l)

        get_property( INTERFACE_COMPILE_DEFINITIONS
                      TARGET ${args_TARGET}
                      PROPERTY INTERFACE_COMPILE_DEFINITIONS )
        foreach( d ${INTERFACE_COMPILE_DEFINITIONS} )
            string(APPEND PKG_OPTIONS " -D${d}")
        endforeach(d)

        get_property( INTERFACE_COMPILE_OPTIONS
                      TARGET ${args_TARGET}
                      PROPERTY INTERFACE_COMPILE_OPTIONS )
        foreach( o ${INTERFACE_COMPILE_OPTIONS} )
           string(APPEND PKG_OPTIONS " ${o}")
        endforeach(o)

    endif()

    set(PKG_DESCRIPTION ${TARGET_NAME})

    if (args_VERSION)
        set(PKG_VERSION "${args_VERSION}")
    else(args_VERSION)
        set(PKG_VERSION "0.0.0")
    endif(args_VERSION)

    if (args_PREFIX)
        set(PKG_PREFIX "${args_PREFIX}")
    else(args_PREFIX)
        set(PKG_PREFIX "${CMAKE_INSTALL_PREFIX}")
    endif(args_PREFIX)

    list(REMOVE_DUPLICATES pcDeps)
    string( REPLACE ";" " "  my_REQUIRES "${pcDeps}" )
    set(PKG_REQUIRES "${PKG_REQUIRES} ${my_REQUIRES}")

    if (args_LIBDIR)
        set(PKG_LIBDIR "${args_LIBDIR}")
    else(args_LIBDIR)
        set(PKG_LIBDIR "${CMAKE_INSTALL_LIBDIR}")
    endif(args_LIBDIR)

    if (args_INCLUDEDIR)
        set(PKG_INCLUDEDIR "${args_INCLUDEDIR}")
    else(args_INCLUDEDIR)
        set(PKG_INCLUDEDIR "include")
    endif(args_INCLUDEDIR)

    # setup the install rule for this metadata
    if(args_COMPONENT)
        set(_COMPONENT "${args_COMPONENT}")
    else(args_COMPONENT)
        set(_COMPONENT "${CMAKE_INSTALL_DEFAULT_COMPONENT_NAME}")
    endif(args_COMPONENT)

    configure_file(${BdeBuildSystem_DIR}/support/template.pc.in
        "${CMAKE_CURRENT_BINARY_DIR}/${PC_NAME}.pc"
        @ONLY
    )
    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/${PC_NAME}.pc"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
        COMPONENT "${_COMPONENT}-pkgconfig"
    )
    install(
        FILES "${CMAKE_CURRENT_BINARY_DIR}/${PC_NAME}.pc"
        DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
        COMPONENT "${_COMPONENT}-all"
    )
endfunction()
