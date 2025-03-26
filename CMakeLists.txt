cmake_minimum_required(VERSION 3.22)

project(bde-tools NONE)

# bbs-tools
install(DIRECTORY BdeBuildSystem
        DESTINATION share/cmake
        COMPONENT bbs-cmake-module)

install(PROGRAMS BdeBuildSystem/scripts/sim_cpp11_features.pl
                 BdeBuildSystem/scripts/bbs_input_limiter.pl
        DESTINATION share/cmake/BdeBuildSystem/scripts
        COMPONENT bbs-cmake-module)

# bbs shell wrappers
install(PROGRAMS bin/bbs_build
                 bin/bbs_build_env
                 bin/bbs_make_vscode
                 bin/bde_build_env
                 bin/cmake_build
                 bin/bde_runtest
                 bin/get_dependers
        DESTINATION libexec/bde-tools/bin
        COMPONENT bde-tools)

# bbs tools implementation
install(FILES bin/bbs_build.py
              bin/bbs_build_env.py
              bin/bde_build_env.py
              bin/bde_runtest.py
              bin/cmake_build.py
        DESTINATION libexec/bde-tools/bin
        COMPONENT bde-tools)

# bde-tools
# keep pylibinit when removing old bde-tools install rules(!)
install(PROGRAMS bin/bbs_make_vscode.py
                 bin/bde_input_limiter.pl
                 bin/get_dependers.py
                 bin/bde_get_changed_components.sh
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

# Install vscode templates
install(DIRECTORY share/templates/vscode
        DESTINATION libexec/bde-tools/templates
        COMPONENT bde-tools)

# Install rules for bde-gdb-printers
install(FILES contrib/gdb-printers/bde_printer.py
        DESTINATION libexec/bde-gdb-printers
        COMPONENT bde-gdb-printers)

install(FILES contrib/gdb-printers/gdbinit.dpkg
        DESTINATION libexec/bde-gdb-printers
        RENAME gdbinit
        COMPONENT bde-gdb-printers)
