# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via build environment.
#
# Windows, cl

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "/TP "
       "/FS "
       "/MP "
       "/GR "
       "/GT "
       "/nologo "
       "/D_WIN32_WINNT=0x0600 "
       "/DWINVER=0x0600 "
      )
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)

set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "/TC "
       "/FS "
       "/MP "
       "/GT "
       "/nologo "
      )
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)


set(CMAKE_CXX_FLAGS_RELEASE         "/MD /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "/MD /O1 /Ob1 /Os /DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "/MD /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /Zi /DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "/MDd /Od /Ob0 /Zi"
    CACHE STRING "Debug"          FORCE)

set(CMAKE_C_FLAGS_RELEASE         "/MD /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /DNDEBUG"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL      "/MD /O1 /Ob1 /Os /DNDEBUG"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO  "/MD /O2 /Ob1 /Oi /Ot /GS- /Gs /GF /Gy /Zi /DNDEBUG"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG           "/MDd /Od /Ob0 /Zi"
    CACHE STRING "Debug"          FORCE)
