## bde_application.cmake

include(bde_include_guard)
bde_include_guard()

include(bde_package)
include(bde_standalone)
include(bde_struct)
include(bde_utils)
include(bde_uor)

# Install an application target.
function(bde_application_install_target uor listFile installOpts)
    bde_assert_no_extra_args()

    bde_struct_get_field(uorTarget ${uor} TARGET)
    bde_struct_get_field(component ${installOpts} COMPONENT)
    bde_struct_get_field(execInstallDir ${installOpts} EXECUTABLE_DIR)

    # Install main target
    install(
        TARGETS ${uorTarget}
        COMPONENT "${component}"
        RUNTIME DESTINATION ${execInstallDir}
    )

    bde_add_component_install_target(${component} ${uorTarget})
endfunction()

function(bde_application_create_main_package retPackage listFile)
    # Find potential application main files
    bde_expand_list_file(${listFile} FILENAME appName ROOTDIR rootDir)
    string(REGEX REPLACE "(m_)?(.+)" "\\2" appSrcName ${appName})

    foreach(mainFile ${appSrcName} ${appName})
        bde_utils_find_file_extension(file ${rootDir}/${mainFile}.m ".cpp;.c")
        list(APPEND mainFiles ${file})
    endforeach()

    if(mainFiles)
        package_initialize(package ${appName}-main)
        list(REMOVE_DUPLICATES mainFiles)
        bde_struct_set_field(${package} SOURCES ${mainFiles})
    else()
        message(FATAL_ERROR "Cannot find ${appName}'s .m.cpp file.")
    endif()

    bde_return(${package})
endfunction()

function(bde_application_process_packages uor listFile installOpts)
    bde_create_standalone_package(standalonePkg ${listFile} "")
    bde_uor_use_package(${uor} ${standalonePkg})

    bde_application_create_main_package(applicationPkg ${listFile})
    bde_uor_use_package(${uor} ${applicationPkg})
endfunction()
