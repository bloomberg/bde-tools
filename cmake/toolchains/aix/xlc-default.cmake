# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC 
# environment variables.
#
# AIX, xlc
#
# Important: this variable changes the behaviour of the shared library
# link step.
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)

string(CONCAT DEFAULT_CXX_FLAGS
       "-q${BUILD_BITNESS} "
       "-qalias=noansi "
       "-qarch=pwr6 "
       "-qdebug=nparseasm "
       "-qfuncsect "
       "-qlanglvl=staticstoreoverlinkage "
       "-qmaxmem=-1 "
       "-qnotempinc "
       "-qrtti=all "
       "-qsuppress=1500-029 "
       "-qsuppress=1540-2910 "
       "-qsuppress=1501-201 "
       "-qtbtable=small "
       "-qtls "
       "-qtune=pwr7 "
       "-qxflag=dircache:71,100 "
       "-qxflag=NoKeepDebugMetaTemplateType "
       "-qxflag=tocrel "
       "-qxflag=FunctionCVTmplArgDeduction2011 "
       "-qxflag=UnwindTypedefInClassDecl "
      )
set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)

string(CONCAT DEFAULT_C_FLAGS
       "-q${BUILD_BITNESS} "
       "-qalias=noansi "
       "-qarch=pwr6 "
       "-qdebug=nparseasm "
       "-qfuncsect "
       "-qlanglvl=staticstoreoverlinkage "
       "-qmaxmem=-1 "
       "-qnotempinc "
       "-qrtti=all "
       "-qsuppress=1500-029 "
       "-qsuppress=1540-2910 "
       "-qsuppress=1501-201 "
       "-qtbtable=small "
       "-qtls "
       "-qtune=pwr7 "
       "-qxflag=dircache:71,100 "
       "-qxflag=NoKeepDebugMetaTemplateType "
       "-qxflag=tocrel "
       "-qxflag=FunctionCVTmplArgDeduction2011 "
       "-qxflag=UnwindTypedefInClassDecl "
      )
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)

set(CMAKE_CXX_FLAGS_RELEASE         "-O"
    CACHE STRING "Release"        FORCE)
set(CMAKE_CXX_FLAGS_MINSIZEREL      "-O"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_CXX_FLAGS_RELWITHDEBINFO  "-O -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_CXX_FLAGS_DEBUG           "-g"
    CACHE STRING "Debug"          FORCE)


set(CMAKE_C_FLAGS_RELEASE           "-O"
    CACHE STRING "Release"        FORCE)
set(CMAKE_C_FLAGS_MINSIZEREL        "-O"
    CACHE STRING "MinSizeRel"     FORCE)
set(CMAKE_C_FLAGS_RELWITHDEBINFO    "-O -g"
    CACHE STRING "RelWithDebInfo" FORCE)
set(CMAKE_C_FLAGS_DEBUG             "-g"
    CACHE STRING "Debug"          FORCE)

# All tools on AIX need a bitness.
set(CMAKE_CXX_ARCHIVE_CREATE
    "<CMAKE_AR> -X${BUILD_BITNESS} cr <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_APPEND
    "<CMAKE_AR> -X${BUILD_BITNESS} r <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_CXX_ARCHIVE_FINISH
    "<CMAKE_RANLIB> -X${BUILD_BITNESS} <TARGET> <LINK_FLAGS>")

set(CMAKE_C_ARCHIVE_CREATE
    "<CMAKE_AR> -X${BUILD_BITNESS} cr <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_C_ARCHIVE_APPEND
    "<CMAKE_AR> -X${BUILD_BITNESS} r <TARGET> <LINK_FLAGS> <OBJECTS>")
set(CMAKE_C_ARCHIVE_FINISH
    "<CMAKE_RANLIB> -X${BUILD_BITNESS} <TARGET> <LINK_FLAGS>")

set(CMAKE_CXX_CREATE_SHARED_LIBRARY
    "<CMAKE_CXX_COMPILER> <CMAKE_SHARED_LIBRARY_CXX_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_CXX_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")

set(CMAKE_C_CREATE_SHARED_LIBRARY
    "<CMAKE_C_COMPILER> <CMAKE_SHARED_LIBRARY_C_FLAGS> <LANGUAGE_COMPILE_FLAGS> <CMAKE_SHARED_LIBRARY_CREATE_C_FLAGS> <LINK_FLAGS> <SONAME_FLAG><TARGET_SONAME> -o <TARGET> <OBJECTS> <LINK_LIBRARIES>")
