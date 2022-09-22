# Default compiler-less toolchains for BDE build system.
# The actual compiler for this toolchain is passed via CXX and CC 
# environment variables.
#
# AIX, xlc
#
# Important: this variable changes the behaviour of the shared library
# link step.
set(CMAKE_BUILD_WITH_INSTALL_RPATH TRUE)

set(DEFAULT_CXX_FLAGS "$ENV{CXXFLAGS}")
set(DEFAULT_C_FLAGS "$ENV{CFLAGS}")

string(CONCAT DEFAULT_CXX_FLAGS
       "${DEFAULT_CXX_FLAGS} "
       "-bmaxdata:0x50000000 "      # DRQS 13597546
       "-qalias=noansi "
       "-qarch=pwr6 "
       "-qdfp "
       "-qfuncsect "
       "-qinline "
       "-qlanglvl=staticstoreoverlinkage "
       "-qnotempinc "
       "-qrtti=all "
       "-qsuppress=1500-029 "
       "-qsuppress=1500-030 "
       "-qsuppress=1501-201 "
       "-qsuppress=1540-2910 "
       "-qtbtable=small "
       "-qtls "
       "-qtune=pwr7 "
       "-qxflag=dircache:71,100 "
       "-qxflag=NoKeepDebugMetaTemplateType "
       "-qxflag=tocrel "
       "-qxflag=FunctionCVTmplArgDeduction2011 "
       "-qxflag=UnwindTypedefInClassDecl "
       "-qxflag=inlinewithdebug:stepOverInline "
       "-qxflag=noautoinline "
       "-qxflag=TolerateIncorrectUncaughtEHState "
      )

string(CONCAT DEFAULT_C_FLAGS
       "${DEFAULT_C_FLAGS} "
       "-qarch=pwr6 "
       "-qdfp "
       "-qfuncsect "
       "-qinline "
       "-qtbtable=none "
       "-qtune=pwr7 "
      )

# Include BDE ufid presets
include("${CMAKE_CURRENT_LIST_DIR}/xlc-bde-presets.cmake")

set(CMAKE_CXX_FLAGS ${DEFAULT_CXX_FLAGS} CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   ${DEFAULT_C_FLAGS}   CACHE STRING "Default" FORCE)
set(CMAKE_EXE_LINKER_FLAGS ${DEFAULT_EXE_LINKER_FLAGS} CACHE STRING "Default" FORCE)

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
