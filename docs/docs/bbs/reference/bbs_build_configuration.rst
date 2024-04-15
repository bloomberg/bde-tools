===========================
Build Configuration Options
===========================

BBS provides users with ability to configure the build for a specific compiler,
operating system, architecture and build flavors. Those configurations are
identified/described by a set of flags.

.. note::

   The compiler and build options are typically set in the build environmenet
   using :doc:`../tools/bbs_build_env`.

UPLID
=====

UPLID stands for Universal Platform ID.  It is used to identify the platform
and tool-chain used to build the repository.  This identifier comprises the
following parts (in order) joined together with the delimiter ``-``:

1. OS Type
2. OS Name
3. CPU type
4. OS Version
5. CompilerToolchain

For example, ``unix-linux-x86_64-3.10.0-gcc-9.0.0`` is an UPLID whose OS
type is ``unix``, OS Name is ``linux``, CPU type is ``x86_64``, OS
version is ``3.10.0`` and compiler profile with name ``gcc-9.0.0``.

UPLID (combined with UFID) is primarily used to generate unique build folders
for building different flavors of BDE repos.

Valid OS Types
--------------

.. csv-table::
   :header: "OS Type", "Description"
   :widths: 40, 60
   :align: left

   "unix", "Unix-based operating systems and containers(Linux, Solaris, AIX, OS X, WSL)"
   "windows", "Microsoft Windows operating system"

Valid OS Names
--------------

.. csv-table::
   :header: "OS Name", "Description"
   :widths: 40, 60
   :align: left

   "linux", "Linux/Linux container (including WSL)"
   "darwin", "MacOS X"
   "aix", "IBM AIX OS"
   "sunos", "Sun Solaris OS"
   "windows_nt", "Microsoft Windows OS"

BBS tools will detect the operating system versions and CPU types by inspecting
the underlying operating system configuration files.

Known Compiler Types
--------------------
BBS tools are capable of auto-detecting common compilers and find a default BDE
toolchain for those compiler types.

.. csv-table::
   :header: "Compiler type ", "Description"
   :widths: 40, 60
   :align: left

   "gcc", " GNU gcc compiler"
   "clang", "clang compiler"
   "xlc", "IBM XL C/C++ compiler"
   "cc", "Sun Studio C/C++ compiler"
   "cl", "Visual Studio C/C++ compiler"

The Compiler toolchains part is generated based on the compiler build profile
selected by the tool.

.. _ufid:


UFID
====

UFIDs (Unified Flag ID) are used to identify the resulting binary/library
configuration to be produced by the build system.

Each individual UFID flag enables/disables a specific configuration aspect of
the resulting build artifacts. Each UFID flag is also mapped to a CMake
variable that can be used with raw CMake workflows to specify the build
configuration.

UFID flags
----------

The following flags are recognized by BBS tools:

.. csv-table::
   :header: "Ufid flag", "CMake Variable", "Description"
   :widths: 10, 30, 60
   :align: left

   "dbg", "CMAKE_BUILD_TYPE='Debug'", "Non optimized build with debug information"
   "opt",  "CMAKE_BUILD_TYPE='Release'", "Optimized build without debug information"
   "opt_dbg", "CMAKE_BUILD_TYPE='RelWithDebInfo'", "Optimized build with debug information"
   "noexc", "BDE_BUILD_TARGET_NOEXC", "Build with no exception (if not specified, exceptions are enabled)"
   "nomt", "BDE_BUILD_TARGET_NOMT", "Build without multi-threading (if not specified, multi-threading is enabled)"
   "32", "BDE_BUILD_TARGET_32", "Build for 32-bit architecture"
   "64", "BDE_BUILD_TARGET_64", "Build for 64-bit architecture (if nether 32/64 are specified, defaults to compiler settings)"
   "safe", "BDE_BUILD_TARGET_SAFE", "Enable additional assertion checks;"
   "safe2", "BDE_BUILD_TARGET_SAFE2", "Enable aggresive assertion checks,  binary-incompatible build"
   "aopt", "-DBSLS_ASSERT_LEVEL_ASSERT_OPT", "Set bsls assert level to OPT"
   "adbg", "-DBSLS_ASSERT_LEVEL_ASSERT_DBG", "Set bsls assert level to DBG"
   "asafe", "-DBSLS_ASSERT_LEVEL_ASSERT_SAFE", "Set bsls assert level to SAFE"
   "anone", "-DBSLS_ASSERT_LEVEL_ASSERT_NONE", "Disable bsls asserts"
   "ropt", "-DBSLS_REVIEW_LEVEL_REVIEW_OPT", "Set bsls review level to OPT"
   "rdbg", "-DBSLS_REVIEW_LEVEL_REVIEW_DBG", "Set bsls review level to DBG"
   "rsafe", "-DBSLS_REVIEW_LEVEL_REVIEW_SAFE", "Set bsls review level to SAFE"
   "rnone", "-DBSLS_REVIEW_LEVEL_REVIEW_NONE", "Disable bsls reviews"
   "asan", "BDE_BUILD_TARGET_ASAN", "Build with address sanitizer"
   "msan", "BDE_BUILD_TARGET_MSAN", "Build with memory sanitizer"
   "tsan", "BDE_BUILD_TARGET_TSAN", "Build with thread sanitizer"
   "ubsan","BDE_BUILD_TARGET_UBSAN", "Build with undefined behavior sanitizer"
   "fuzz", "BDE_BUILD_TARGET_FUZZ", "Build with fuzz tester (specify another sanitizer too)"
   "pic", "CMAKE_POSITION_INDEPENDENT_CODE", "Build position-independent code"
   "stlport", "BDE_BUILD_TARGET_STLPORT", "**(SunOS only)** Use STLport standard library implementation"
   "cpp03", "CMAKE_CXX_STANDARD=98", "Build with support for C++03 features"
   "cpp11", "CMAKE_CXX_STANDARD=11", "Build with support for C++11 features"
   "cpp14", "CMAKE_CXX_STANDARD=14", "Build with support for C++14 features"
   "cpp17", "CMAKE_CXX_STANDARD=17", "Build with support for C++17 features"
   "cpp20", "CMAKE_CXX_STANDARD=20", "Build with support for C++20 features"
   "cpp23", "CMAKE_CXX_STANDARD=23", "Build with support for C++23 features"
   "cpp26", "CMAKE_CXX_STANDARD=26", "Build with support for C++26 features"

For example, the UFID ``dbg_64_pic`` represents a build
configuration that enables debugging symbols, enables multi-threading
and exceptions and produces position independent code for 64-bit bitness .
