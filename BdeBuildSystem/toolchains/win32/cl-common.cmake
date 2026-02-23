# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via build environment.
#
# Windows, cl

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

set(CXX_WARNINGS
    # deletion of pointer to incomplete type
    "/we4150 "
    # elements of array will be default initialized
    "/wd4351 "
    # default constructor could not be generated
    "/wd4510 "
    # default constructor could not be generated
    "/wd4610 "
    # A member of a class template is not defined
    "/wd4661 "
    # not all control paths return a value
    "/we4715 "
)

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "/TP "
       "/FS "
       "/MP "
       "/GR "
       "/GT "
       ${CXX_WARNINGS}
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

# cmake-community support.
# See also https://bbgithub.dev.bloomberg.com/conan/conan_common_config_install/blob/master/profiles/toolchain/windows.cmake
set(INSTALL_BB_LIBRARY_DEFAULT_ARGS
        NO_EMIT_PKGCONFIG_FILE
    )

set(CONFIGURE_BB_TARGET_DEFAULT_ARGS
        NO_BASELINE_CHECKS
        NO_BBALIGNMAGIC
        NO_BBGLIB
        NO_BBTHREADS
        NO_EMIT_PKG_CONFIG_FILE
        NO_FORTRAN_RUNTIME
        NO_IMPORT_PKGCONFIG
        NO_INTBASIC
        NO_PEOVERRIDE
        NO_PLINKSTRINGS
        NO_SUNOS_MISALIGN
    )
