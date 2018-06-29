.. _customization-top:

==============================
BDE Build System Customization
==============================

This section describes how to use BDE Build System with external
projects.

.. _customization-1:

Overview
--------

BDE build system allow clients to customize processing at any level of the BDE
repository structure - package groups, packages (including standalones and
thirdparty) - without any changes in the build system itself.

The build system also desinged with the concepts of "layer". The layer is
responsible to handle a specific set of functionality within the build system.

For example, the ``ufid`` layer handles all logic for ``UFID`` processing -
mapping the flags supplied in the ufid to internal CMake build types, build 
flags, the installation ufid-qualified naming scheme. The layer can be
changed to support different ways of passing build configuration.

The ``base`` layer is responsible for core processing the :ref:`BDE-style
repositories <bde_repo-top>` - parsing directory structure, detecting and
loading customization files, parsing ``.mem`` and ``..dep`` files, creating low
level system targets, tests discovery and dependency resolution.

How to enable BDE build system for your project
-----------------------------------------------

To enable BDE build system for a repository that follows the :ref:`BDE-style
repositories <bde_repo-top>` structure, add the ``project.cmake`` and
``CmakeLists.txt`` files with the following content into top level or your
repository:

  .. code-block:: cmake

     # project.cmake
     include(legacy/wafstyleout)
     include(layers/package_libs)
     include(layers/ufid)
     include(layers/install_pkg_config)
     include(layers/install_cmake_config) 

  .. code-block:: cmake

     # CmakeLists.txt
     cmake_minimum_required(VERSION 3.8)

     get_filename_component(repoName ${CMAKE_CURRENT_LIST_DIR} NAME)

     project(${repoName})

     include(bde_workspace)

     bde_process_workspace(
         ${CMAKE_CURRENT_LIST_DIR}
     )

  .. note::
     Sample ``CmakeLists.txt`` and ``project.cmake`` files can be found 
     in ``<bde-tools>/share/`` directory.


How to extend package processing
--------------------------------

BDE build system allows clients to customize processing of individual packages
within the package group. Customization file should be named
``<package_name>.cmake`` and placed into the ``package`` folder of the package.

For clarity, the following example will customize the processing of the abstract
``tstex`` package of the ``tst`` package group.

The customization file should contain the following boiler-place code:

  .. code-block:: cmake
     :linenos:

     # groups/tst/tstex/package/tstex.cmake
     include(bde_interface_target)
     include(bde_package)
     include(bde_struct)

     bde_prefixed_override(tstex process_package)
     function(tstex_process_package retPackage)
         process_package_base("" package ${ARGN})

         bde_struct_get_field(interfaceTarget ${package} INTERFACE_TARGET)

         # Customization code
         # ...

         bde_return(${package})
     endfunction()

The code above overrides the function ``process_package`` provided by base
layer of BDE build system. The base layer is responsible for creating so called
package interface target. This object contains information about the given
package - the list of components, dependencies, test drivers, etc. The call to
the ``process_package_base()`` on line 8 calls the ``process_package`` that was
in effect before override ( effectively - the base layer ) which creates and
popilates the package interface target. On line 10, the interface target is
looked up and loaded in the ``interfaceTarget`` variable.

The interface target has ``INTERFACE`` and ``PRIVATE`` parts. Libraries and
targets added to the ``INTERFACE`` part are linked to, and are made part of the
link interface. Libraries and targets added to the ``PRIVATE`` are linked to,
but are not made part of the link interface.

Customization code can then modify the interface target.

To link a special library ``xyz`` (and make this library part of the package
link interface):

  .. code-block:: cmake

     bde_interface_target_link_libraries(
         ${interfaceTarget}
         PUBLIC
            xyz
     )

To add a special compiler definition for compiling ``xyz``:

  .. code-block:: cmake

     bde_interface_target_compile_definitions(
         ${interfaceTarget}
         PRIVATE
            EXTRA_DEFINITION
     )

To add a special compile option for ``xyz`` (the example uses CMake generator
expression syntax to add compile option only for MSVC compiler):

  .. code-block:: cmake

     bde_interface_target_compile_options(
         ${interfaceTarget}
         PRIVATE
             $<$<CXX_COMPILER_ID:MSVC>: /bigobj>
     )

