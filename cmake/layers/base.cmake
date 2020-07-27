include(bde_include_guard)
bde_include_guard()

# component
include(bde_component)

function(base_process_component retComponent rootDir componentName)
    bde_assert_no_extra_args()

    component_initialize(component ${componentName})
    component_find_sources(${component} ${rootDir})
    component_find_tests(${component} ${rootDir})

    bde_return(${component})
endfunction()

bde_create_virtual_function(component_initialize bde_component_initialize)
bde_create_virtual_function(component_find_sources bde_component_find_sources)
bde_create_virtual_function(component_find_tests bde_component_find_tests)
#Hack to fix bus builds. the above virtual function must be used in the code.
bde_create_virtual_function(component_find_test bde_component_find_tests)
bde_create_virtual_function(process_component base_process_component)

# package
include(bde_package)

function(base_process_package retPackage listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} FILENAME pkgName)
    package_initialize(package ${pkgName})
    package_process_components(${package} ${listFile})
    package_setup_interface(${package} ${listFile})
    package_setup_test_interface(${package} ${listFile})
    package_install(${package} ${listFile} ${installOpts})

    bde_return(${package})
endfunction()

bde_create_virtual_function(package_initialize bde_package_initialize)
bde_create_virtual_function(package_process_components bde_package_process_components)
bde_create_virtual_function(package_setup_interface bde_package_setup_interface)
bde_create_virtual_function(package_setup_test_interface bde_package_setup_test_interface)
bde_create_virtual_function(package_install bde_package_install)
bde_create_virtual_function(process_package base_process_package)

# common UOR functions
function(none)
endfunction()
bde_create_virtual_function(uor_set_version none)
bde_create_virtual_function(uor_setup_interface none)
bde_create_virtual_function(uor_setup_test_interface none)
bde_create_virtual_function(uor_install bde_uor_install_target)

# package_group
include(bde_package_group)

function(base_process_package_group retPackageGroup listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} FILENAME groupName)
    package_group_initialize(uor ${groupName})
    package_group_set_version(${uor} ${listFile})
    package_group_process_packages(${uor} ${listFile} ${installOpts})
    package_group_setup_interface(${uor} ${listFile})
    package_group_setup_test_interface(${uor} ${listFile})
    package_group_install(${uor} ${listFile} ${installOpts})
    package_group_install_meta(${uor} ${listFile} ${installOpts})

    bde_return(${uor})
endfunction()

bde_create_virtual_function(package_group_initialize bde_uor_initialize_library)
bde_create_virtual_function(package_group_set_version bde_package_group_set_version)
bde_create_virtual_function(package_group_process_packages bde_package_group_process_packages)
bde_create_virtual_function(package_group_setup_interface bde_package_group_setup_interface)
bde_create_virtual_function(package_group_setup_test_interface bde_package_group_setup_test_interface)
bde_create_virtual_function(package_group_install uor_install)
bde_create_virtual_function(package_group_install_meta bde_package_group_install_meta)
bde_create_virtual_function(process_package_group base_process_package_group)

# standalone
include(bde_standalone)

function(base_process_standalone_package retPackageGroup listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} FILENAME pkgName)
    standalone_package_initialize(uor ${pkgName})
    standalone_package_process_packages(${uor} ${listFile} ${installOpts})
    standalone_package_setup_interface(${uor} ${listFile})
    standalone_package_setup_test_interface(${uor} ${listFile})
    standalone_package_install(${uor} ${listFile} ${installOpts})

    bde_return(${uor})
endfunction()

bde_create_virtual_function(standalone_package_initialize bde_uor_initialize_library)
bde_create_virtual_function(standalone_package_process_packages bde_standalone_package_process_packages)
bde_create_virtual_function(standalone_package_setup_interface bde_standalone_setup_interface)
bde_create_virtual_function(standalone_package_setup_test_interface bde_standalone_setup_test_interface)
bde_create_virtual_function(standalone_package_install uor_install)
bde_create_virtual_function(process_standalone_package base_process_standalone_package)

# application
include(bde_application)

function(base_process_application retPackageGroup listFile installOpts)
    bde_assert_no_extra_args()

    bde_expand_list_file(${listFile} FILENAME appName)
    application_initialize(uor ${appName})
    application_process_packages(${uor} ${listFile} ${installOpts})
    application_setup_interface(${uor} ${listFile})
    application_setup_test_interface(${uor} ${listFile})
    application_install(${uor} ${listFile} ${installOpts})

    bde_return(${uor})
endfunction()

bde_create_virtual_function(application_initialize bde_uor_initialize_application)
bde_create_virtual_function(application_process_packages bde_application_process_packages)
bde_create_virtual_function(application_setup_interface bde_standalone_setup_interface)
bde_create_virtual_function(application_setup_test_interface bde_standalone_setup_test_interface)
bde_create_virtual_function(application_install bde_application_install_target)
bde_create_virtual_function(process_application base_process_application)

# project
include(bde_project)

function(base_process_project retProject listDir)
    bde_assert_no_extra_args()

    get_filename_component(projName ${listDir} NAME)
    project_initialize(proj ${projName})
    project_setup_install_opts(${proj})
    project_process_uors(${proj} ${listDir})

    bde_return(${proj})
endfunction()

bde_create_virtual_function(project_initialize bde_project_initialize)
bde_create_virtual_function(project_setup_install_opts bde_project_setup_install_opts)
bde_create_virtual_function(project_process_uors bde_project_process_uors)
bde_create_virtual_function(process_project base_process_project)
