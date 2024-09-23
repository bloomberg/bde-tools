# Default clang-based toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# Darwin, clang

include(${CMAKE_CURRENT_LIST_DIR}/../setup_refroot_pkgconfig.cmake)

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")
set(DEFAULT_EXE_LINKER_FLAGS "-Wl,-no_warn_duplicate_libraries")

set(CXX_WARNINGS
    " "
    )

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       ${CXX_WARNINGS}
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
      )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/clang-bde-presets.cmake")

# After picking various ufid flags, make them default.
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-O2 -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O2 -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O2 -g -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-g"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE           "-O2 -DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-O2 -DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O2 -g -DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-g"
    CACHE STRING "Debug"          FORCE)
