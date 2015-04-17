====
Help
====

Frequently Asked Questions
==========================

Why did you choose waf vs another build tool?
---------------------------------------------

We had the following goals for the cross-platform build system:

1. Serve as an in-place replacement for an existing in-house build system,
   "bde_build", that already used the existing :ref:`bde_repo-metadata`.

2. Require either no configuration, or only very minimal configuration for any
   :ref:`bde_repo-top`. Be as user friendly as possible.

3. Have good performance.

4. Integrate features not typically found in a build system, such the
   verification of the repo structure, checking for cyclic dependencies, and
   running test drivers in a configurable way.

Requirements 1 and 4 meant that ease of customization was an extremely important
criteria.

We evaluated a few different cross-platform build tools for this purpose,
including `SCons <http://www.scons.org/>`_, `waf
<https://github.com/waf-project/waf>`_, `CMake <http://www.cmake.org/>`_, and
`gyp <http://www.cmake.org/>`_. We settled on using waf because it had the best
overall combination of customizability and speed among the tools that were
evaluated.

Waf, along with Scons, can be extended using Python.  Using python as the
extension language made it easy for us to add additional features that
integrates natively with the build tool.  Gyp can generate ninja targets, which
is fast, but gyp's declarative JSON configuration requires preprocessors for
doing any deep customization. CMake is perhaps the most mature, but CMake's
domain specific language places certain limitations on what can be integrated
into the tool and leaves a lot to be desired.

What made us choose waf over Scons is that waf, which began as a fork of Scons,
is `designed to be much faster than scons
<http://www.freehackers.org/~tnagy/bench.txt>`_.

Why is there a copy of waf in this repository?
----------------------------------------------

The BDE Tools repository contains customziations that may apply to only the
version of waf bundled in the repo.  Furthermore, waf is also relatively
lightweight, being only about 100KB in size.

Do I have to be using the BDE libraries to utilize the provided build tools?
----------------------------------------------------------------------------

No. The tools work for any conforming :ref:`bde_repo-top`.

How do I build using a specific version of Visual Studio?
---------------------------------------------------------

The ``CXX`` environment variable isn't used on Windows. Instead, you must use
the ``--msvc_version`` configuration option in waf.

The following table shows the relationship between the Compiler (CL.exe)
version version, Visual Studio product name, and Visual Studio internal product
version.

+------------------+--------------------+--------------------------+
| Compiler version | Product Name       | Internal Product Version |
+==================+====================+==========================+
|            18.00 | Visual Studio 2013 |                     12.0 |
+------------------+--------------------+--------------------------+
|            17.00 | Visual Studio 2012 |                     11.0 |
+------------------+--------------------+--------------------------+
|            16.00 | Visual Studio 2010 |                     10.0 |
+------------------+--------------------+--------------------------+
|            15.00 | Visual Studio 2008 |                      9.0 |
+------------------+--------------------+--------------------------+

The ``--msvc_version`` accepts the string "msvc" followed by a space, followed
by the Visual Studio internal product version number. For example, to select
Visual Studio 2013, you can pass the following option to ``waf configure``:

::

   $ waf configure --msvc_version "msvc 12.0"

.. TODO Why should I use the BDE development methodology?

Alternatively, you can :ref:`tutorials-setwafenv-bde-windows`.

Troubleshooting
===============

I see a python exception when running ``waf configure``.
--------------------------------------------------------

Most likely, you have updated BDE Tools without re-configuring the source repo
being built.  Try removing the existing configuration:

::

   $ waf distclean  # delete the output directory, including the existing configuration
   $ waf configure build

Waf is not recognizing the changes that I just made.
----------------------------------------------------

Waf reads and caches the metadata and structure of the repository during ``waf
configure`` to speed up the build process during ``waf build``.

If you made any physical changes to the repository, such as having updated the
metadata, or added a new component, you must run ``waf configure`` again for
waf to pick up the changes you have made:

::

   <make physical changes to repo>
   $ waf configure
   $ waf build

Waf is not recognizing the new component that I added.
------------------------------------------------------

Make sure that you have also made the corresponding changes to the
:ref:`bde_repo-mem` of the package in which you added the new component.

For example, if you added a component named ``abcd_comp1``, make sure that you
also add ``abcd_comp1`` to the ``mem`` file of the package ``abcd``.

Known Issues
============

Please refer to `the issue tracker
<https://github.com/bloomberg/bde-tools/issues>`_.
