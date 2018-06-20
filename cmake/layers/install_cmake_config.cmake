# No include guard - may be reloaded

bde_prefixed_override(cmakeconfig uor_install)
function(cmakeconfig_uor_install uor listFile installOpts)
    uor_install_base(cmakeconfig_uor_install ${ARGV})

    bde_struct_get_field(component ${installOpts} COMPONENT)
    bde_struct_get_field(exportSet ${installOpts} EXPORT_SET)
    bde_struct_get_field(archiveInstallDir ${installOpts} ARCHIVE_DIR)

    install(
        EXPORT ${exportSet}Targets
        DESTINATION "${archiveInstallDir}/cmake"
        COMPONENT "${component}"
    )

    # Install interface targets
    bde_struct_get_field(uorInterface ${uor} INTERFACE_TARGET)
    if(uorInterface)
        bde_install_interface_target(
            ${uorInterface}
            EXPORT ${exportSet}InterfaceTargets
        )

        # Namespace is needed for disambuguation of
        # common interface target if multiple UORs built by this
        # project are used by an external project
        install(
            EXPORT ${exportSet}InterfaceTargets
            DESTINATION "${archiveInstallDir}/cmake"
            NAMESPACE "${exportSet}::"
            COMPONENT "${component}"
        )
    endif()

    # Create the groupConfig.cmake for the build tree
    find_file(bdeGroupConfigFile "groupConfig.cmake.in" PATHS ${CMAKE_MODULE_PATH})
    mark_as_advanced(bdeGroupConfigFile)
    bde_struct_get_field(group ${uor} NAME)
    bde_struct_get_field(depends ${uor} DEPENDS)
    configure_file(
        ${bdeGroupConfigFile}
        "${PROJECT_BINARY_DIR}/${group}Config.cmake"
        @ONLY
    )

    install(
        FILES "${PROJECT_BINARY_DIR}/${group}Config.cmake"
        DESTINATION "${archiveInstallDir}/cmake"
        COMPONENT "${component}"
    )
endfunction()

bde_prefixed_override(cmakeconfig package_install)
function(cmakeconfig_package_install package listFile installOpts)
    package_install_base(cmakeconfig_package_install ${ARGV})

    bde_struct_get_field(exportSet ${installOpts} EXPORT_SET)
    bde_struct_get_field(includeInstallDir ${installOpts} INCLUDE_DIR)

    bde_struct_get_field(packageInterface ${package} INTERFACE_TARGET)
    bde_interface_target_include_directories(
        ${packageInterface}
        PUBLIC
            $<INSTALL_INTERFACE:${includeInstallDir}>
    )

    # Install interface targets
    bde_install_interface_target(
        ${packageInterface}
        EXPORT ${exportSet}InterfaceTargets
    )
endfunction()
