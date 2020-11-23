.. _code_generation:

.. _code_generation-top:

===============
Code Generation
===============

This section describes how the BDE Build System interacts with code generators.

.. _code_generation-overview:

--------
Overview
--------

The BDE CMake build system generates some code automatically. Currently this is
done to simulate variadic templates for code being built with a C++03 compiler
(see `Expanding Parameter Packs`_ below). The code generation is run
automatically as part of the configuration of a project (see `User Interaction`_
below). The code generation step generates code into the source tree of the
repository, which differs from how many CMake projects are structured. This
code is checked into our repositories, both for release labels and our master
branch.

We generate the code in the source tree for 2 principal reasons:
 * Debuggability
    At debug time, the generated code is what has to be visible to the
    debugger.  If it's a transient artifact, it won't be available when
    developers are trying to diagnose issues.
 * Build reproducibility
    Generating the code in-tree makes sure our releases can be reproduced
    trivially.

In order to ensure generated code in source control is not out of date, our CI
systems perform builds that verify that generated code is up to date with both
the latest version of the source code, and the latest version of the code
generation tools (see `User Interaction`_ below).

----------------
User Interaction
----------------

After the generation templates are written and the initial code generation is
done (e.g., `Writing Parameter Packs`_ and `Initial simulation tool usage`_,
below), the ongoing use of the code generators is transparent to any user of
the ``cmake_build.py`` tool.

Users set up their environment as usual, then run the ``cmake_build.py configure`` step, which sets up the rules for re-generating the target files if necessary:

  .. code-block:: shell

    $ cmake_build.py configure
        ...
        -- Looking for pthread_create in pthread - found
        -- Found Threads: TRUE  
        -- sim_cpp11 generation: /bb/mbiga/mbig1480/bde/groups/bdl/bdlb/bdlb_nullablevalue.cpp -> /bb/mbiga/mbig1480/bde/groups/bdl/bdlb/bdlb_nullablevalue_cpp03.cpp
        -- sim_cpp11 generation: /bb/mbiga/mbig1480/bde/groups/bdl/bdlb/bdlb_nullablevalue.h -> /bb/mbiga/mbig1480/bde/groups/bdl/bdlb/bdlb_nullablevalue_cpp03.h
        -- sim_cpp11 generation: /bb/mbiga/mbig1480/bde/groups/bsl/bslalg/bslalg_arrayprimitives.cpp -> /bb/mbiga/mbig1480/bde/groups/bsl/bslalg/bslalg_arrayprimitives_cpp03.cpp
        -- sim_cpp11 generation: /bb/mbiga/mbig1480/bde/groups/bsl/bslalg/bslalg_arrayprimitives.h -> /bb/mbiga/mbig1480/bde/groups/bsl/bslalg/bslalg_arrayprimitives_cpp03.h
        ...

Afterwards, during the build phase, the generated files are re-generated only
if necessary:

  .. code-block:: shell

    $ cmake_build.py build
        ...
        [99/328] Generating ../../groups/bsl/bslmf/bslmf_functionpointertraits_cpp03.h - sim_cpp11_features.pl updated file
        [100/328] Generating ../../groups/bsl/bslmf/bslmf_nthparameter_cpp03.cpp - sim_cpp11_features.pl did not need to update
        ...



In this example, ``bslmf_functionpointertraits_cpp03.h`` needed to be
regenerated, but ``bslmf_nthparameter_cpp03.cpp`` did not.  Unless you are
working directly on a component with generated code, the latter is the much
more common occurence.


.. _parameter_packs-top:

=========================
Expanding Parameter Packs
=========================

This section describes how BDE simulates
`parameter packs <https://en.cppreference.com/w/cpp/language/parameter_pack>`_
(a.k.a. variadic templates) on C++03 compilers.

.. _parameter_packs-1:

--------
Overview
--------

Parameter packs are a feature that was added in C++11, allowing for template
expansions with a variable number of parameters.  For example:

.. _parameter_packs-example-1:

Unexpanded (source) code
^^^^^^^^^^^^^^^^^^^^^^^^

  .. code-block:: C++

        #if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
        template <class VALUE, class ALLOCATOR>
        template <class... ARGS>
        inline
        typename list<VALUE, ALLOCATOR>::reference
        list<VALUE, ALLOCATOR>::emplace_front(ARGS&&... arguments)
        {
            emplace(cbegin(), BSLS_COMPILERFEATURES_FORWARD(ARGS, arguments)...);
            return front();
        }
        #endif

We simulate the variadic expansions in C++03 using
``bde-tools/contrib/sim_cpp11/sim_cpp11_features.pl``.

This tool can be applied to any source file (e.g., ``bslstl_list.h``) and
generates an ``_cpp03`` file (e.g. ``bslstl_list_cpp03.h``) alongside it, as
well as modifying the original file to include the ``_cpp03`` file if
necessary.

The generated ``_cpp03`` equivalent of the example above is not as readable,
which is why we isolate it off into its own file which can be ignored during
code reviews.  In this example, only the first 3 expansions are shown; the
actual _cpp03 file has 10 expansions covering 300 lines of code just for this
one method.

.. _parameter_packs-example-2:

Expanded (generated) code
^^^^^^^^^^^^^^^^^^^^^^^^^

  .. code-block:: C++

        #if BSLS_COMPILERFEATURES_SIMULATE_VARIADIC_TEMPLATES
        // {{{ BEGIN GENERATED CODE
        // Command line: sim_cpp11_features.pl bslstl_list.h
        #ifndef BSLSTL_LIST_VARIADIC_LIMIT
        #define BSLSTL_LIST_VARIADIC_LIMIT 10
        #endif
        #ifndef BSLSTL_LIST_VARIADIC_LIMIT_E
        #define BSLSTL_LIST_VARIADIC_LIMIT_E BSLSTL_LIST_VARIADIC_LIMIT
        #endif
        #if BSLSTL_LIST_VARIADIC_LIMIT_E >= 0
        template <class VALUE, class ALLOCATOR>
        inline
        typename list<VALUE, ALLOCATOR>::reference
        list<VALUE, ALLOCATOR>::emplace_front(
                                  )
        {
            emplace(cbegin());
            return front();
        }
        #endif  // BSLSTL_LIST_VARIADIC_LIMIT_E >= 0

        #if BSLSTL_LIST_VARIADIC_LIMIT_E >= 1
        template <class VALUE, class ALLOCATOR>
        template <class ARGS_01>
        inline
        typename list<VALUE, ALLOCATOR>::reference
        list<VALUE, ALLOCATOR>::emplace_front(
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_01) arguments_01)
        {
            emplace(cbegin(), BSLS_COMPILERFEATURES_FORWARD(ARGS_01, arguments_01));
            return front();
        }
        #endif  // BSLSTL_LIST_VARIADIC_LIMIT_E >= 1

        #if BSLSTL_LIST_VARIADIC_LIMIT_E >= 2
        template <class VALUE, class ALLOCATOR>
        template <class ARGS_01,
                  class ARGS_02>
        inline
        typename list<VALUE, ALLOCATOR>::reference
        list<VALUE, ALLOCATOR>::emplace_front(
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_01) arguments_01,
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_02) arguments_02)
        {
            emplace(cbegin(), BSLS_COMPILERFEATURES_FORWARD(ARGS_01, arguments_01),
                              BSLS_COMPILERFEATURES_FORWARD(ARGS_02, arguments_02));
            return front();
        }
        #endif  // BSLSTL_LIST_VARIADIC_LIMIT_E >= 2

        #if BSLSTL_LIST_VARIADIC_LIMIT_E >= 3
        template <class VALUE, class ALLOCATOR>
        template <class ARGS_01,
                  class ARGS_02,
                  class ARGS_03>
        inline
        typename list<VALUE, ALLOCATOR>::reference
        list<VALUE, ALLOCATOR>::emplace_front(
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_01) arguments_01,
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_02) arguments_02,
                               BSLS_COMPILERFEATURES_FORWARD_REF(ARGS_03) arguments_03)
        {
            emplace(cbegin(), BSLS_COMPILERFEATURES_FORWARD(ARGS_01, arguments_01),
                              BSLS_COMPILERFEATURES_FORWARD(ARGS_02, arguments_02),
                              BSLS_COMPILERFEATURES_FORWARD(ARGS_03, arguments_03));
            return front();
        }
        #endif  // BSLSTL_LIST_VARIADIC_LIMIT_E >= 3


As you can see, manually maintaining such expanded code is a nightmare.

-----------------------
Writing parameter packs
-----------------------

Parameter pack templates are written as normal C++11 code in the header, source
file, and test driver of the component. Each template member is surrounded by a
specific ``#if`` block:

  .. code-block:: C++

        #if !BSLS_COMPILERFEATURES_SIMULATE_CPP11_FEATURES
        //...
        #endif

Also, anywhere that ``bsl::forward`` would be used,
``BSLS_COMPILERFEATURES_FORWARD`` is used instead (see
the unexpanded example above (:ref:`parameter_packs-example-1`)).

-----------------------------
Initial simulation tool usage
-----------------------------

We store generated code in our source tree.  See
:ref:`code_generation-overview` for the rationale.


Once a variadic template is added (to a header, source, or test driver file)
for the first time, the developer adds a ``<component>_cpp03`` sub-component to
``<package>.mem`` file for the package.  The build systems determines on which
componets to run the variadic simulation expansion by looking for subordinate
components with ``_cpp03`` extensions.

  .. code-block:: shell

        .../bde-tools/contrib/sim_cpp11/sim_cpp11_features.pl bsl_list.h
        .../bde-tools/contrib/sim_cpp11/sim_cpp11_features.pl bsl_list.cpp
        .../bde-tools/contrib/sim_cpp11/sim_cpp11_features.pl bsl_list.t.cpp
        echo bslstl_list_cpp03 >> package/bslstl.mem
        sort -o package/bslstl.mem package/bslstl.mem
        git add bsl_list_cpp03.{h,cpp,t.cpp} package/bslstl.mem
        git commit -m'Adding cpp03 files'


-------------------------------------------
Ongoing synchronization of the _cpp03 files
-------------------------------------------

The ``cmake_build.py`` tool automatically generates rules to re-run
``sim_cpp11_features.pl`` if the source files have changed.

A different option is passed to ``cmake_build.py`` by the nightly and feature
branch test builds which causes the build to fail if the source and ``_cpp03``
files are out of sync, allowing us to make sure that the state of committed
code is in sync.

  .. code-block:: shell
        
        cmake_build.py build --cpp11-verify-no-change
