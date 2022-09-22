find_package( ConfigureBbTarget REQUIRED )
find_package( BdeBuildSystem REQUIRED )

add_executable(xyzwithlib)
bbs_target_setup_uor(xyzwithlib)
install(TARGETS xyzwithlib
        RUNTIME DESTINATION bin )

set(testtarget xyzwithlib.td)
set(expected_deps "m_xyzwithlib_component.td")

#if( NOT TARGET ${testtarget} )
#  message( FATAL_ERROR "Missing target: ${testtarget}" )
#endif()

# Post-install check
#find_package(ModuleTestHelpers REQUIRED)
#check_installed_files(bin/xyzwithlib)
