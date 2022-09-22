cmake_minimum_required(VERSION 3.15)
project(TargetBDEStyleUor-standalone-package)

# Hack until BBToolchain stops resetting this
if(TESTHELPER_INSTALL_DIR)
  set(ENV{PKG_CONFIG_SYSROOT_DIR} ${TESTHELPER_INSTALL_DIR})
endif()

enable_testing()

# Add package
add_subdirectory(pkgtest)
