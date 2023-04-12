# -----------------------------------------------------------
# This is a copy of the ImportPkgConfigTargets module
# with changed prefix (to avoid name clash) of the functions.
# -----------------------------------------------------------

# import each item in the argument list and all it's
# dependencies as an imported library target
#
# Dependency information is searched with the pkg-config tool
# Additional target direct dependencies can be specified by setting 
# <target>_DEPS variables before calling import_pkgconfig_targets()
# The extra deps will be searched AFTER the deps defined in the pkgconfig file
#
include_guard()

macro(_bbs_pcimport_initialize)
  #
  # Get the default pkg-config search path
  #
  find_program(PKG_CONFIG_EXECUTABLE pkg-config)
  if (NOT PKG_CONFIG_EXECUTABLE)
    if (BDE_BUILD_TARGET_64)
      find_program(PKG_CONFIG_EXECUTABLE pkg-config.64)
      if (NOT PKG_CONFIG_EXECUTABLE)
         message(FATAL_ERROR "Failed to find pkg-config")
      endif()
    else()
      find_program(PKG_CONFIG_EXECUTABLE pkg-config.32)
      if (NOT PKG_CONFIG_EXECUTABLE)
         message(FATAL_ERROR "Failed to find pkg-config")
      endif()
    endif()
  endif()

  execute_process( COMMAND ${PKG_CONFIG_EXECUTABLE} --variable pc_path pkg-config
                   OUTPUT_VARIABLE _importpc_pcpath
                   RESULT_VARIABLE _importpc_pc_path_rc
                   OUTPUT_STRIP_TRAILING_WHITESPACE )

  if ( _importpc_pc_path_rc )
    message( FATAL_ERROR "${PKG_CONFIG_EXECUTABLE} pkg-config --variable pc_path pkg-config failed with rc:${_importpc_pc_path_rc}" )
  elseif( _importpc_pcpath )
    string( REPLACE ":" ";" _importpc_pcpath ${_importpc_pcpath} )
  endif()

  #
  # import_pkgconfig can import packages simultaneously from a relocatable and non-relocatable pkg-config
  # installation. Relocatable installations use the PKG_CONFIG_SYSROOT_DIR environment variable.
  # See the pkg-config man page for more details. Each type of installation has a list of search paths
  # for its .pc files.
  # To set the prefix for the relocatable installation use the PKG_CONFIG_SYSROOT_DIR environment variable.
  # The search paths for the relocatable installation  use the PKG_CONFIG_PATH environment variable.
  # To use a non-relocatable installation either unset the PKG_CONFIG_SYSROOT_DIR environment variable or set
  # the NON_SYSROOT_PKG_CONFIG_PATH list.
  # To set the search paths for the non-relocatable installation you may set the NON_SYSROOT_PKG_CONFIG_PATH list
  # or use the PKG_CONFIG_PATH environment variable if you are not using that variable for the relocatable
  # installation.
  #
  set( installation_names )
  if ( NOT $ENV{PKG_CONFIG_SYSROOT_DIR} STREQUAL "" )
    set( installation_names pkgconfig_installations_sysroot )
    set( pkgconfig_installations_sysroot_PKG_CONFIG_SYSROOT_DIR $ENV{PKG_CONFIG_SYSROOT_DIR} CACHE STRING "PKG_CONFIG_SYSROOT_DIR for sysroot pkg-config")
    set( pkgconfig_installations_sysroot_PKG_CONFIG_PATH $ENV{PKG_CONFIG_PATH} CACHE STRING "PKG_CONFIG_PATH for sysroot pkg-config")
    if ( NON_SYSROOT_PKG_CONFIG_PATH )
       list( APPEND installation_names pkgconfig_installations_non-sysroot )
       set( pkgconfig_installations_non-sysroot_PKG_CONFIG_SYSROOT_DIR "" CACHE STRING "PKG_CONFIG_SYSROOT_DIR for non-sysroot pkg-config")
       set( pkgconfig_installations_non-sysroot_PKG_CONFIG_PATH ${NON_SYSROOT_PKG_CONFIG_PATH} CACHE STRING "PKG_CONFIG_PATH for non-sysroot pkg-config")
    endif()
  else()
    set( installation_names pkgconfig_installations_non-sysroot )
    set( pkgconfig_installations_non-sysroot_PKG_CONFIG_SYSROOT_DIR "" CACHE STRING "PKG_CONFIG_SYSROOT_DIR for non-sysroot pkg-config")
    set( pkgconfig_installations_non-sysroot_PKG_CONFIG_PATH ${NON_SYSROOT_PKG_CONFIG_PATH}:$ENV{PKG_CONFIG_PATH} CACHE STRING "PKG_CONFIG_PATH for non-sysroot pkg-config")
  endif()
  set( PKG_CONFIG_INSTALLATION_NAMES ${installation_names} CACHE STRING "Which pkg-config installations to use")
endmacro()

if( NOT WIN32)
  _bbs_pcimport_initialize()
endif()

function( bbs_import_pkgconfig_targets )
  if (WIN32)
    message(STATUS "Skipping pkg-config dependency resolution")
  endif()

  _bbs_import_pkgconfig_targets( "${ARGV}" "" )
  if ( TARGET peutil )
     # WORKAROUND: Generally it's not a good idea to hardcode specific
     # logic for specific imports in this package, but this special logic was
     # added to unblock the migration from Sun Studio Fortran to gfortran,
     # which itself unblocks the Linux migration.
     #
     # When Dependency Injection is possible for turning target names
     # into properly realized targets, this logic should be removed.
     # See: http://bburl/required-targets
     get_target_property( peutil_type peutil TYPE )
     if ( peutil_type STREQUAL STATIC_LIBRARY )
        set_target_properties( peutil
                               PROPERTIES
                               IMPORTED_LINK_INTERFACE_LANGUAGES "CXX;Fortran" )
     endif()
  endif()
endfunction()

function( _bbs_import_pkgconfig_targets pkgnames pkgparents )
  foreach( pkgname ${pkgnames} )
    set( pkgcallchain ${pkgparents} ${pkgname} )
    _bbs_pcimport_add_package( ${pkgname} "${pkgcallchain}" )
  endforeach()
endfunction()
 
#
# Add the following pkg and all it's required dependencies as imported targets
#
function( _bbs_pcimport_add_package pkgname pkgcallchain )
  if ( TARGET ${pkgname} OR ${pkgname} MATCHES "^\\$")
    return()
  endif()

  if ( ${pkgname}_WORKSPACE_SOURCE_DIR AND (NOT DEFINED ${pkgname}_BUILD_LOCAL OR "${${pkgname}_BUILD_LOCAL}") )
    add_subdirectory( ${${pkgname}_WORKSPACE_SOURCE_DIR} ${${pkgname}_WORKSPACE_BINARY_DIR} )
  elseif( "${${pkgname}_BUILD_LOCAL}" )
    # allow x_BUILD_LOCAL to just skip the package in the pkg-config search
  elseif( _pcimport_${pkgname}_cached AND NOT IGNORE_PKGCONFIG_IMPORT_CACHE )
    _bbs_pcimport_import_cached_target( ${pkgname} "${pkgcallchain}" )
  else()
    _bbs_pcimport_import_pkgconfig_target( ${pkgname} "${pkgcallchain}" )
  endif()
endfunction()

#
# Add the following target and all it's required dependencies
# as imported targets from it's entry in the cache
#
function( _bbs_pcimport_import_cached_target targetname pkgcallchain )
  message( VERBOSE "Importing cached ${targetname} (${_pcimport_${targetname}_version})" )

  if( _pcimport_${targetname}_location )
    add_library( ${targetname} STATIC IMPORTED GLOBAL )
    set_property( TARGET ${targetname} PROPERTY
                  IMPORTED_LOCATION ${_pcimport_${targetname}_location} )
  else()
      add_library( ${targetname} INTERFACE IMPORTED GLOBAL )
  endif()

  if( _pcimport_${targetname}_link_libraries OR ${targetname}_DEPS )
     set( link_libraries ${_pcimport_${targetname}_link_libraries} ${${targetname}_DEPS} )
     list( REMOVE_DUPLICATES link_libraries )
     set_property( TARGET ${targetname} PROPERTY INTERFACE_LINK_LIBRARIES ${link_libraries} )
  endif()

  if( _pcimport_${targetname}_include_directories )
    set_property( TARGET ${targetname} PROPERTY
                  INTERFACE_INCLUDE_DIRECTORIES ${_pcimport_${targetname}_include_directories} )
  endif()

  if( _pcimport_${targetname}_compile_definitions )
    set_property( TARGET ${targetname} PROPERTY
                  INTERFACE_COMPILE_DEFINITIONS ${_pcimport_${targetname}_compile_definitions} )
  endif()

  if( _pcimport_${targetname}_compile_options )
    set_property( TARGET ${targetname} PROPERTY
                  INTERFACE_COMPILE_OPTIONS ${_pcimport_${targetname}_compile_options} )
  endif()

  if( _pcimport_${targetname}_requires )
    _bbs_import_pkgconfig_targets( "${_pcimport_${targetname}_requires}" "${pkgcallchain}" )
  endif()
  
  # import user specified dependencies
  if( ${targetname}_DEPS )
    _bbs_import_pkgconfig_targets( "${${targetname}_DEPS}" "${pkgcallchain}" )
  endif()
endfunction()

#
# Add the following pkg-config and all it's required dependencies
# as imported targets from it's pkg-config file
#
function( _bbs_pcimport_import_pkgconfig_target pkgname pkgcallchain )
  set( saved_env_pkg_config_sysroot_dir $ENV{PKG_CONFIG_SYSROOT_DIR} )
  set( saved_env_pkg_config_path $ENV{PKG_CONFIG_PATH} )
  _bbs_pcimport_get_pcfile( ${pkgname} ${pkgname}_pcfile "${pkgcallchain}" )
  _bbs_pcimport_get_flags_from_pcfile( ${pkgname} ${${pkgname}_pcfile}
                                    ${pkgname}_libflags
                                    ${pkgname}_cflags
                                    ${pkgname}_requires
                                    ${pkgname}_version )
  message( VERBOSE "Importing ${pkgname} (${${pkgname}_version}) from ${${pkgname}_pcfile}")
  _bbs_pcimport_deduce_libs( ${pkgname} ${pkgname}_libflags )
  _bbs_pcimport_create_imported_target( ${pkgname} ${pkgname}_libflags )
  _bbs_pcimport_add_libs_to_target( ${pkgname} ${pkgname}_libflags ${pkgname}_requires )
  _bbs_pcimport_add_cflags_to_target( ${pkgname} ${pkgname}_cflags )
  _bbs_pcimport_cache_target( ${pkgname} ${pkgname}_requires )
  _bbs_import_pkgconfig_targets( "${${pkgname}_requires}" "${pkgcallchain}" )
  _bbs_import_pkgconfig_targets( "${${pkgname}_DEPS}" "${pkgcallchain}" )
  set( ENV{PKG_CONFIG_SYSROOT_DIR} ${saved_env_pkg_config_sysroot_dir} )
  set( ENV{PKG_CONFIG_PATH} ${saved_env_pkg_config_path} )
endfunction()

#
# Find the pkg-config file for the given pkgname and place it in result
#
function( _bbs_pcimport_get_pcfile pkgname result pkgcallchain )
  set(pc_paths)

  foreach( installation ${PKG_CONFIG_INSTALLATION_NAMES} )
    set( ENV{PKG_CONFIG_SYSROOT_DIR} ${${installation}_PKG_CONFIG_SYSROOT_DIR} )

    string(REPLACE ":" ";" paths "${${installation}_PKG_CONFIG_PATH}")
    list(APPEND pc_paths ${paths})

    if( _importpc_pcpath )
      string(REPLACE " " ";" paths "${_importpc_pcpath}")
      list(APPEND pc_paths ${paths})
    endif()

    foreach( path ${pc_paths} )
      if( EXISTS "${path}/${pkgname}.pc" )
        set(${result} "${path}/${pkgname}.pc" PARENT_SCOPE)
        return()
      endif()

      list(APPEND pc_paths "${path}")
    endforeach()
  endforeach()

  string( REGEX REPLACE ";+" " " paths "${pc_paths}" )
  message( FATAL_ERROR "Cannot find ${pkgname}.pc file in these paths: ${paths}\n[CALL_CHAIN=${pkgcallchain}]" )
endfunction()

#
# Extract the Libs, Cflags and Require lines from the given pcfile into the resultlists
#
macro( _bbs_pcimport_get_flags_from_pcfile pkgname pcfile libs-resultlist cflags-resultlist required-resultlist version-result )
  file( STRINGS ${pcfile} pccontents )
  _bbs_pcimport_expand_variables( pccontents )

  foreach( line ${pccontents} )
    # Escape $ with \$ so it can be passed to the macro
    string( REGEX REPLACE "\\$" "\\\\$" line "${line}" )
    _bbs_pcimport_import_line( "Libs" ${libs-resultlist} ${line} )
    _bbs_pcimport_import_line( "Libs.private" ${libs-resultlist}.private ${line} )
    _bbs_pcimport_import_line( "Cflags" ${cflags-resultlist} ${line} )
    _bbs_pcimport_import_line( "Requires" ${required-resultlist} ${line} SPLIT_CSV SKIP_LIB_VERSION)
    _bbs_pcimport_import_line( "Requires.private" ${required-resultlist}.private ${line} SPLIT_CSV SKIP_LIB_VERSION)
    _bbs_pcimport_import_line( "Version" ${version-result} ${line} )
  endforeach()
  list( APPEND ${libs-resultlist} "${${libs-resultlist}.private}" )
  list( APPEND ${required-resultlist} "${${required-resultlist}.private}" )
endmacro()

#
# Expands variables in pkg-config content
# E.g. if prefix=/opt/bb is in the contents then ${prefix}/include expands to /opt/bb/include
#
macro( _bbs_pcimport_expand_variables pccontents )
  list(REVERSE ${pccontents})
  foreach(pccontent ${${pccontents}})
    # Extract key using lazy search for "=", leading and trailing whitespace
    # will be stripped. E.g. "A = B = C" -> "A", "B = C". Empty keys are
    # allowed.
    if ( ${pccontent} MATCHES  "([^=]*)=(.*)" )
      string(STRIP "${CMAKE_MATCH_1}" CMAKE_MATCH_1)
      string(STRIP "${CMAKE_MATCH_2}" CMAKE_MATCH_2)
      string(REPLACE "\${${CMAKE_MATCH_1}}" "${CMAKE_MATCH_2}" ${pccontents} "${${pccontents}}")
    endif()
  endforeach()
  string(REPLACE "\${pc_sysrootdir}" "$ENV{PKG_CONFIG_SYSROOT_DIR}" ${pccontents} "${${pccontents}}")
endmacro()

#
# Import pkgconfig lines and expand the results into ; delimited lists
#
macro ( _bbs_pcimport_import_line match resultlist line )
  set(flag_args SPLIT_CSV SKIP_LIB_VERSION)
  cmake_parse_arguments( IMPORT_LINE "${flag_args}" "" "" ${ARGN} )
    string( REGEX REPLACE "^${match}:(.+)$" "\\1" output "${line}" )
    string( STRIP "${CMAKE_MATCH_1}" CMAKE_MATCH_1 )
     if( CMAKE_MATCH_1 )
      if (IMPORT_LINE_SKIP_LIB_VERSION)
        string( REGEX REPLACE "[<>=]=?[ ]*([.0-9]+\\.*)+" "" output "${CMAKE_MATCH_1}" )
      endif()
      string( STRIP "${output}" output )
      if ( output )
        string( REPLACE " " ";" ${resultlist} "${output}") #convert string to ; separated list
        if( IMPORT_LINE_SPLIT_CSV )
          string( REPLACE "," ";" ${resultlist} "${${resultlist}}" ) #convert , to ;
        endif()
      endif()
    endif()
endmacro()

#
# Declare the given pkgname as an imported target.
# Create a static library if the pkg has libs to link in.
# Create an interface library otherwise.
#
macro( _bbs_pcimport_create_imported_target pkgname libflags )
  if (${pkgname}_location)
    add_library( ${pkgname} STATIC IMPORTED GLOBAL )
    set_property( TARGET ${pkgname} PROPERTY
                  IMPORTED_LOCATION ${${pkgname}_location} )
  else()
    add_library( ${pkgname} INTERFACE IMPORTED GLOBAL )
  endif()
endmacro()

#
# Deduce the location and other link libraries flags
# for the given target using the supplied libflags list
#
# Defines:
#   - ${targetname}_libdirs
#   - ${targetname}_libname
#   - ${targetname}_misclinklibs
#   - [optional] ${targetname}_location
#
macro( _bbs_pcimport_deduce_libs targetname libflags )

  set (_bbs_static_blacklist "-ldl;-lrt;-lpthread")

  #split the flags into dirs, libraries and other flags
  set(${targetname}_libdirs "")
  set(${targetname}_misclinklibs "")
  foreach( ${targetname}_libflag ${${libflags}} )
    if( ${targetname}_libflag MATCHES "^-L(.+)$" )
      list( APPEND ${targetname}_libdirs $ENV{PKG_CONFIG_SYSROOT_DIR}${CMAKE_MATCH_1} )
    elseif( ${targetname}_libflag MATCHES "^-l(.+)$" AND NOT ${targetname}_libflag IN_LIST _bbs_static_blacklist )
      list( APPEND ${targetname}_libs ${CMAKE_MATCH_1} )
    elseif( ${targetname}_libflag MATCHES "^-(.+)$" )
      # add miscellaneous flags to the link line for the target
      list( APPEND ${targetname}_misclinklibs ${${targetname}_libflag} )
    else()
      # otherwise, assume we're given the full path to an object/archive to link in
      if( NOT ${targetname}_libflag MATCHES "^$ENV{PKG_CONFIG_SYSROOT_DIR}" )
        message( FATAL_ERROR "Libraries specified by path must be prefixed by the pkg-config \${pc_sysroot} variable" )
      endif()
      if( NOT EXISTS ${${targetname}_libflag} )
        message( FATAL_ERROR "Unable to find library provided by full path: ${${targetname}_libflag}" )
      endif()
      list( APPEND ${targetname}_libs ${${targetname}_libflag} )
    endif()
  endforeach()

  foreach( ${targetname}_lib ${${targetname}_libs} )
    # find the library filename, supporting GNU ld's '-l :filename' option
    set( ${targetname}_libname "" )
    if( ${targetname}_lib MATCHES "^:" )
      string( REPLACE ":" "" ${targetname}_libname "${${targetname}_lib}" )
    elseif( ${targetname}_lib MATCHES "^/" AND EXISTS ${${targetname}_lib} )
      # if we're given the path to a library, just use it and skip
      # calling find_library()

      # NOTE: it's important that we normalize the path here as multiple
      # references to the same file with distinct paths may confuse CMake's
      # dependency resolution algorithm. For example, if CMake sees the following
      # link lines

      # -lrdkafka++ -lrdkafka (expanded to /path/to/librdkakfa++.a /path/to/librdkafka.a)
      # /path/to/librdkafka++.a /path//to/librdkafka.a

      # it will incorrectly assume that librdkafka++.a DOES NOT depend on librdkafka.a,
      # may reorder the dependencies, producing an invalid final link line

      # see https://gitlab.kitware.com/cmake/cmake/blob/v3.12.2/Source/cmComputeLinkDepends.cxx#L51-80
      file( TO_CMAKE_PATH "${${targetname}_lib}" lib${${targetname}_lib} )
    else()
      set( ${targetname}_libname "lib${${targetname}_lib}.a" )
    endif()

    # finds absolute filename for static or shared and stores it in the cache
    if( NOT lib${${targetname}_lib} )
      find_library( lib${${targetname}_lib}
                    NAMES "${${targetname}_libname}" ${${targetname}_lib}
                    HINTS ${${targetname}_libdirs}
                    NO_CMAKE_SYSTEM_PATH ) # <--turns off finding full path for things like socket, pthread etc
    endif()

    # mark as advanced visibility when viewing the cache with ccmake
    mark_as_advanced( FORCE lib${${targetname}_lib} )

    if ( NOT lib${${targetname}_lib} )
      # library not found - add the libname to the link line (e.g. pthread)
      list( APPEND ${targetname}_misclinklibs ${${targetname}_lib} )
    elseif( NOT ${targetname}_location )
      # first library listed - set it as the target's library location
      set( ${targetname}_location ${lib${${targetname}_lib}} )
    else()
      # other libraries - add full library path to the link line
      list( APPEND ${targetname}_misclinklibs ${lib${${targetname}_lib}} )
    endif()
  endforeach()
endmacro()

#
# Set the IMPORTED_LOCATION and INTERFACE_LINK_LIBRARIES properties
# on the given target using the supplied libflags list
#
macro( _bbs_pcimport_add_libs_to_target targetname libflags requires_list )
  if (${targetname}_misclinklibs)
      set_property( TARGET ${targetname} APPEND PROPERTY
                     INTERFACE_LINK_LIBRARIES ${${targetname}_misclinklibs} )
  endif ()
  # add the required pkgs to the link. These will be resolved as full fledged targets
  if( ${requires_list} OR ${targetname}_DEPS )
    set( link_libraries ${${requires_list}} ${${targetname}_DEPS} )
    list( REMOVE_DUPLICATES link_libraries )
    set_property( TARGET ${targetname} APPEND PROPERTY
                  INTERFACE_LINK_LIBRARIES ${link_libraries})
  endif()
endmacro()

#
# Set the INTERFACE_COMPILE_DEFINITIONS, INTERFACE_INCLUDE_DIRECTORIES
# and INTERFACE_COMPILE_OPTIONS propertieson the given target
# using the supplied cflags list
#
macro( _bbs_pcimport_add_cflags_to_target targetname cflags )
  foreach( ${targetname}_cflag ${${cflags}} )
    if( ${targetname}_cflag MATCHES "-D(.+)" )
      set_property( TARGET ${targetname} APPEND PROPERTY
                    INTERFACE_COMPILE_DEFINITIONS ${CMAKE_MATCH_1} )
    elseif( ${targetname}_cflag MATCHES "-I(.+)" )
      file( TO_CMAKE_PATH $ENV{PKG_CONFIG_SYSROOT_DIR}${CMAKE_MATCH_1} ${targetname}_idir )
      set_property( TARGET ${targetname} APPEND PROPERTY
                    INTERFACE_INCLUDE_DIRECTORIES ${${targetname}_idir} )
    else()
      set_property( TARGET ${targetname} APPEND PROPERTY
                     INTERFACE_COMPILE_OPTIONS ${${targetname}_cflag} )
    endif()
  endforeach()
endmacro()

#
# stores the target in the cache so we don't need to recalc from the .pc file
#
macro( _bbs_pcimport_cache_target targetname requires_list )
  set( _pcimport_${targetname}_cached TRUE CACHE INTERNAL "" )

  get_target_property(prop ${targetname} TYPE )
  if ( NOT "${prop}" STREQUAL INTERFACE_LIBRARY )
    get_target_property(prop ${targetname} IMPORTED_LOCATION )
    if ( prop )
      set( _pcimport_${targetname}_location ${prop} CACHE INTERNAL "" )
    endif()
  endif()

  get_target_property( prop ${targetname} INTERFACE_LINK_LIBRARIES )
  if ( prop )
    set( _pcimport_${targetname}_link_libraries ${prop} CACHE INTERNAL "" )
  endif()

  get_target_property( prop ${targetname} INTERFACE_INCLUDE_DIRECTORIES )
  if ( prop )
    set( _pcimport_${targetname}_include_directories ${prop} CACHE INTERNAL "" )
  endif()

  get_target_property( prop ${targetname} INTERFACE_COMPILE_DEFINITIONS )
  if ( prop )
    set( _pcimport_${targetname}_compile_definitions ${prop} CACHE INTERNAL "" )
  endif()

  get_target_property( prop ${targetname} INTERFACE_COMPILE_OPTIONS )
  if ( prop )
    set( _pcimport_${targetname}_compile_options ${prop} CACHE INTERNAL "" )
  endif()

  if ( ${requires_list} )
    set( _pcimport_${targetname}_requires ${${requires_list}} CACHE INTERNAL "" )
  endif()

  if ( ${targetname}_version )
    set( _pcimport_${targetname}_version ${${targetname}_version} CACHE INTERNAL "" )
  endif()

endmacro()
