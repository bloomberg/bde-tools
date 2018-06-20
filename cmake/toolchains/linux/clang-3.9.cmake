set(root /bb/bde/bbshr/RHEL6-clang-compilers/opt/bb/lib/llvm-3.9/bin)
set(CMAKE_C_COMPILER ${root}/clang)
set(CMAKE_CXX_COMPILER ${root}/clang++)

include("toolchains/linux/clang-default")
