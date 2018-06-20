# Select global build type flags.
set(CMAKE_CXX_FLAGS "-m${BUILD_BITNESS}" CACHE STRING "Default" FORCE)
set(CMAKE_C_FLAGS   "-m${BUILD_BITNESS}" CACHE STRING "Default" FORCE)

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)
