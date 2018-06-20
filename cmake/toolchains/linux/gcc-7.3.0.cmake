set(root /opt/bb/lib/gcc-7.3/bin/)
set(CMAKE_C_COMPILER ${root}/gcc)
set(CMAKE_CXX_COMPILER ${root}/g++)

include("toolchains/linux/gcc-default")
