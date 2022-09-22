cmake_minimum_required( VERSION 3.13 )
project( TargetBDEStyleUor-tests-bde-source )

# Hack until BBToolchain stops resetting this
if( TESTHELPER_INSTALL_DIR )
  set( ENV{PKG_CONFIG_SYSROOT_DIR} ${TESTHELPER_INSTALL_DIR} )
endif()

enable_testing()

# Libraries and applications with chain of dependencies

add_subdirectory( groups/xyz )
add_subdirectory( adapters/a_xyz )
add_subdirectory( applications/xyzmainonly )
add_subdirectory( applications/xyzwithlib )

# Libraries and applications with no dependencies

add_subdirectory( adapters/a_nodep )
add_subdirectory( applications/nodep )

# Additional validation

find_package(ModuleTestHelpers REQUIRED)
add_testcase_count_check_target(validate 3)
