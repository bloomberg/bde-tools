# This CMakeLists.txt can be used to build a workspace containing multiple
# BDE-style repositories.

cmake_minimum_required(VERSION 3.24)
project(workspace)

# BDE build system selector
if (BBS_BUILD_SYSTEM)
    enable_testing()

    find_package(BdeBuildSystem REQUIRED)

    file(GLOB files "${CMAKE_CURRENT_LIST_DIR}/*")
    foreach(f ${files})
        if (IS_DIRECTORY ${f} AND EXISTS ${f}/CMakeLists.txt)
            message(STATUS "Adding folder ${f} to workspace")
            add_subdirectory(${f})
        endif()
    endforeach()

    # Add here further repositories needed
else()

    if (NOT CMAKE_MODULE_PATH)
        message(FATAL_ERROR "Please specify path to BDE cmake modules.")
    endif()

    include(bde_utils)
    include(bde_workspace)

    file(GLOB files "*")
    bde_utils_filter_directories(workspaceDirs ${files})

    bde_process_workspace(
        ${workspaceDirs}
    )
endif()
