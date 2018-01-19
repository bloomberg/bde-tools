# This CMakeLists.txt can be used to build a workspace containing multiple
# BDE-style repositories.


cmake_minimum_required(VERSION 3.8)

if (NOT CMAKE_MODULE_PATH)
    message(FATAL "Please specify path to BDE cmake modules.")
endif()

include(bde_utils)
file(GLOB files "*")
bde_filter_directories(workspaceDirs ${files})

project(workspace)

include(bde_project)
bde_process_workspace(
    ${workspaceDirs}
)
