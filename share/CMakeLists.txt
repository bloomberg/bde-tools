# This CMakeLists.txt can be used to build a workspace containing multiple
# BDE-style repositories.

cmake_minimum_required(VERSION 3.10)

if (NOT CMAKE_MODULE_PATH)
    message(FATAL_ERROR "Please specify path to BDE cmake modules.")
endif()

project(workspace)

include(bde_utils)
include(bde_workspace)

file(GLOB files "*")
bde_utils_filter_directories(workspaceDirs ${files})

bde_process_workspace(
    ${workspaceDirs}
)
