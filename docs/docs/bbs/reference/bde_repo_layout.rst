.. _bde_repo_layout-top:

====================
BDE-Style Repository
====================

Introduction
============

For a repository to be buildable with the BDE tools, it must have the following
characteristics:

-  Must follow :ref:`bde_repo_layout-physical_layout`.

-  Must provide :ref:`bde_repo_layout-metadata`.

Terminology
===========

  .. glossary::

    component
      A component comprises a ``.h`` and ``.cpp`` pair, along with an
      associated test driver (``.t.cpp`` file).  E.g., the component
      ``bslstl_map`` comprises ``bslstl_map.h`` and ``bslstl_map.cpp``, and is
      associated with the test driver file ``bslstl_map.t.cpp``.

    package
      A physical unit that comprises a collection of related components.

    package group
      A physically cohesive unit that comprises a collection of packages.

    stand-alone package
      A package that does not belong to a package group.

.. _bde_repo_layout-uor:

  .. glossary::

    UOR (Unit of Release)
      A stand-alone package or a package group.  Generally, UORs are the
      libraries (``.a`` files or applications) that get deployed on a system.
      The names of UORs must be globally unique.

.. _bde_repo_layout-physical_layout:

BDE Physical Code Organization
==============================

.. _bde_repo_layout-units:

Units and Unique Names
----------------------

Components, Packages, and Package Groups are all considered physical units
inside of a repository.  Unit names have the constraint that they must be
globally unique.  This characteristic of units greatly simplifies how we can
reason about the source code.

Having globally unique component names allows BDE to use direct include
directives instead of relative ones, i.e., using ``#include <bdlt_date.h>``
instead of ``#include "include/header.h"``.  Using direct includes affords us
flexibility with development and deployment.  Otherwise, we would not be able
to extract an arbitrary subset of our code for point distributions without
recreating our entire directory structure.  Separately, our development process
for package groups may choose to locate headers differently when using code
withing the group compared with once the code is released.

The argument for angle brackets rather than quotes is similar: Angle brackets
``<>`` provide full control over source of headers and can simulate the common
usage of double quotes ``""`` simply by adding ``-I.`` to the compile line.

Having unique unit names is achieved in BDE via using a central name registry
as well as following certain naming conventions:

  - The name of each package group is a unique mnemonic exactly three
    characters long (e.g., ``bsl``).
  - The name of a package should be prefixed with the name of the package group
    and should also be a mnemonic no longer than six characters (e.g.,
    ``bslma``).
  - The name of a component should be prefixed by the name of the package in
    which the component is contained followed by an ``_`` (e.g.,
    ``bslma_allocator``).
  - The name of a stand-alone package should be prefixed with ``a_`` if it's an
    adapter, and ``m_`` if it's an application.
  - All of the names should be in lower case.

For more details on naming conventions and design rules of components,
packages, and package groups, please see `BDE Physical Code Organization
Guidelines
<https://github.com/bloomberg/bde/wiki/physical-code-organization#physical-code-organization>`_.

Regular Components, Packages, and Package Groups
------------------------------------------------

The source code must be organized into 3 hierarchical levels of aggregation (in
order from smallest to largest): components, packages, and package groups.  A
package comprises a set of components; a package group comprises a set of
packages.

By default, package groups should be located in ``<repo_root>/groups``, and a
package belonging to a package group should be a sub-directory of that package
group.

For example, in BDE, the ``bsl`` package group contains the packages ``bsls``
and ``bslma`` (in addition to many other packages).  The ``bsls`` package
contains the components ``bsls_util`` and ``bsls_ident``; The ``bslma`` package
contains the components ``bslma_allocator`` and ``bslma_testallocator``.  These
physical units should have the following structure on the file system:

  ::

    <repo_root>
     `-- groups
         |-- bsl
         |   |-- group
         |   |   |-- bsl.mem
         |   |   |-- bsl.dep
         |   |-- bsls
         |   |   |-- package
         |   |   |   |-- bsls.mem
         |   |   |   |-- bsls.dep
         |   |   |-- bsls_ident.h
         |   |   |-- bsls_ident.cpp
         |   |   |-- bsls_ident.t.cpp
         |   |   |-- bsls_util.h
         |   |   |-- bsls_util.cpp
         |   |   |-- bsls_util.t.cpp
         |   `-- bslma
         |       |-- package
         |       |   |-- bslma.mem
         |       |   |-- bslma.dep
         |       |-- bslma_allocator.h
         |       |-- bslma_allocator.cpp
         |       |-- bslma_allocator.t.cpp
         |       |-- bslma_testallocator.h
         |       |-- bslma_testallocator.cpp
         |       `-- bslma_testallocator.t.cpp
         `-- bdl
             |
             `-- ...
    
Stand-Alone and Application Packages
------------------------------------

Stand-alone packages are packages that do not belong to a package group.
An application package is a special kind of stand-alone package, with the main
difference being that an application package contains a ``<package>.m.cpp``
file in which the ``main`` function is defined.

By default, application packages should be located in the ``applications``
directory, adapter packages should be located in the ``adapters`` directory,
and other types of stand-alone packages can be located in the ``standalones``
directory.

Non-standard Package Types
--------------------------

BDE repository can include source files that don't conform to a standard
BDE-style package.  Often, the reason is to bundle an existing third-party
package inside of a repository.

There are two common types of non-conforming packages: header-only packages and
third-party packages.

Header-only Packages
````````````````````

Header-only packages are packages that contain header-only library or just a
set of headers. These packages do not behave like regular BDE packages in
that they do not contain BDE components.  Nonetheless, ``mem`` file in those
packages still can be used to provide the list of headers contained in the
package.

Third-Party Packages
````````````````````

Third-party packages are not BDE-style packages and do not contain any
:ref:`bde_repo_layout-metadata`.  By default, these packages are located under
the ``thirdparty`` directory, and must be provided with a custom
``CMakeLists.txt``.

  .. note::

    Third-party packages mainly exist to simplify the build process for certain
    low-level libraries.  A third-party package can be easily moved to its own
    repository if so desired, in which case the third-party package must be
    first separately built and installed before the original repository that
    depended on that third-party package can be built.

.. _bde_repo_layout-metadata:

BDE Metadata
============

There are 3 types of metadata that can be applied to either a package or a
package group in a BDE-style repository.  Two types of metadata are
required:

 * ``mem``

   Define the members of a package or package group.

 * ``dep``

   Define the dependencies of a package or package group.

And additional type of metadata is optional:

 * ``t.dep``

   Define the dependencies of the test drivers for a package or package group.

Each type of metadata should be stored as a file in either the ``package``
sub-directory in a package or the ``group`` sub-directory in a package group.
A metadata file's name should begin with the package or package group to which
it applies, followed by a ``.``, and finally followed by the type of the
metadata.  For example, in the BDE libraries, the ``mem`` file of the package
group ``bsl`` is named ``bsl.mem`` and located at the path
``<repo_root>/groups/bsl/group/bsl.mem``; the ``dep`` file of the package
``bslstl`` is named ``bslstl.dep`` and located at the path
``<repo_root>/groups/bsl/group/bslstl.dep``.

.. _bde_repo_layout-mem:

Mem File
--------

A package ``mem`` file defines the list of member components in the package.  A
package group ``mem`` file defines the list of member packages in the package
group.

Each line of a ``mem`` file contains a single entry (a component or a package).
Blank lines are ignored and a ``#`` within a line marks the remainder as a
comment.

For example:

* the ``mem`` file for the ``bsl`` group `bsl.mem
  <https://github.com/bloomberg/bde/blob/main/groups/bsl/group/bsl.mem>`_

* the ``mem`` file for the ``bslma`` package `bslma.mem
  <https://github.com/bloomberg/bde/blob/main/groups/bsl/bslma/package/bslma.mem>`_

.. _bde_repo_layout-dep:

Dep File
--------

A ``dep`` file describes the allowed dependencies for either a package
or a package-group.  A package-group's ``dep`` file describes the other
package-groups that components within that package-group may depend on.
Similarly, a package's ``dep`` file describes the other packages within
the *same* package-group that components within that package may
depend on.  Note that a package's ``dep`` file should *not* refer to other
package-groups, since the dependencies on other package-groups are
inherited from the package-group-level ``dep`` file.

Each line of a ``dep`` file contains a single entry (a package or a package
group).  Blank lines are ignored and a ``#`` within a line marks the remainder
as a comment.

For example:

* The ``dep`` file for the ``bdl`` group `bdl.dep <https://github.com/bloomberg/bde/blob/main/groups/bdl/group/bdl.dep>`_

* The ``dep`` file for the ``bslma`` package `bslma.dep <https://github.com/bloomberg/bde/blob/main/groups/bsl/bslma/package/bslma.dep>`_


