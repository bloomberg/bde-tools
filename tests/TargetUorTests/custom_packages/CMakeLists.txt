cmake_minimum_required(VERSION 3.15)
project(TargetBDEStyleUor-tests-simple-group)

# Hack until BBToolchain stops resetting this
if(TESTHELPER_INSTALL_DIR)
  set(ENV{PKG_CONFIG_SYSROOT_DIR} ${TESTHELPER_INSTALL_DIR})
endif()

enable_testing()

# Libraries and applications with chain of dependencies
add_subdirectory(xyz)
