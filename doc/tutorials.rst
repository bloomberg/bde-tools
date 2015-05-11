=========
Tutorials
=========

.. _tutorials-build_bde:

Use waf to Build BDE
====================

.. note::

   The following instruction assumes that you are running a unix
   platform. Building on windows is almost equivalent, except you must use the
   equivalent commands in windows command prompt. For more details, please see
   :ref:`waf-windows`.

First, clone the bde and bde-tools repositores from `github
<https://github.com/bloomberg/bde>`_:

::

   $ git clone https://github.com/bloomberg/bde.git
   $ git clone https://github.com/bloomberg/bde-tools.git

Then, add the ``<bde-tools>/bin`` to the ``PATH`` environment variable:

::

   $ export PATH=<bde-tools>/bin:$PATH

.. note::

   Instead of adding ``bde-tools/bin`` to your ``PATH``, you can also execute
   the scripts in ``bde-tools/bin`` directly.

Now, go to the root of the bde repository and build the libraries in it:

::

    $ cd <bde>
    $ waf configure
    $ waf build --target bslstl  # build just the bslstl package
    $ waf build  # build all libraries
    $ waf build --test build  # build all test drivers
    $ waf build --test run  # run all test drivers

The linked libraries, test drivers, and other build artifacts should be in the
build output directory, which by default is just "build".

See :ref:`waf-top` for detailed reference.

.. _tutorials-setwafenv-bde:

Use bde_setwafenv.py to Build BDE
=================================

First, specify the compilers available on your system in a
``~/.bdecompilerconfig``.  Here is an example:

::

   [
        {
            "hostname": ".*",
            "uplid": "unix-linux-",
            "compilers": [
                {
                    "type": "gcc",
                    "c_path": "/opt/swt/install/gcc-4.7.2/bin/gcc",
                    "cxx_path": "/opt/swt/install/gcc-4.7.2/bin/g++",
                    "version": "4.7.2"
                },
                {
                    "type": "gcc",
                    "c_path": "/opt/swt/install/gcc-4.3.5/bin/gcc",
                    "cxx_path": "/opt/swt/install/gcc-4.3.5/bin/g++",
                    "version": "4.3.5"
                },
                {
                    "type": "gcc",
                    "c_path": "/usr/bin/gcc",
                    "cxx_path": "/usr/bin/g++",
                    "version": "4.1.2"
                }
            ]
        }
   ]

See :ref:`setwafenv-compiler_config` for more details.

Then, follow the instructions from :ref:`tutorials-build_bde` to checkout bde
and bde-tools and add bde-tools/bin to your PATH.

Next, use ``bde_setwafenv.py`` to set up the environment variables:

::

   $ eval $(bde_setwafenv.py -i /tmp/bde-install -t dbg_mt_exc_64 -c gcc-4.7.2)

   using configuration: /home/che2/.bdecompilerconfig
   using compiler: gcc-4.7.2
   using ufid: dbg_exc_mt_64
   using install directory: /tmp/bde-install

.. note::

   Here we choose to use :ref:`bde_repo-ufid` to specify the build
   configuration.  You can also use the :ref:`qualified configuration options
   <waf-qualified_build_config>`.

The actual environment variables being set will depend on your machine's
platform :ref:`bde_repo-uplid`. On my machine, the following Bourne shell
commands are evaluated to set the environment variables:

::

   export BDE_WAF_UPLID=unix-linux-x86_64-3.2.0-gcc-4.7.2
   export BDE_WAF_UFID=dbg_exc_mt_64
   export BDE_WAF_BUILD_DIR="unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64"
   export WAFLOCK=".lock-waf-unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64"
   export CXX=/usr/bin/g++
   export CC=/usr/bin/gcc
   export PREFIX="/tmp/bde-install/unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64"
   export PKG_CONFIG_PATH="/tmp/bde-install/unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64/lib/pkgconfig"
   unset BDE_WAF_COMP_FLAGS

Then, build BDE using waf:

::

   $ cd <bde>
   $ waf configure build

See :ref:`setwafenv-top` for detailed reference.

.. _tutorials-workspace:

Use waf Workspace to Build Multiple BDE-Style Repositories
==========================================================

You can you the workspace feature to build multiple BDE-style repositories in
the same way as a single repository (see :ref:`waf-workspace`)

For example, suppose that you have the following BDE-style repositories that
that you want to build together: ``bsl-internal``, ``bde-core``, and
``bde-bb``.

First, create a directory to serve as the root of the workspace, say
``myworkspace``:

::

   $ mkdir myworkspace

Then, check out the repositories that will be part of the workspace:

::

   $ cd myworkspace
   $ git clone <bsl-internal-url>
   $ git clone <bde-core-url>
   $ git clone <bde-bb-url>

Next, add a empty file named ``.bdeworkspaceconfig`` and copy
``bde-tools/etc/wscript`` to the root of the workspace:

::

   $ touch .bdeworkspaceconfig
   $ cp <bde-tools>/etc/wscript .

The workspace should now have the following layout:

::

   myworkspace
   |
   |-- .bdeworkspaceconfig
   |-- wscript
   |-- bsl-internal
   |   |
   |   |-- wscript
   |   `-- ...      <-- other files in bsl-internal
   |
   |-- bde-core
   |   |
   |   |-- wscript
   |   `-- ...      <-- other files in bde-core
   |
   `-- bde-bb
       |
       |-- wscript
       `-- ...      <-- other files in bde-bb


Now, you can build every repository in the workspace together:

::

   $ waf configure
   $ waf build

bde_setwafenv.py works the same way for a workspace as a regular repository.


.. note::

   You must be in the root directory of the workspace to build the workspace.
   If you go into a repository contained in the workspace, any waf commands
   will apply to that repository directly.

.. _tutorials-setwafenv-bde-app:

Use bde_setwafenv.py to Build an Application on Top of BDE
==========================================================

First, follow :ref:`tutorials-setwafenv-bde` to create
``~/.bdecompilerconfig``, set up the environment variables using
bde_setwafenv.py, and build BDE.

Then, install bde:

::

   $ cd <bde>
   $ waf install

On my machine, the headers, libraries, and pkg-config files are installed to
``/tmp/bde-install/unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64``:

::

   /tmp/bde-install/unix-linux-x86_64-3.2.0-gcc-4.7.2-dbg_exc_mt_64
   |
   |-- include
   |   |
   |   `-- ...  <-- header files
   |
   `-- lib
    |
    |-- libbdl.a
    |-- libbsl.a
    |-- libdecnumber.a
    |-- libinteldfp.a
    `-- pkgconfig
        |
        |-- bdl.pc
        |-- bsl.pc
        |-- decnumber.pc
        `-- inteldfp.pc

Next, create a new repository containing the application that we are going to
be building.

::

   $ mkdir testrepo
   $ cd testrepo
   $ cp <bde-tools>/etc/wscript .  # wscript is required for using waf

Then, create the following directory and file structure in the repo
(see :ref:`bde_repo-physical_layout` for more details):

::

   testrepo
   |
   |-- wscript
   `-- applications
      |
      `-- myapp
          |
          |-- myapp.m.cpp
          `-- package
              |
              |-- myapp.dep
              `-- myapp.mem

Contents of myapp.m.cpp:

::

    #include <bsl_vector.h>
    #include <bsl_iostream.h>

    int main(int, char *[])
    {
        bsl::vector<int> v;

        v.push_back(3);
        v.push_back(2);
        v.push_back(5);

        for (bsl::vector<int>::const_iterator iter = v.begin();
            iter != v.end();
            ++iter) {
            bsl::cout << *iter << bsl::endl;
        }

        return 0;
    }

Contents of myapp.dep:

::

   bsl # we depend on bsl

``myapp.mem`` should be empty because myapp doesn't contain any components
except the ``.m.cpp``, which is implicitly included in an application package.

Now, we can build this application using waf:

::

   $ cd <testrepo>
   $ waf configure
   $ waf build

.. _tutorials-setwafenv-bde-windows:

Use bde_setwafenv.py to Build BDE on Windows
============================================

bde_setwafenv.py can be used on Windows through Cygwin or Git for Windows (msysgit).

**Prerequisites**:

- `Cygwin <https://www.cygwin.com/>`_ or `Git for Windows (msysgit) <https://msysgit.github.io/>`_
- Windows and Cygwin versions of Python 2.6, 2.7, or 3.3+

First, make sure you have cloned the bde and bde-tools repositories, and that
you have added ``bde-tools/bin`` to your system's PATH.

Then, for Cygwin, export the WIN_PYTHON environment variable to point to the
*Cygwin* path of the *Windows* version of Python.  For example, if the Windows
version of Python is installed to ``C:\Python27\python``, then you can use the
following command to set up the required WIN_PYTHON environment variable:

::

   $ export WIN_PYTHON=/cygdrive/c/Python27/python

For msysgit, add Windows version of Python to the system PATH.

Next, in the Cygwin or msysgit bash shell, run the following command to set the
environment variables for waf:

::

   $ bde_setwafenv.py list  # list available compilers on windows
   $ eval $(bde_setwafenv.py -i ~/tmp/bde-install -c cl-18.00) # use visual studio 2013

.. note::

   On Windows, bde_setwafenv.py does not use ``~/.bdecompilerconfig``. Instead
   it uses a list of hard-coded available compilers on windows and do not check
   those compilers are available. It is your job to make sure that you are
   using an already installed Visual Studio compiler.

Now, you can build bde using ``waf`` in msysgit or ``cygwaf.sh`` in cygwin:

::

   $ cd <bde>

   # in msysgit
   $ waf configure
   $ waf build

   # in Cygwin
   $ cygwaf.sh configure
   $ cygwaf.sh build

.. important::

   Even though bde_setwafenv.py is supported on only Cygwin in Windows, Cygwin
   itself is not a supported build platform by :ref:`waf-top`.  Once
   bde_setwafenv.py is executed in Cygwin, ``bde-tools/bin/cygwaf.sh``
   (preferred) or ``bde-tools/bin/waf.bat`` must be used instead of executing
   ``waf`` directly. ``cygwaf.sh`` will invoke ``waf`` using the windows
   version of Python and build using the Visual Studio C/C++ compiler selected.
   You can download a free version of Visual Studio Express from `Microsoft
   <https://www.visualstudio.com/en-us/products/visual-studio-express-vs.aspx>`_.

.. TODO: Building an Library That Does Not Depend on BDE
.. TODO: Building an Application That Does Not Depend on BDE
