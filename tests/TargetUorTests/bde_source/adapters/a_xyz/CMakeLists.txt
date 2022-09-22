find_package(BdeBuildSystem REQUIRED)

add_library(a_xyz STATIC)
bbs_target_setup_uor(a_xyz)

set(testtarget a_xyz.td)

#if( NOT TARGET ${testtarget} )
#  message( FATAL_ERROR "Missing target: ${testtarget}" )
#endif()

# Post-install check

#find_package(ModuleTestHelpers REQUIRED)
#check_installed_files(include/a_xyz_component.h
#                      "${CMAKE_INSTALL_LIBDIR}/liba_xyz.a"
#                      "${CMAKE_INSTALL_LIBDIR}/pkgconfig/a-xyz.pc")
