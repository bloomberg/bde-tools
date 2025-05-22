# Homebrew (https://brew.sh) llvm-based (clang) toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.  These compilers are installed at /local/opt/llvm or
# /local/opt/llvm@VER root folders and since they are not Apple-provided some
# additional comment line options are necessary to make them work.
#
# The file itself is a copy of clang-default.cmake with lines added/modified
# between the START/END comments.
#
# Darwin, llvm, Homebrew

include(${CMAKE_CURRENT_LIST_DIR}/../setup_refroot_pkgconfig.cmake)

# Homebrew llvm changes START

set(cxx_path "$ENV{CXX}")

cmake_path(GET cxx_path PARENT_PATH cxx_bin_path)
cmake_path(GET cxx_bin_path PARENT_PATH cxx_root)

execute_process(COMMAND xcrun --sdk macosx --show-sdk-path OUTPUT_VARIABLE macos_sdkroot OUTPUT_STRIP_TRAILING_WHITESPACE)

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS} -I${cxx_root}/include")
set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS} -I${cxx_root}/include")
set(DEFAULT_EXE_LINKER_FLAGS "-Wl,-no_warn_duplicate_libraries -L${cxx_root}/lib -L${cxx_root}/lib/c++ -L${macos_sdkroot}/usr/lib -Wl,-rpath,${cxx_root}/lib/c++")

# Homebrew llvm changes END

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
