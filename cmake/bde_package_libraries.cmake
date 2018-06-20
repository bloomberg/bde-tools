include(bde_include_guard)
bde_include_guard()

bde_register_struct_type(
    BDE_PACKAGELIBS_PACKAGE_TYPE
        INHERIT BDE_PACKAGE_TYPE
        # The dependencies on other packages are used for manual detection of
        # unfulfilled inter-package dependencies (due to CMake's object library) deficiencies.
        # If the object library is used, the sources will contain a generator
        # expression expanding to list of object files of the OBJ_TARGET.
        DEPENDS

        # For the BDE style of building tests - i.e., build the package libraries first
        # and then link tests with package libraries as opposed to package group library -
        # an object library is created to avoid double-compiling the sources for package
        # and package group libraries. In this case, the TARGET denotes the package library
        # and contains the usage requirements of the package (i.e., INTERFACE part of the INTERFACE_TARGET),
        # whereas the OBJ_TARGET denotes the object library and uses the build requirements
        # of the package (i.e., PRIVATE part of the INTERFACE_TARGET). Note that the
        # generator expressions (e.g., from the common interface target) are evaluated
        # on the OBJ_TARGET in this case (see bde/bde repository for an example of use).
        TARGET
        OBJ_TARGET
             # INTERFACE_TARGETS's INTERFACE linked to TARGET, and PRIVATE - to OBJ_TARGET
)

function(bde_package_create_target package)
    bde_struct_get_field(packageTarget ${package} NAME)
    bde_struct_get_field(headers ${package} HEADERS)
    bde_struct_get_field(sources ${package} SOURCES)
    bde_struct_get_field(packageInterface ${package} INTERFACE_TARGET)
    bde_struct_get_field(depends ${package} DEPENDS)

    if(sources)
        # object library
        set(packageObjTarget ${packageTarget}-obj)
        add_library(
            ${packageObjTarget}
            OBJECT EXCLUDE_FROM_ALL
            ${sources} ${headers}
        )
        set(packageObjects $<TARGET_OBJECTS:${packageObjTarget}>)
        bde_struct_set_field(${package} SOURCES ${packageObjects})
        bde_struct_set_field(${package} OBJ_TARGET ${packageObjTarget})

        # CMake as of 3.10 does not allow calling target_link_libraries
        # on OBJECT libraries. This command, however successfully imports
        # the build requirements, such as compiler options and include
        # directories
        bde_interface_target_name(
            privatePackageRequirements ${packageInterface} PRIVATE
        )

        set_target_properties(
            ${packageObjTarget}
            PROPERTIES
                LINK_LIBRARIES
                "${depends};${privatePackageRequirements}"
        )

        # target for tests
        add_library(${packageTarget} EXCLUDE_FROM_ALL ${packageObjects})
    else()
        # Add IDE target (https://gitlab.kitware.com/cmake/cmake/issues/15234)
        add_custom_target(${packageTarget}-headers SOURCES ${headers})

        # target for tests
        add_library(${packageTarget} INTERFACE)
    endif()

    # Set up usage requirements for the package target
    bde_interface_target_name(
        interfacePackageRequirements ${packageInterface} INTERFACE
    )
    target_link_libraries(
        ${packageTarget} INTERFACE ${depends} ${interfacePackageRequirements}
    )

    bde_struct_set_field(${package} TARGET ${packageTarget})
    bde_link_target_to_tests(${package})

    foreach(field HEADERS SOURCES DEPENDS)
        bde_struct_mark_field_const(${package} ${field})
    endforeach()
endfunction()