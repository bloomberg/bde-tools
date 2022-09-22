include_guard()

#.rst
# .. command: _pkgconfig_map_insert
#
# Macro for inserting values into UOR to PKGCONFIG name mapping.
macro(_pkgconfig_map_insert uor_name pc_name)
    set(_uor_to_pkgconfig_map_${uor_name} ${pc_name})
    set(_pkgconfig_to_uor_map_${pc_name} ${uor_name})
endmacro()

_pkgconfig_map_insert(apr1           apr-1)
_pkgconfig_map_insert(aprutil1       apr-util-1)
_pkgconfig_map_insert(crypto         libcrypto)
_pkgconfig_map_insert(curl           libcurl)
_pkgconfig_map_insert(event          libevent)
_pkgconfig_map_insert(event_pthreads libevent_pthreads)
_pkgconfig_map_insert(event_openssl  libevent_openssl)
_pkgconfig_map_insert(glib2          glib-2.0)
_pkgconfig_map_insert(gmock_main     gmock_main)
_pkgconfig_map_insert(gobject2       gobject-2.0)
_pkgconfig_map_insert(gtest_main     gtest_main)
_pkgconfig_map_insert(protobuf-c     libprotobuf-c)
_pkgconfig_map_insert(ssl            libssl)
_pkgconfig_map_insert(svm            libsvm)
_pkgconfig_map_insert(uv             libuv)
_pkgconfig_map_insert(xercesc        xerces-c)
_pkgconfig_map_insert(z              zlib)

#.rst
# .. command: bbs_uor_to_pc_name
#
# Provides the UOR to PKGCONFIG name mapping used in the bdemeta-genpkgconfig
# tool.
function(bbs_uor_to_pc_name uor_name pc_name)
    bbs_assert_no_extra_args()

    if(DEFINED _uor_to_pkgconfig_map_${uor_name})
        set(${pc_name} ${_uor_to_pkgconfig_map_${uor_name}} PARENT_SCOPE)
    endif()

    string(REPLACE "_" "-" sanitizedName "${uor_name}")
    set(${pc_name} ${sanitizedName} PARENT_SCOPE)
endfunction()

#.rst
# .. command: bbs_pc_to_uor_name
#
# Provides the PKGCONFIG to UOR name mapping used in the bdemeta-genpkgconfig
# tool.
function(bbs_pc_to_uor_name pc_name uor_name )
    bbs_assert_no_extra_args()
    if(DEFINED _pkgconfig_to_uor_map_${pc_name})
        set(${uor_name} ${_pkgconfig_to_uor_map_${pc_name}} PARENT_SCOPE)
    endif()

    string(REPLACE "-" "_" sanitizedName "${pc_name}")
    set(${uor_name} ${sanitizedName} PARENT_SCOPE)
endfunction()

#.rst
# .. command: bbs_uor_to_pc_list
#
# Provides the UOR to PKGCONFIG name mapping used in the bdemeta-genpkgconfig
# tool, applying bbs_uor_to_pc_name to each item in a list, as from a dep file,
# and output into the variable specified by the caller as pc_list.
function(bbs_uor_to_pc_list uor_list pc_list)
    bbs_assert_no_extra_args()

    foreach(uor_name ${uor_list})
        bbs_uor_to_pc_name(${uor_name} _pc_name)
        list(APPEND _pc_list ${_pc_name})
    endforeach()

    set(${pc_list} ${_pc_list} PARENT_SCOPE)
endfunction()

#.rst
# .. command: bbs_pc_to_uor_list
#
# Provides the PKGCONFIG to UOR name mapping used in the bdemeta-genpkgconfig
# tool, applying bbs_pc_to_uor_list to each item in a list as from a pkgconfig
# file, and output into the variable specified by the caller as uor_list.
function(bbs_pc_to_uor_list pc_list uor_list)
    bbs_assert_no_extra_args()

    foreach(pc_name ${pc_list})
      bbs_pc_to_uor_name(${pc_name} _uor_name)
      list(APPEND _uor_list ${_uor_name})
    endforeach()

    set(${uor_list} ${_uor_list} PARENT_SCOPE)
endfunction()
