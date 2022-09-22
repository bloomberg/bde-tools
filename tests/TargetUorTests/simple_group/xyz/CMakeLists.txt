find_package(BdeBuildSystem REQUIRED)

# Group level CML

add_library(xyz STATIC)
bbs_target_setup_uor(xyz)
target_compile_definitions(xyzb PRIVATE xyzb_BAR)

set(testtarget xyz.td)

#if(NOT TARGET ${testtarget})
#  message(FATAL_ERROR "Missing target: ${testtarget}")
#endif()

# Post-install check

#find_package(ModuleTestHelpers REQUIRED)
#check_installed_files(include/xyza_component.h
#                      "${CMAKE_INSTALL_LIBDIR}/libxyz.a"
#                      "${CMAKE_INSTALL_LIBDIR}/pkgconfig/xyz.pc")
