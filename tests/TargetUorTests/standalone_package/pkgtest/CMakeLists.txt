find_package(BdeBuildSystem REQUIRED)

set(package pkgtest)
add_library(${package})
bbs_target_setup_uor(${package})
