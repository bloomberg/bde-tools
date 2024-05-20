# Default BDE ufid variables handling.
#
# SunOS, cc

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
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-m32 "
           )
endif()

# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if(BDE_BUILD_TARGET_NO_EXC)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-features=no%except "
           )
endif()

# Set requested CPP standard
if (BDE_BUILD_TARGET_CPP03)
    # Sun Studio 12.4 uses incompatible ABI when passed -std=c++03.
    # We do not set anything here relying on default behaviour.
elseif(BDE_BUILD_TARGET_CPP11)
    set(CMAKE_CXX_STANDARD 11)
elseif(BDE_BUILD_TARGET_CPP14)
    set(CMAKE_CXX_STANDARD 14)
elseif(BDE_BUILD_TARGET_CPP17)
    set(CMAKE_CXX_STANDARD 17)
else()
    # c++03 is default for Sun CC (see above)
endif()

# Stlport library selector
if(BDE_BUILD_TARGET_STLPORT)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-DBDE_BUILD_TARGET_STLPORT "
           "-library=stlport4 "
           "-template=no%extdef "
           )
    string(CONCAT DEFAULT_EXE_LINKER_FLAGS
           "${DEFAULT_EXE_LINKER_FLAGS} "
           "-library=stlport4 "
          )
endif()

# Sanitizers
if(BDE_BUILD_TARGET_ASAN)
    message(FATAL_ERROR "Address sanitizer is not available for cc.")
endif()

if(BDE_BUILD_TARGET_MSAN)
    message(FATAL_ERROR "Memory sanitizer is not available for cc.")
endif()

if(BDE_BUILD_TARGET_TSAN)
    message(FATAL_ERROR "Thread sanitizer is not available for cc.")
endif()

if(BDE_BUILD_TARGET_UBSAN)
    message(FATAL_ERROR "UB sanitizer is not available for cc.")
endif()

if(BDE_BUILD_TARGET_FUZZ)
    message(FATAL_ERROR "Fuzzer is not available for cc.")
endif()
