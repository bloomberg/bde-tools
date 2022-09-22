# Default BDE ufid variables handling.
#
# AIX, xlc

# CMAKE_BUILD_TYPE and CMAKE_POSITION_INDEPENDENT_CODE are
# not handled by this code and must be passed to cmake directly by
# BDE or other wrappers (bbcmake) or by plain cmake.

if(BDE_BUILD_TARGET_64)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-q64 "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-q64 "
           )

    # All tools on AIX need a bitness.
    set(CMAKE_CXX_ARCHIVE_CREATE "<CMAKE_AR> -X64 cr <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_CXX_ARCHIVE_APPEND "<CMAKE_AR> -X64 r <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_CXX_ARCHIVE_FINISH "<CMAKE_RANLIB> -X64 <TARGET> <LINK_FLAGS>")

    set(CMAKE_C_ARCHIVE_CREATE "<CMAKE_AR> -X64 cr <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_C_ARCHIVE_APPEND "<CMAKE_AR> -X64 r <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_C_ARCHIVE_FINISH "<CMAKE_RANLIB> -X64 <TARGET> <LINK_FLAGS>")
endif()

if(BDE_BUILD_TARGET_32)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-q32 "
           )
    string(CONCAT DEFAULT_C_FLAGS
           "${DEFAULT_C_FLAGS} "
           "-q32 "
           )

    # All tools on AIX need a bitness.
    set(CMAKE_CXX_ARCHIVE_CREATE "<CMAKE_AR> -X32 cr <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_CXX_ARCHIVE_APPEND "<CMAKE_AR> -X32 r <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_CXX_ARCHIVE_FINISH "<CMAKE_RANLIB> -X32 <TARGET> <LINK_FLAGS>")

    set(CMAKE_C_ARCHIVE_CREATE "<CMAKE_AR> -X32 cr <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_C_ARCHIVE_APPEND "<CMAKE_AR> -X32 r <TARGET> <LINK_FLAGS> <OBJECTS>")
    set(CMAKE_C_ARCHIVE_FINISH "<CMAKE_RANLIB> -X32 <TARGET> <LINK_FLAGS>")
endif()

set(CMAKE_CXX_CREATE_SHARED_LIBRARY
    "<CMAKE_CXX_COMPILER> <CMAKE_SHARED_LIBRARY_CXX_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")

set(CMAKE_C_CREATE_SHARED_LIBRARY
    "<CMAKE_C_COMPILER> <CMAKE_SHARED_LIBRARY_C_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")

# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if(BDE_BUILD_TARGET_NO_EXC)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-qnoeh "
           "-qsuppress=1540-1090 "
           "-qsuppress=1540-1088 "
           "-DBDE_BUILD_TARGET_NO_EXC "
           )
else()
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "-qeh "
           "-qlanglvl=newexcp "
           "-DBDE_BUILD_TARGET_EXC "
           )
endif()

# Set requested CPP standard
if (BDE_BUILD_TARGET_CPP03)
    # c++03 is default on AIX
elseif(BDE_BUILD_TARGET_CPP11)
    set(CMAKE_CXX_STANDARD 11)
elseif(BDE_BUILD_TARGET_CPP14)
    set(CMAKE_CXX_STANDARD 14)
elseif(BDE_BUILD_TARGET_CPP17)
    set(CMAKE_CXX_STANDARD 17)
elseif(BDE_BUILD_TARGET_CPP20)
    set(CMAKE_CXX_STANDARD 20)
else()
    # c++03 is default on AIX
endif()

# Sanitizers
if(BDE_BUILD_TARGET_ASAN)
    message(FATAL_ERROR "Address sanitizer is not available for xlc.")
endif()

if(BDE_BUILD_TARGET_MSAN)
    message(FATAL_ERROR "Memory sanitizer is not available for xlc.")
endif()

if(BDE_BUILD_TARGET_TSAN)
    message(FATAL_ERROR "Thread sanitizer is not available for xlc.")
endif()

if(BDE_BUILD_TARGET_UBSAN)
    message(FATAL_ERROR "UB sanitizer is not available for xlc.")
endif()

if(BDE_BUILD_TARGET_FUZZ)
    message(FATAL_ERROR "Fuzzer is not available for xlc.")
endif()
