# No include guard - may be reloaded

bde_prefixed_override(pkgconfig uor_install)
function(pkgconfig_uor_install uor listFile installOpts)
    uor_install_base(pkgconfig_uor_install ${ARGV})

    bde_struct_get_field(component ${installOpts} COMPONENT)
    bde_struct_get_field(pkgConfigInstallDir ${installOpts} PKGCONFIG_DIR)

    # Create the group.pc for the build tree
    # In CMake a list is a string with ';' as an item separator.
    find_file(bdePkgConfigFile "group.pc.in" PATHS ${CMAKE_MODULE_PATH})
    mark_as_advanced(bdePkgConfigFile)

    set(pkgConfigFile ${bdePkgConfigFile})

    bde_expand_list_file(${listFile} LISTDIR listDir FILENAME name)
    set(customPkgConfigDesc ${listDir}/${name}.pc.desc)
    if(EXISTS ${customPkgConfigDesc})
        #set(pkgConfigFile ${customPkgConfigFile})
        include(${customPkgConfigDesc})
        bde_log(VERBOSE "CUSTOM pkgconfig description from ${customPkgConfigDesc}")
    endif()

    if(NOT uor_name)
        set(uor_name ${name})
    endif()

    if(NOT uor_lib)
        set(uor_lib ${name})
    endif()

    if(NOT uor_description)
        set(uor_description "The ${name} package.")
    endif()

    # TODO: extract version from *_scm_versiontag.h
    if(NOT uor_version)
        bde_struct_get_field(versionTag ${uor} VERSION_TAG)
        set(uor_version ${versionTag})
    endif()

    bde_struct_get_field(pc_depends ${uor} DEPENDS)
    string(REPLACE ";" " " uor_pc_depends "${pc_depends}")
    configure_file(
        ${pkgConfigFile}
        "${PROJECT_BINARY_DIR}/${component}.pc"
        @ONLY
    )

    install(
        FILES "${PROJECT_BINARY_DIR}/${component}.pc"
        DESTINATION "${pkgConfigInstallDir}"
        COMPONENT "${component}-pkgconfig"
    )
endfunction()
