include(bde_include_guard)
bde_include_guard()

include(bde_log)
include(bde_package)
include(bde_package_libraries)
include(bde_uor)
include(bde_utils)

function(bde_create_standalone_package retPackage listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} FILENAME pkgName)
    bde_create_struct_with_interfaces(package BDE_PACKAGELIBS_PACKAGE_TYPE
                                      NAME ${pkgName}-pkg)
        # Replace the name to avoid clashes
        # This also ignores .dep - those are uor depends, not interpackage depends

    package_process_components(${package} ${listFile})
    package_setup_interface(${package} ${listFile})
    package_setup_test_interface(${package} ${listFile})
    if(installOpts)
        package_install(${package} ${listFile} ${installOpts})
    endif()
    bde_package_create_target(${package})

    bde_return(${package})
endfunction()

function(bde_standalone_package_process_packages uor listFile installOpts)
    bde_create_standalone_package(standalonePkg ${listFile} ${installOpts})
    bde_uor_use_package(${uor} ${standalonePkg})
endfunction()

function(bde_standalone_setup_interface uor listFile)
    uor_setup_interface(${uor} ${listFile})
    bde_process_dependencies(${uor} ${listFile})
endfunction()

function(bde_standalone_setup_test_interface uor listFile)
    bde_process_test_dependencies(${uor} ${listFile})
    bde_create_uor_test_metatarget(${uor})
endfunction()
