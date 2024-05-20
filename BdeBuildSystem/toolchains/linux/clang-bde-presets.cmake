# Default BDE ufid variables handling.
#
# Linux, clang

# CMAKE_BUILD_TYPE and CMAKE_POSITION_INDEPENDENT_CODE are
# not handled by this code and must be passed to cmake directly by
# BDE or other wrappers (bbcmake) or by plain cmake.

if (NOT BDE_BUILD_TARGET_32 AND NOT BDE_BUILD_TARGET_64)
    if(${CMAKE_HOST_SYSTEM_PROCESSOR} MATCHES "64")
        # 64 bit
        set(BDE_BUILD_TARGET_64 ON CACHE INTERNAL "" FORCE)
    else()
        set(BDE_BUILD_TARGET_32 ON CACHE INTERNAL "" FORCE)
    endif()
endif()

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
           "-D_FILE_OFFSET_BITS=64 "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-m32 "
           "-mstackrealign "
           "-mfpmath=sse "
           "-D_FILE_OFFSET_BITS=64 "
           )
endif()

# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if(BDE_BUILD_TARGET_NO_EXC)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fno-exceptions "
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
elseif(BDE_BUILD_TARGET_CPP23)
    set(CMAKE_CXX_STANDARD 23)
elseif(BDE_BUILD_TARGET_CPP26)
    set(CMAKE_CXX_STANDARD 26)
else()
    # c++17 is default on Linux when nothing is set
    set(CMAKE_CXX_STANDARD 17)
endif()

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)

# Stlport library selector
if(BDE_BUILD_TARGET_STLPORT)
    message(FATAL_ERROR "Stlport is not available on Linux.")
endif()

# Sanitizers
if(BDE_BUILD_TARGET_ASAN)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-fsanitize=address "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=address "
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
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=memory "
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
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=thread "
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
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=undefined "
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
           "-fsanitize=fuzzer-no-link "
           "-DBDE_ACTIVATE_FUZZ_TESTING "
           "-DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-fsanitize=fuzzer-no-link "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-static-libsan "
           )
endif()
