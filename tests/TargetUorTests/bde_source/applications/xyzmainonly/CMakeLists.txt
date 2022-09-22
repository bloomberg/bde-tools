find_package(BdeBuildSystem REQUIRED)

add_executable(xyzmainonly)
bbs_target_setup_uor(xyzmainonly)
install(TARGETS xyzmainonly
        RUNTIME DESTINATION bin)

# Post-install check
find_package(ModuleTestHelpers REQUIRED)
check_installed_files(bin/xyzmainonly)
