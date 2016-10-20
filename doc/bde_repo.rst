.. _bde_repo-top:

====================
BDE-Style Repository
====================

Introduction
============

For a repository to be buildable with the :ref:`waf-top`, it must
have the following characteristics:

-  Must follow :ref:`bde_repo-physical_layout`.

-  Must provide :ref:`bde_repo-metadata`.

Terminology
===========

.. glossary::

   component
       A component comprises a .h and .cpp pair, along with an associated test
       driver (.t.cpp file).  E.g., the component bslstl_map comprises
       ``bslstl_map.h`` and ``bslstl_map.cpp``, and is associated with the test
       driver file ``bslstl_map.t.cpp``.

   package
       A physical unit that comprises a collection of related components.

   package group
       A physically cohesive unit that comprises a collection of packages.

   stand-alone package
       A package that does not belong to a package group.

.. _bde_repo-uor:

.. glossary::
   UOR (Unit of Release)
       A stand-alone package or a package group.  Generally, UORs are the
       libraries (.a files or applications) that gets deployed on a system.
       The names of UORs must be globally unique.

.. _bde_repo-physical_layout:

BDE Physical Code Organization
==============================

.. _bde_repo-units:

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

- The name of each package group is a unique mnemonic exactly three characters
  long (e.g., ``bsl``).
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
Guidelines <https://github.com/bloomberg/bde/wiki/physical-code-organization#physical-code-organization>`_.

Normal Components, Packages, and Package Groups
-----------------------------------------------

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
         |   |-- bsls
         |   |   |-- bsls_ident.h
         |   |   |-- bsls_ident.cpp
         |   |   |-- bsls_ident.t.cpp
         |   |   |-- bsls_util.h
         |   |   |-- bsls_util.cpp
         |   |   |-- bsls_util.t.cpp
         |   `-- bslma
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
Applications are a special kind of stand-alone package, with the main
difference being that an application package contains a ``<package>.m.cpp``
file in which the ``main`` function is defined.

By default, application packages should be located in the ``applications``
directory, adapter packages should be located in the ``adapters`` directory,
and other types of stand-alone packages can be located in the ``standalones``
directory.

Non-Conforming Package Types
----------------------------

Sometimes, we may want to include source files that don't conform to a standard
BDE-style package.  Often, the reason is to bundle an existing third-party
package inside of a repository.

There are two types of non-conforming packages: ``plus`` packages and
third-party packages.

Plus Packages
`````````````
``Plus`` packages are packages having a name containing a ``+``, e.g.,
``bsl+bslhdrs``.  These packages do not behave like regular BDE packages in
that they do not contain BDE components.  Therefore, they do not need ``mem``
files.  (Having an empty ``mem`` file is also permitted.)

The test drivers for these packages are located in the ``test`` sub-directory.
These tests are run only one time unlike BDE-style test drivers, which get
run repeatedly with incrementing case numbers as arguments.

The build behavior for these packages is that all source files in the root
directory of the package are built into a library.

Third-Party Packages
````````````````````

Third-party packages are not BDE-style packages and do not contain any
:ref:`bde_repo-metadata`.  By default, these packages are located under the
``third-party`` directory, and they are built in a custom way that is defined
by a directory local ``wscript``.

The ``wscript`` in each third-party package should not depend on BDE's ``waf``
customizations, and the ``wscript`` should generate a ``pkg-config`` file in
the same way as other types of UORs.  For an example, see the `wscript
<https://github.com/bloomberg/bde/blob/master/third-party/inteldfp/wscript>`_
of the ``inteldfp`` third-party package in BDE.

.. note::

   Third-party packages mainly exist to simplify the build process for
   certain low-level libraries.  A third-party package can be easily moved to
   its own repository if so desired, in which case the third-party package must
   be first separately built and installed before the original repository that
   depended on that third-party package can be built.

.. _bde_repo-layout_customize:

Customizing The Repository Layout
---------------------------------

The layout of the repository can be customized using a JSON configuration file
``.bdelayoutconfig`` located in the root of the repository.

Here is the default layout configuration:
::

    {
        "group_dirs": ["groups", "enterprise", "wrappers"],
        "app_package_dirs": ["applications"],
        "stand_alone_package_dirs": ["adapters", "standalones"],
        "third_party_package_dirs": ["third-party"],
        "group_abs_dirs": []
    }

Description of Fields:

- ``group_dirs``

  Relative path to directories each containing multiple package groups.

- ``app_package_dirs``

  Relative path to directories each containing multiple application packages.

- ``third_party_package_dirs``

  Relative path to directories each containing multiple third-party
  directories.

- ``stand_alone_package_dirs``

  Relative path to directories each containing multiple stand-alone packages.

- ``group_abs_dirs``

  Relative path to directories each pointing to the root of a package group.

An sample configuration file can be found at
``<bde-tools>/share/sample-config/bdelayoutconfig.sample``.

.. _bde_repo-metadata:

BDE Metadata
============

There are 6 types of metadata that can be applied to either a package or a
package group in a BDE-style repository.  Two types of metadata are
required:

-  ``mem``

   Define the members of a package or package group.

-  ``dep``

   Define the dependencies of a package or package group.

And four types of metadata are optional:

-  ``opts``

   Define the build options used internally.

-  ``defs``

   Define the build options visible externally.

-  ``caps``

   Define the supported platforms and build types (capability).

-  ``pub``

   Define the header files to be installed from the package (public).

Each type of metadata should be stored as a file in either the
``package`` sub-directory in a package or the ``group`` sub-directory in
a package group.  A metadata file's name should begin with the package or
package group to which it applies, followed by a ``.``, and finally
followed by the type of the metadata.  For example, in the BDE libraries,
the ``mem`` file of the package group ``bsl`` is named ``bsl.mem`` and
located at the path ``<repo_root>/groups/bsl/group/bsl.mem``; the
``dep`` file of the package ``bslstl`` is named ``bslstl.dep`` and
located at the path ``<repo_root>/groups/bsl/group/bslstl.dep``.

.. index::
   single: mem file

.. _bde_repo-mem:

Mem File
--------

A package ``mem`` file defines the list of member components in the
package.  A package group ``mem`` file defines the list of member
packages in the package group.

Each line of a ``mem`` file contains a single entry (a component or a package).
Blank lines are ignored and a ``#`` within a line marks the remainder as a
comment.

For example:

* the ``mem`` file for the bsl group `bsl.mem <https://github.com/bloomberg/bde/blob/master/groups/bsl/group/bsl.mem>`_

* the ``mem`` file for the bslma package `bslma.mem <https://github.com/bloomberg/bde/blob/master/groups/bsl/bslma/package/bslma.mem>`_

.. index::
   single: dep file

.. _bde_repo-dep:

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

* The ``dep`` file for the bdl library:

  `bdl.dep <https://github.com/bloomberg/bde/blob/master/groups/bdl/group/bdl.dep>`_

* The ``dep`` file for the bslma library:

  `bslma.dep <https://github.com/bloomberg/bde/blob/master/groups/bsl/bslma/package/bslma.dep>`_

.. _bde_repo-options_format:

Options File Format
-------------------

``opts``, ``defs``, and ``cap`` files are all written in the options
file format.

The options file format comprises a set of option rules, processed from
top to bottom.  Each rule contains a condition to match based on the
platform and configuration and modifies a variable (representing an
option) if that condition is met.

More accurately, a rule consists of five fields, which together provide
the criteria under which it applies, and the variable name and value it
contributes.  In order, the five fields are:

1. An optional command that describes how to combine the value with the
   accumulated value of the variable produced by the rules that preceded
   this rule.

2. A wildcard UPLID that defines what range of platforms the option
   applies to.  The wildcard UPLID can be as vague or precise as
   necessary, and may wildcard (``*``) any of the six UPLID elements
   that do not constrain it.  An option rule may match all UPLIDS, in
   which case its wildcard UPLID is just ``*``.

3. A UFID flag combination that defines the build type flags that apply
   to it.  An option may apply to all build types, in which case the flag
   combination is ``_``.

4. The name of the variable to which the rule contributes.

5. The value contributed by the rule.  This may be empty.

For example, here is a rule that sets the variable ``EXC_CXXFLAGS``:

::

    !! unix-SunOS-*-*-cc  exc  EXC_CXXFLAGS = -features=except

The ``!!`` command states that the value should completely override any
existing values for the ``EXC_CXXFLAGS``, but only if the OS type is
``unix``, the platform is ``SunOS``, the compiler is cc, and if an
exception-enabled build was requested with the ``exc`` UFID.

The first three fields of an option rule are described in more detail in
the three sections below.

Each of the ``opts``, ``defs``, and ``cap`` files use a predefined set of
variables, which are are described in their respective sections below.
For example, ``opts`` and ``defs`` use the value of the variable
``BDEBUILD_CFLAGS`` as the options to pass to the C compiler.

Rule Commands
`````````````

The first field of an option rule is an *optional* command that
describes how to combine the value of the current rule with the value
accumulated by previous rules.  The following commands are supported:

+---------+----------+------------------------------------------------------+
| Command | Meaning  | Description                                          |
+=========+==========+======================================================+
| ``++``  | Add      | Add to end of value, with a leading space (default). |
+---------+----------+------------------------------------------------------+
| ``--``  | Insert   | Add to start of value, with a following space.       |
+---------+----------+------------------------------------------------------+
| ``>>``  | Append   | Add to end of value directly, no leading space.      |
+---------+----------+------------------------------------------------------+
| ``<<``  | Prepend  | Add to start of value directly, no following space.  |
+---------+----------+------------------------------------------------------+
| ``!!``  | Override | Completely replace the prior value.                  |
+---------+----------+------------------------------------------------------+

The default command if none is supplied is to append with a leading
space (``++``).


.. index::
   single: UPLID

.. _bde_repo-uplid:

UPLID
`````

The second field of an option rule is a wildcard UPLID.  UPLID stands for
Universal Platform ID.  It is used to identify the platform and
tool-chain used to build the repository.  This identifier comprises the
following parts (in order) joined together with the delimiter ``-``:

1. OS Type
2. OS Name
3. CPU type
4. OS Version
5. Compiler Type
6. Compiler Version

For example, ``unix-linux-x86_64-2.6.18-gcc-4.3.2`` is an UPLID whose OS
type is ``unix``, OS Name is ``linux``, CPU type is ``x86_64``, OS
version is ``2.6.18``, compiler type is ``gcc``, and compiler version is
``4.3.2``.  This UPLID identifies a platform running Linux (kernel)
version 2.6.18, with an X86\_64 CPU, using gcc version 4.3.2.

If you are unsure of the UPLID for a particular platform, a good way to
determine it is to run ``waf configure`` on that platform.

A wildcard UPLID allows the use of the wildcard symbol, ``*``, as one or
more parts of the UPLID.  When ``*`` is used for a part, any value for
that part will be matched.


Valid OS Types
~~~~~~~~~~~~~~

+---------+--------------------------------------------------------------+
| OS Type | Description                                                  |
+=========+==============================================================+
| unix    | Unix-based operating systems (Linux, Solaris, AIX, and OS X) |
+---------+--------------------------------------------------------------+
| windows | Microsoft Windows operating system                           |
+---------+--------------------------------------------------------------+

Valid OS Names
~~~~~~~~~~~~~~

+------------+------------------------+
| OS Name    | Description            |
+============+========================+
| linux      | Linux                  |
+------------+------------------------+
| darwin     | OS X                   |
+------------+------------------------+
| aix        | AIX                    |
+------------+------------------------+
| sunos      | Solaris                |
+------------+------------------------+
| windows_nt | Windows NT             |
+------------+------------------------+

Valid Compiler Types
~~~~~~~~~~~~~~~~~~~~

+---------------+------------------------------+
| Compiler Type | Description                  |
+===============+==============================+
| gcc           | gcc compiler                 |
+---------------+------------------------------+
| clang         | clang compiler               |
+---------------+------------------------------+
| xlc           | IBM XL C/C++ compiler        |
+---------------+------------------------------+
| cc            | Sun Studio C/C++ compiler    |
+---------------+------------------------------+
| cl            | Visual Studio C/C++ compiler |
+---------------+------------------------------+

.. index::
   single: UFID

.. _bde_repo-ufid:

UFID
````

The third field of an option rule is a UFID.  UFID stands for Unified
Flag ID.  It is used to identify the configuration used to build the
repository.  It comprises one or more flags.  The following flags are
permissible:

+--------+--------------------------------------------------------------+
| Flag   | Description                                                  |
+========+==============================================================+
| dbg    | Build with debugging information                             |
+--------+--------------------------------------------------------------+
| opt    | Build optimized                                              |
+--------+--------------------------------------------------------------+
| exc    | Build with support for exceptions (default no support)       |
+--------+--------------------------------------------------------------+
| mt     | Build with support for multi-threading (default no support)  |
+--------+--------------------------------------------------------------+
| ndebug | Build with NDEBUG defined                                    |
+--------+--------------------------------------------------------------+
| 64     | Build for 64-bit architecture (default is 32-bit)            |
+--------+--------------------------------------------------------------+
| safe   | Build assertion-checked libraries                            |
+--------+--------------------------------------------------------------+
| safe2  | Build assertion-checked, binary-incompatible libraries       |
+--------+--------------------------------------------------------------+
| shr    | Build dynamic libraries                                      |
+--------+--------------------------------------------------------------+
| pic    | Build static PIC libraries                                   |
+--------+--------------------------------------------------------------+
| cpp11  | Build with support for C++11 features                        |
+--------+--------------------------------------------------------------+

.. note::
   ``Waf`` always enables ``mt``.  It is still a valid ufid for historical
   reasons.

For example, the UFID ``dbg_mt_exc_shr`` represents a build
configuration that enables debugging symbols, supports multi-threading
and exceptions, and builds libraries as dynamic libraries.

The UFID specified in an option rule will be matched only if the current
build configuration contains all of the UFID of that rule.

For example, suppose that the current build configuration is
``dbg_mt_exc``.  A rule whose UFID is ``dbg_mt`` will be matched
(assuming that the rule's UPLID also matches), but a rule whose UFID is
``opt_mt`` will not be matched.

Variable Expansion
``````````````````

The values of a variable can reference other variables.  After all of the
option files have been read, variables are evaluated by recursive
expansion, in a manner similar to Make variables.  Thus, a variable can
not refer to itself, or it will result in an infinite recursion during
expansion.

If an option variable referenced is not defined in any options files read, then
its value will be the environment variable having the same name, if it is
defined; otherwise, the value of the option variable is taken to be an empty
string.

For example:

::

* _ FOO = a
* _ BAR = $(FOO) b

After evaluation, the variable BAR will have a value "a b".

Processing Order
````````````````

There are three levels at which build options can be defined, depending
on their intended scope of influence:

-  Universally.  Option rules defined in the default options file are
   used as the basis for deriving all build options for any package or
   package group.  The value of variables defined here can be further
   augmented or overridden by group- or package-level rules.  The default
   options file, ``default.opts``, is stored in the ``etc`` directory of the
   open source repository ``bde-tools`` hosted on github.

-  At the package-group level.  Option rules defined at this level apply
   to the whole package group.  These rules are processed after those in
   the default options file.

-  At the package level.  Options defined at this level apply only to the
   package in which they reside and not to other packages in the same
   package group.  These rules are processed after those for package
   groups.

Each level is processed in order, thereby giving lower levels the
ability to augment or override the values established by higher ones;
groups can override the default value of an option, and packages can
override the value established by their containing group.

.. index::
   single: opts file
   single: defs file

Opts and Defs Files
-------------------

An ``opts`` file defines internal build options, while a ``defs`` file
defines exported (externally visible) build options.  Both of these file
types use the options file format, which allows the specification of compiler
and linker flags depending on the current platform and configuration used.

``opts`` files are valid for all packages and package groups, while ``defs``
file are only valid for :ref:`UORs <bde_repo-uor>` (stand-alone packages and
package groups).

The following table shows the variables that contribute to the build
flags used by the build tool:

+-------------------+------------------------------------+
| Variable Name     | Description                        |
+===================+====================================+
| BDEBUILD_CFLAGS   | Options passed to the C compiler   |
+-------------------+------------------------------------+
| BDEBUILD_CXXFLAGS | Options passed to the C++ compiler |
+-------------------+------------------------------------+
| BDEBUILD_LDFLAGS  | Options passed to the linker       |
+-------------------+------------------------------------+

.. index::
   single: cap file

Cap File
--------

A ``cap`` file defines the combinations of platform and build
configuration supported by a package or a package group.  This file type
also uses the ``opts`` file format.  The capability of a package or package
group is determined by the value of the variable ``CAPABILITY``.  If the
value of ``CAPABILITY`` is unset or is ``ALWAYS``, then the package or
package group is supported on the matched platform and build
configuration.  If the value of ``CAPABILITY`` is ``NEVER``, then the
package or package group is not supported.

.. index::
   single: pub file

Pub File
--------

A ``pub`` file defines the list of header file names, *not component names*,
that should be installed for a package.  In a way, this is a method to provide
a public interface and hide internal-only implementation details from clients
of a library.

``pub`` files are valid for packages only, not package groups.
