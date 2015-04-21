==========================
Frequently Asked Questions
==========================

Why did you choose to use waf?
==============================

We had the following goals for the cross-platform build system:

1. Work with :ref:`bde_repo-metadata`, which specifies the contents,
   dependency, and build options of a repo in a build-tool agnostic way.  These
   metadata formats were already used by other existing in-house build systems.

2. Require minimal configuration to use for any :ref:`bde_repo-top`.

3. Have good performance.

4. Integrate features not typically found in a build system, such the
   verification of the repo structure, checking for cyclic dependencies, and
   running test drivers in a configurable way.

5. Be user friendly.

Requirements 1 and 4 meant that ease of customization was an extremely
important criteria. We chose waf because it had the best overall combination of
customizability and speed among the tools that were evaluated.

We evaluated a few different cross-platform build tools, including `SCons
<http://www.scons.org/>`_, `waf <https://github.com/waf-project/waf>`_, `CMake
<http://www.cmake.org/>`_, and `gyp <http://www.cmake.org/>`_.

Waf, along with SCons, can be extended using Python.  Using python as the
extension language made it easy for us to add additional features that
integrates natively with the build tool.  Gyp can generate ninja targets, which
is fast, but gyp's declarative JSON configuration requires preprocessors for
doing any deep customization. CMake is perhaps the most mature, but CMake's
domain specific language is awkward to use and places certain limitations on
what can be integrated into the tool iself.

What made us choose waf over SCons is that waf is much faster than SCons [#f1]_
[#f2]_.

Why is there a copy of waf in this repository?
==============================================

Including a packed waf executable script in each project is the recommended
distribution method for waf. This method may seem non-ideal due to code
duplication, but the method ensures that API changes in the upstream waf source
will never affect the customizations made to waf in a local project.
Furthermore, waf is also relatively lightweight, being only about 100KB in
size.

Do I have to be using the BDE libraries to utilize the provided build tools?
============================================================================

The build tools are designed to work with BDE and libraries and application
built on top of BDE, but the tools should work for any conforming
:ref:`bde_repo-top`.  Keep in mind that some options, such as
``--assert--level``, are specific to building the BDE libraries.


.. rubric:: Footnotes

.. [#f1] `Benchmarks of various C++ build tools
         <http://sourceforge.net/p/psycle/code/10694/tree//branches/bohan/wonderbuild/benchmarks/time.xml>`_
         Compares the speed of SCons, Waf, Wonderbuild, Jam, Make, the
         Autotools, and CMake.

.. [#f2] `Comparison between Scons and Waf on no-op build times <http://www.freehackers.org/~tnagy/bench.txt>`_
