Troubleshooting
===============

I get the error "BDE waf customizations can not be found."
----------------------------------------------------------

Make sure that you are running the ``waf`` exectuable located in
``bde-tool/bin``.  The ``wscript`` file uses the location of waf to find BDE's
waf customizations.

If the problem presists, then copy ``bde-tools/share/wscript`` to the root of
the repo that you are trying to build.  The existing ``wscript`` in your repo
is probably out of date and is no longer supported.

I get a python exception when running ``waf configure``.
--------------------------------------------------------

Most likely, you have updated BDE Tools without re-configuring the source repo
being built.  Try removing the existing configuration:

::

   $ waf distclean  # delete the output directory, including the existing configuration
   $ waf configure build

Waf did not detect the changes that I made.
-------------------------------------------

Waf reads and caches the metadata and structure of the repository during ``waf
configure`` to speed up the build process during ``waf build``.  This is speed
up is particularly significant on a network based file system such as NFS.

If you made any physical changes to the repository, such as having updated the
metadata, added a new component, or added a new package group, you must run
``waf configure`` again for waf to pick up the changes you have made:

::

   <make physical changes to repo>
   $ waf configure
   $ waf build

.. note::
   We considered having waf automatically re-configure a repository whenever
   required, but this feature can not be implemented reliably without actually
   re-scanning the entire repository before doing each build (which can be slow
   on NFS). Not all physical changes are recorded in a metadata file, e.g.,
   adding a new package group or a stand-alone package.  If you want to have
   the auto-configure-like behavior, you can always run ``waf configure build``
   to always configure a repository before building it.  For most projects
   built on local disk, the configuration step should take a negligible amount
   of time.

Waf did not detect the component I added.
-----------------------------------------

Make sure that you have also made the corresponding change to the
:ref:`bde_repo-mem` of the package in which you added the new component.

For example, if you added a component named ``abcd_comp1``, make sure that you
also add ``abcd_comp1`` to the ``mem`` file of the package ``abcd``.

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

Known Issues
------------

Please refer to `the issue tracker
<https://github.com/bloomberg/bde-tools/issues>`_.
