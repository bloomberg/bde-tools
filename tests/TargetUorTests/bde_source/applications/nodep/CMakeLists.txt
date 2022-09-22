find_package(ConfigureBbTarget REQUIRED)
find_package(BdeBuildSystem REQUIRED)

add_executable(nodep)
bbs_target_setup_uor(nodep)
install(TARGETS nodep
        RUNTIME DESTINATION bin )

set(testtarget nodep.td)

#if( NOT TARGET ${testtarget} )
#  message( FATAL_ERROR "Missing target: ${testtarget}" )
#endif()

# Post-install check
#find_package(ModuleTestHelpers REQUIRED)
#check_installed_files(bin/nodep)
