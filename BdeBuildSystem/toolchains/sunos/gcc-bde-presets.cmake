# Default BDE ufid variables handling.
#
# gcc

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
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-m32 "
           )
endif()

string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-fsanitize=undefined "
           "-static-libsan "
           )
# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if (BDE_BUILD_TARGET_NO_EXC)
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
else()
    # c++03 is default on SunOS
    set(CMAKE_CXX_STANDARD 98)
endif()

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)

# Stlport library selector
if(BDE_BUILD_TARGET_STLPORT)
    message(FATAL_ERROR "Stlport is not available for gcc.")
endif()

# Sanitizers
if(BDE_BUILD_TARGET_ASAN)
    message(FATAL_ERROR "Address sanitizer is not available for gcc.")
endif()

if(BDE_BUILD_TARGET_MSAN)
    message(FATAL_ERROR "Memory sanitizer is not available for gcc.")
endif()

if(BDE_BUILD_TARGET_TSAN)
    message(FATAL_ERROR "Thread sanitizer is not available for gcc.")
endif()

if(BDE_BUILD_TARGET_UBSAN)
    message(FATAL_ERROR "UB sanitizer is not available for gcc.")
endif()

if(BDE_BUILD_TARGET_FUZZ)
    message(FATAL_ERROR "Fuzzer is not available for gcc.")
endif()
