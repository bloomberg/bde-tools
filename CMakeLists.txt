cmake_minimum_required(VERSION 3.22)

project(bde-tools NONE)

# bbs-tools 
install(DIRECTORY BdeBuildSystem
        DESTINATION share/cmake
        COMPONENT bbs-cmake-module
        PATTERN "sim_cpp11_features.pl|bbs_runtest.py|wafstyleout.py" 
            PERMISSIONS OWNER_READ OWNER_EXECUTE
                        GROUP_READ GROUP_EXECUTE
                        WORLD_READ WORLD_EXECUTE)

install(PROGRAMS bin/bbs_build.py
                 bin/bbs_build_env.py
        DESTINATION libexec/bde-tools/bin
        COMPONENT bde-tools)

include(CTest)
if(BUILD_TESTING)
  find_package(ModuleTestHelpers REQUIRED)

  add_subdirectory(tests/MetadataTests)
  add_subdirectory(tests/TargetUorTests)
endif()

# bde-tools
# keep pylibinit when removing old bde-tools install rules(!)
install(PROGRAMS bin/bde_build_env.py
                 bin/bde_runtest.py
                 bin/cmake_build.py
        DESTINATION libexec/bde-tools/bin
        COMPONENT bde-tools)

install(DIRECTORY cmake lib
        DESTINATION libexec/bde-tools
        COMPONENT bde-tools
        PATTERN "__pycache__" EXCLUDE)

install(DIRECTORY bin/pylibinit
        DESTINATION libexec/bde-tools/bin
        COMPONENT bde-tools
        PATTERN "__pycache__" EXCLUDE)

# Install rules for bde-gdb-printers
install(FILES contrib/gdb-printers/bde_printer.py
        DESTINATION libexec/bde-gdb-printers
        COMPONENT bde-gdb-printers)

install(FILES contrib/gdb-printers/gdbinit.dpkg
        DESTINATION libexec/bde-gdb-printers
        RENAME gdbinit
        COMPONENT bde-gdb-printers)
