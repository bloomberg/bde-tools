# Default BDE ufid variables handling.
#
# clang

# CMAKE_BUILD_TYPE and CMAKE_POSITION_INDEPENDENT_CODE are
# not handled by this code and must be passed to cmake directly by
# BDE or other wrappers (bbcmake) or by plain cmake.

if(BDE_BUILD_TARGET_64)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-m64 "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-m64 "
           )
endif()

if(BDE_BUILD_TARGET_32)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-m32 "
           "-mstackrealign "
           "-mfpmath=sse "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-m32 "
           "-mstackrealign "
           "-mfpmath=sse "
           )
endif()

# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if(BDE_BUILD_TARGET_NO_EXC)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fno-exceptions "
           "-DBDE_BUILD_TARGET_NO_EXC "
           )
endif()

# Set requested CPP standard
if (BDE_BUILD_TARGET_CPP03)
    set(CMAKE_CXX_STANDARD 98)
elseif(BDE_BUILD_TARGET_CPP11)
    set(CMAKE_CXX_STANDARD 11)
elseif(BDE_BUILD_TARGET_CPP14)
    set(CMAKE_CXX_STANDARD 14)
elseif(BDE_BUILD_TARGET_CPP17)
    set(CMAKE_CXX_STANDARD 17)
elseif(BDE_BUILD_TARGET_CPP20)
    set(CMAKE_CXX_STANDARD 20)
else()
    # c++17 is default on Linux when nothing is set
    set(CMAKE_CXX_STANDARD 17)
endif()

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)

# SAFE flags
if(BDE_BUILD_TARGET_SAFE)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBDE_BUILD_TARGET_SAFE "
           "-DBDE_DONT_ALLOW_TRANSITIVE_INCLUDES "
           )
endif()

# ASSERT levels
if(BDE_BUILD_TARGET_AOPT)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_ASSERT_LEVEL_ASSERT_OPT "
           )
elseif(BDE_BUILD_TARGET_ADBG)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_ASSERT_LEVEL_ASSERT "
           )
elseif(BDE_BUILD_TARGET_ASAFE)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_ASSERT_LEVEL_ASSERT_SAFE "
           )
elseif(BDE_BUILD_TARGET_ANONE)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_ASSERT_LEVEL_NONE "
           )
endif()

# REVIEW levels
if(BDE_BUILD_TARGET_ROPT)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_REVIEW_LEVEL_REVIEW_OPT "
           )
elseif(BDE_BUILD_TARGET_RDBG)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_REVIEW_LEVEL_REVIEW "
           )
elseif(BDE_BUILD_TARGET_RSAFE)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_REVIEW_LEVEL_REVIEW_SAFE "
           )
elseif(BDE_BUILD_TARGET_ANONE)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBSLS_REVIEW_LEVEL_NONE "
           )
endif()

# Sanitizers
if(BDE_BUILD_TARGET_ASAN)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=address "
           "-DBDE_BUILD_TARGET_ASAN "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=address "
           "-DBDE_BUILD_TARGET_ASAN "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=address "
           "-static-libsan "
           )
endif()

if(BDE_BUILD_TARGET_MSAN)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=memory "
           "-DBDE_BUILD_TARGET_TSAN "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=memory "
           "-DBDE_BUILD_TARGET_TSAN "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=memory "
           "-static-libsan "
           )
endif()

if(BDE_BUILD_TARGET_TSAN)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=thread "
           "-DBDE_BUILD_TARGET_TSAN "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=thread "
           "-DBDE_BUILD_TARGET_TSAN "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=thread "
           "-static-libsan "
           )
endif()

if(BDE_BUILD_TARGET_UBSAN)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=undefined "
           "-DBDE_BUILD_TARGET_UBSAN "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=undefined "
           "-DBDE_BUILD_TARGET_UBSAN "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=undefined "
           "-static-libsan "
           )
endif()

if(BDE_BUILD_TARGET_FUZZ)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=fuzzer-no-link"
           "-DBDE_ACTIVATE_FUZZ_TESTING"
           "-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION"
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=undefined "
           "-static-libubsan "
           )
endif()
