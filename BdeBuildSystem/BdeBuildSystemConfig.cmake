cmake_minimum_required(VERSION 3.15)

include_guard()

# Sub-modules are listed here in dependency order
include(${CMAKE_CURRENT_LIST_DIR}/BdeBuildSystemUtils.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/BdeMetadataUtils.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/BdePkgconfigUtils.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/BdeDependencyUtils.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/BdeTargetUtils.cmake)
include(${CMAKE_CURRENT_LIST_DIR}/BdeTestDriverUtils.cmake)
