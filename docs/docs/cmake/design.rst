.. _build_system_design-top:

===============================
CMake Build System Organization
===============================

.. _build_system_design-intro:

Introduction
============

BDE Cmake build system is organized as a set of the modules that implement
processing of the :ref:`BDE-style repositories <bde_repo-top>`.

Supported build actions include:

* Building individual components, packages, or package-groups.
* Building and running test drivers.
* Generating installation targets for build artefacts and packaging metadata.

The build system is built on top of `CMake <https://cmake.org>`_ and supports
all of the vanilla CMake commands and options, as well as additional
configuration and build options for working with BDE-style repositories.

Design
======




.. _build_system_design-build-targets:

Build Targets
=============

The build system generates following build targets:

* Package group targets
* Package targets
* Standalone/thirdparty targets
* Component test driver targets

.. _build_system_design-install-components:

Install Components
==================

The build system creates following install components for a given ``uor``:

+---------------------------------+------------------------------------+
| Name of the component           | Description                        |
+=================================+====================================+
| uor                             | Ufid-qualified UOR library         |
+---------------------------------+------------------------------------+
| uor-headers                     | Header files for the UOR           |
+---------------------------------+------------------------------------+
| uor-symlinks                    | Ufid-quialified symlinks to the    |
|                                 | library.                           |
+---------------------------------+------------------------------------+
| uor-release-symlink             | Non-ufid qualified symlink to      |
|                                 | the libkrary                       |
+---------------------------------+------------------------------------+
| uor-meta                        | UOR meta information (internal     |
|                                 | meta for build and packaging)      |
+---------------------------------+------------------------------------+
| uor-pkgconfig                   | pkgconfig file for the library     |
+---------------------------------+------------------------------------+


