# Set various Windows specific defines
string(CONCAT DEFAULT_CXX_FLAGS
       "-DNOGDI "
       "-DNOMINMAX "
       "-D_CRT_SECURE_NO_WARNINGS "
       "-D_SCL_SECURE_NO_DEPRECATE "
       "-DWIN32_LEAN_AND_MEAN "
       "-DVC_EXTRALEAN "
      )

# Set requested CPP standard
if (BDE_BUILD_TARGET_CPP03)
    set(CMAKE_CXX_STANDARD 98)
elseif(BDE_BUILD_TARGET_CPP11)
    set(CMAKE_CXX_STANDARD 11)
elseif(BDE_BUILD_TARGET_CPP14)
    set(CMAKE_CXX_STANDARD 14)
elseif(BDE_BUILD_TARGET_CPP17)
    set(CMAKE_CXX_STANDARD 17)
elseif(BDE_BUILD_TARGET_CPP20)
    set(CMAKE_CXX_STANDARD 20)
elseif(BDE_BUILD_TARGET_CPP23)
    set(CMAKE_CXX_STANDARD 23)
else()
    # c++17 is default on Windows when nothing is set
    set(CMAKE_CXX_STANDARD 17)
endif()

# Disable GNU c++ extensions.
set(CMAKE_CXX_EXTENSIONS OFF)

# NOTE: all c++ compilers support exception by default
# and BDE will by default define BDE_BUILD_TARGET_EXC
if (BDE_BUILD_TARGET_NO_EXC)
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "/EHs- "
           )
else()
    string(CONCAT DEFAULT_CXX_FLAGS
           "${DEFAULT_CXX_FLAGS} "
           "/EHsc "
           )
endif()
