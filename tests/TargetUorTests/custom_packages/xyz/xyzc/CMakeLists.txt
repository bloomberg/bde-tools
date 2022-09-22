find_package(BdeBuildSystem REQUIRED)

set(package xyzc)
bbs_read_package_metadata(${CMAKE_CURRENT_SOURCE_DIR} ${package})

message(VERBOSE "Creating OBJECT library for package: ${package}")
add_library(${package} OBJECT)
target_compile_definitions(${package} PRIVATE xyz_FOO)
