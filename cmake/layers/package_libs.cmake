# No include guard - may be reloaded

include(bde_package_libraries)

bde_prefixed_override(packagelibs process_package)
function(packagelibs_process_package retPackage listFile installOpts)
    process_package_base(packagelibs_process_package package ${listFile} ${installOpts})
    bde_process_dependencies(${package} ${listFile} NO_LINK)
        # These are always only interpackage dependencies.
        # Don't link them into the interface - we'll link them into
        # the target directly - this helps with exporting CMake targets.
    bde_package_create_target(${package})
    bde_return(${package})
endfunction()

bde_prefixed_override(packagelibs package_initialize)
function(packagelibs_package_initialize retPackage packageName)
    bde_assert_no_extra_args()

    bde_create_struct_with_interfaces(package BDE_PACKAGELIBS_PACKAGE_TYPE NAME ${packageName})
    bde_return(${package})
endfunction()

bde_prefixed_override(packagelibs package_group_setup_test_interface)
function(packagelibs_package_group_setup_test_interface group listFile)
    bde_assert_no_extra_args()
    bde_process_test_dependencies(${group} ${listFile})
    bde_create_uor_test_metatarget(${group})

    # Do not link package group target to the tests
endfunction()

bde_prefixed_override(packagelibs process_package_group)
function(packagelibs_process_package_group retUor listFile installOpts)
    process_package_group_base(packagelibs_process_package_group uor ${listFile} ${installOpts})

    # Detect missing interpackage dependencies
    bde_struct_get_field(packages ${uor} PACKAGES)
    bde_struct_get_field(uorName ${uor} NAME)

    set(allInterpackageDeps)
    set(allPackageTargets)

    foreach(package IN LISTS packages)
        # Add depends and target for missing interpackage dependency detection
        bde_struct_get_field(interpackageDeps ${package} DEPENDS)
        list(APPEND allInterpackageDeps ${interpackageDeps})
        bde_struct_get_field(packageTarget ${package} TARGET)
        list(APPEND allPackageTargets ${packageTarget})
    endforeach()

    if(allInterpackageDeps)
        list(REMOVE_ITEM allInterpackageDeps ${allPackageTargets})
        if(allInterpackageDeps)
            list(REMOVE_DUPLICATES allInterpackageDeps)
            message(
                FATAL_ERROR
                "[${uorName}] Found unresolved inter-package dependencies: \
                ${allInterpackageDeps}"
            )
        endif()
    endif()

    bde_return(${uor})
endfunction()
