find_package(BdeBuildSystem REQUIRED)

add_library(a_nodep STATIC)
bbs_target_setup_uor(a_nodep)

set(testtarget a_nodep.td)

#if( NOT TARGET ${testtarget} )
#  message( FATAL_ERROR "Missing target: ${testtarget}" )
#endif()

# Post-install check

#find_package(ModuleTestHelpers REQUIRED)
#check_installed_files("${CMAKE_INSTALL_LIBDIR}/liba_nodep.a"
#                      "${CMAKE_INSTALL_LIBDIR}/pkgconfig/a-nodep.pc")
