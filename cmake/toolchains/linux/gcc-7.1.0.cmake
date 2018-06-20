set(root /bb/bde/bbshr/bde-internal-tools/bin/compiler-wrappers/gcc)
set(CMAKE_C_COMPILER ${root}/gcc-7)
set(CMAKE_CXX_COMPILER ${root}/g++-7)

include("toolchains/linux/gcc-default")
