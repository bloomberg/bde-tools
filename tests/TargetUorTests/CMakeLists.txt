cmake_minimum_required(VERSION 3.15)

# Install output in build directory
set(install_dir ${CMAKE_CURRENT_BINARY_DIR}/install)

add_cmake_test(SOURCE_DIR "standalone_package"
               CMAKE_ARGS "--log-level TRACE"
               INSTALL_DIR "${install_dir}"
               RUN_TEST)

add_cmake_test(SOURCE_DIR "custom_packages"
               CMAKE_ARGS "--log-level TRACE"
               INSTALL_DIR "${install_dir}")

add_cmake_test(SOURCE_DIR "simple_group"
               CMAKE_ARGS "--log-level TRACE"
               INSTALL_DIR "${install_dir}")

# Configure and install the "external" libraries that should be found using
# pkg-config
add_cmake_test(SOURCE_DIR "external"
               INSTALL_DIR "${install_dir}"
               RUN_INSTALL)

# Configure and install the BDE-style sources
add_cmake_test(SOURCE_DIR "bde_source"
               CMAKE_ARGS "--log-level TRACE"
               DEPENDS "external"
               INSTALL_DIR "${install_dir}"
               RUN_TEST
               RUN_INSTALL
               VALIDATION_TARGET "validate")
