# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# Linux, gcc

include(${CMAKE_CURRENT_LIST_DIR}/../setup_refroot_pkgconfig.cmake)

set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

set(CXX_WARNINGS
    "-Waddress "
    "-Wall "
    "-Wcast-align "
    "-Wcast-qual "
    "-Wconversion "
    "-Wextra "
    "-Wformat "
    "-Wformat-security "
    "-Wformat-y2k "
    "-Winit-self "
    "-Wlarger-than-100000 "
    "-Wlogical-op "
    "-Woverflow "
    "-Wpacked "
    "-Wparentheses "
    "-Wpointer-arith "
    "-Wsign-compare "
    "-Wstrict-overflow=1 "
    "-Wtype-limits "
    "-Wvla "
    "-Wvolatile-register-var "
    "-Wwrite-strings "
    "-Wno-char-subscripts "
    "-Wno-long-long "
    "-Wno-sign-conversion "
    "-Wno-unknown-pragmas "
    "-Wno-unused-value "
    )

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS} "
       "-march=westmere "
       "-fdiagnostics-show-option "
       "-fno-strict-aliasing "
       "-fno-omit-frame-pointer "
       ${CXX_WARNINGS}
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS} "
       "-march=westmere "
       "-fdiagnostics-show-option "
       "-fno-strict-aliasing "
      )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/gcc-bde-presets.cmake")

# After picking various ufid flags, make them default.
set(CMAKE_CXX_FLAGS        ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS          ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
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

