include_guard()

# :: bbs_load_conan_build_info ::
# -----------------------------------------------------------------------------
# The function tries to detect the use of conan and loads the
# 'conan_build_info.cmake' file into memory
function(bbs_load_conan_build_info)
    if (TARGET "CONAN_PKG::bde-tools")
        message(STATUS "Conan package already loaded")
        return()
    endif()

    set(CONAN_BUILD_INFO ${CMAKE_BINARY_DIR}/conanbuildinfo.cmake)
    if (EXISTS ${CONAN_BUILD_INFO})
        message(STATUS "Found ${CMAKE_BINARY_DIR}/conanbuildinfo.cmake")
        include(${CONAN_BUILD_INFO})
        conan_basic_setup(TARGETS)
    endif()
endfunction()

# :: bbs_import_conan_target ::
# -----------------------------------------------------------------------------
# The function tries to resolve a single dependency using conan targets.  The
# main purpose of the function is to resolve the disparity of target names, and
# work around the current limitation in the conan cmake generator creating
# non-global targets that cannot be aliased
function(bbs_import_conan_target depName)
    bbs_assert_no_unparsed_args("")

    set(conanDep "CONAN_PKG::${depName}")
    if (TARGET ${conanDep})
        message(VERBOSE "Found dependency ${depName} in conan")

        # After https://github.com/conan-io/conan/issues/3482 is resolved this
        # should be just an alias
        add_library(${depName} INTERFACE IMPORTED)
        target_link_libraries(${depName} INTERFACE ${conanDep})
        foreach(prop INTERFACE_LINK_LIBRARIES INTERFACE_INCLUDE_DIRECTORIES INTERFACE_COMPILE_DEFINITIONS INTERFACE_COMPILE_OPTIONS)
            get_property(tmpProp TARGET ${conanDep} PROPERTY ${prop})
            set_property(TARGET ${conanDep} PROPERTY ${prop} ${tmpProp})
        endforeach()
    endif()
endfunction()

# Try to find external dependency using CMake export.
function(bbs_import_cmake_config depName)
    bbs_assert_no_unparsed_args("")

    string(REPLACE "-" "_" libName ${depName})

    find_package(
        ${libName}
        NO_SYSTEM_ENVIRONMENT_PATH
        NO_CMAKE_PACKAGE_REGISTRY
        QUIET
        GLOBAL
    )

    if(NOT ${libName}_FOUND)
        message(FATAL_ERROR "${libName} NOT FOUND")
    endif()
    if(TARGET ${libName})
        message(VERBOSE "CMake config found for ${libName}")
        if (NOT TARGET ${depName})
            add_library(${depName} ALIAS ${libName})
        endif()
    endif()
endfunction()

# Try to find external dependency by looking up the library with
# the specified name.
function(bbs_import_raw_library depName)
    bbs_assert_no_unparsed_args("")

    string(REPLACE "-" "_" libName ${depName})

    foreach (prefix IN LISTS CMAKE_PREFIX_PATH)
        set(libraryPath "${prefix}/${CMAKE_INSTALL_LIBDIR}")
        set(includePath "${prefix}/include")

        message(VERBOSE "Looking in : ${libraryPath}, ${CMAKE_STATIC_LIBRARY_SUFFIX}")
        message(VERBOSE "Headers in : ${includePath}")
        find_library(
            rawLib_${libName}
            NAMES
                lib${libName}${CMAKE_STATIC_LIBRARY_SUFFIX}
                ${libName}${CMAKE_STATIC_LIBRARY_SUFFIX}
            PATHS
                "${libraryPath}"
            NO_DEFAULT_PATH
        )
        if(rawLib_${libName})
            message(VERBOSE "Found(raw): ${rawLib_${libName}}")
            add_library(${depName} INTERFACE IMPORTED)
            set_target_properties(
                ${depName}
                PROPERTIES
                INTERFACE_LINK_LIBRARIES "${rawLib_${libName}}"
                INTERFACE_INCLUDE_DIRECTORIES "${includePath}"
            )
            return()
        endif()
    endforeach()
endfunction()
