# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC
# environment variables.
#
# Linux, clang

include(${CMAKE_CURRENT_LIST_DIR}/../setup_refroot_pkgconfig.cmake)

set(DEFAULT_CXX_FLAGS_INIT "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS_INIT "$ENV{CFLAGS}")

# Clang looks for its runtime libraries (e.g., the sanitizer runtimes) in a
# resource directory found from its symlink-resolved path.  Some installations
# put the runtimes beside one of the symlinks leading to clang instead.  If the
# default resource directory has no 'lib', use the first resource directory
# along the symlink chain that has one.
execute_process(COMMAND "$ENV{CXX}" -print-resource-dir
                OUTPUT_VARIABLE clang_resource_dir
                OUTPUT_STRIP_TRAILING_WHITESPACE
                ERROR_QUIET)

if (clang_resource_dir AND NOT IS_DIRECTORY "${clang_resource_dir}/lib")
    set(clang_link "$ENV{CXX}")
    while (IS_SYMLINK "${clang_link}")
        file(READ_SYMLINK "${clang_link}" clang_target)
        cmake_path(GET clang_link PARENT_PATH clang_link_dir)
        cmake_path(ABSOLUTE_PATH clang_target BASE_DIRECTORY "${clang_link_dir}"
                   OUTPUT_VARIABLE clang_link)
        execute_process(COMMAND "${clang_link}"
                                -no-canonical-prefixes -print-resource-dir
                        OUTPUT_VARIABLE clang_resource_dir
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)
        if (IS_DIRECTORY "${clang_resource_dir}/lib")
            string(APPEND DEFAULT_CXX_FLAGS_INIT
                   " -resource-dir=${clang_resource_dir}")
            string(APPEND DEFAULT_C_FLAGS_INIT
                   " -resource-dir=${clang_resource_dir}")
            break()
        endif()
    endwhile()
endif()

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
    "-Woverflow "
    "-Wpacked "
    "-Wparentheses "
    "-Wpointer-arith "
    "-Wreorder "
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
    "-Wno-unevaluated-expression "
    "-Wno-unused-comparison "
    )

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS_INIT} "
       "-march=westmere "
       "-fdiagnostics-show-option "
       "-fno-strict-aliasing "
       ${CXX_WARNINGS}
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS_INIT} "
       "-march=westmere "
       "-fdiagnostics-show-option "
       "-fno-strict-aliasing "
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
