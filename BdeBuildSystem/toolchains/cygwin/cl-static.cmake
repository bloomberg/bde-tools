# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via build environment.
#
# Windows, cl

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "/TP "
       "/FS "
       "/MP "
       "/GR "
       "/GT "
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "/TC "
       "/FS "
       "/MP "
       "/GT "
      )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/cl-bde-presets.cmake")

set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)

# cmake 3.15+ MSVC Runtime library support. We control the setting via our toolchain.
# https://cmake.org/cmake/help/v3.15/variable/CMAKE_MSVC_RUNTIME_LIBRARY.html
set(CMAKE_MSVC_RUNTIME_LIBRARY "")

set(CMAKE_CXX_FLAGS_RELEASE         "/MT /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "/MT /O1 /Ob1 /Os /DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "/MT /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /Zi /DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "/MTd /Od /Ob0 /Zi"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE         "/MT /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL      "/MT /O1 /Ob1 /Os /DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO  "/MT /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /Zi /DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG           "/MTd /Od /Ob0 /Zi"
    CACHE STRING "Debug"          FORCE)
