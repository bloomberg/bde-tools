cmake_minimum_required( VERSION 3.15 )
project( TargetBDEStyleUor-tests-external )

find_package( ConfigureBbTarget REQUIRED )

add_library( abc STATIC abc/abc.cpp )
target_include_directories( abc PUBLIC abc )
configure_bb_target( abc V2 INSTALL HEADER_DIRS abc )

add_library( testlib STATIC testlib/testlib.cpp )
target_include_directories( testlib PUBLIC testlib )
configure_bb_target( testlib V2 INSTALL HEADER_DIRS testlib )
