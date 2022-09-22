cmake_minimum_required(VERSION 3.15)

project( PackageMetadataTest NONE )

find_package( BdeBuildSystem REQUIRED )

bbs_read_metadata( PACKAGE btst )

message( VERBOSE "Components  : ${btst_COMPONENTS}" )
message( VERBOSE "Include dir : ${btst_INCLUDE_DIRS}" )
message( VERBOSE "Headers     : ${btst_INCLUDE_FILES}" )
message( VERBOSE "Source dir  : ${btst_SOURCE_DIRS}" )
message( VERBOSE "Source files: ${btst_SOURCE_FILES}" )
message( VERBOSE "Test files  : ${btst_TEST_SOURCES}" )
message( VERBOSE "Dependencies: ${btst_DEPENDS}" )
message( VERBOSE "Metadata dir: ${btst_METADATA_DIRS}\n" )

include ( ../TestUtil.cmake )
__test_compare_lists( "${btst_COMPONENTS}" "btst_compabc;btst_compbcd" )
__test_compare_lists( "${btst_SOURCE_FILES}" "" )
__test_compare_lists( "${btst_TEST_SOURCES}" "" )
__test_compare_lists( "${btst_DEPENDS}" "a_bhlntc;bdl;bsl" )
