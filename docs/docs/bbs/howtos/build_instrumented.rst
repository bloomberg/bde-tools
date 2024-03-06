.. _bbs_build_instrumented-top:

-----------------------
Build Using A Sanitizer
-----------------------
BDE build system supports sanitized builds for gcc and clang compilers with
special :ref:`ufid` flags.

The :ref:`ufid` options related to sanitizers are:

.. csv-table::
   :header: "UFID flag", "Sanitizer"
   :align: left
   
   "asan",  "Build with address sanitizer"
   "msan",  "Build with memory sanitizer"
   "tsan",  "Build with thread sanitizer"
   "ubsan", "Build with undefined behavior sanitizer"

The main difficulty with sanitized build is the proper compiler deployment on
the build host - some compilers require special versions of the compiler
libraries to be available at link/run time. 

{{{ internal
Build with a Default Compiler
-----------------------------
The default gcc compiler installed on the build hosts can build instrumented
libraries/application with no additional configuration.

* Clone the `bde <https://bbgithub.dev.bloomberg.com/bde/bde>`_ repository:

.. code-block:: shell

   $ git clone bbgithub:bde/bde
   $ cd bde


* Configure build with an address sanitizer:

.. code-block:: shell

   $ eval `bbs_build_env -u dbg_asan_64_cpp20`

* Build and run BDE tests:

.. code-block:: shell

   $ plocum bbs_build --target all.t --test run

Configuring a Compiler for an Instrumented Build
------------------------------------------------
Clang compilers require special run-time libraries to be linked with the
instrumented code that are not deployed by default.

Instrumented build with a "custom" compiler should start with installing and
configuring this compiler.

* Install refroot with the compiler and necessary compiler libraries:

.. code-block:: shell
    
   $ refroot-install --distribution=unstable --yes --arch amd64 \
      --package clang-13.0 --package compiler-rt-13.0 \
      --refroot-path=<refroot_path>

* Create a custom entry in the ~/.bbs_build_profiles:

.. code-block:: Json

   [
       {
           "uplid": "unix-linux",
           "profiles": [
               {
                   "name": "Clang-13-rt",
                   "c_path": "<refroot_path>/opt/bb/lib/llvm-13.0/bin/clang",
                   "cxx_path": "<refroot_path>/opt/bb/lib/llvm-13.0/bin/clang++",
                   "toolchain": "clang-default",
                   "description": "Clang 13.0 with sanitizers runtime"
               }
           ]
       }
   ]

* Configure build with address sanitizer and custom compiler:

.. code-block:: shell

   $ eval `bbs_build_env -u dbg_asan_64_cpp20 -p Clang-13-rt`

}}}
{{{ oss
Build with sanitizers
---------------------
Make sure that compiler you use for instrumented build is installed
with all necessary support for sanitizers

* Clone the `bde <https://github.com/bloomberg/bde>`_ repository:

.. code-block:: shell

   $ git clone https://github.com/bloomberg/bde.git
   $ cd bde


* Configure build with an address sanitizer:

.. code-block:: shell

   $ eval `bbs_build_env -u dbg_asan_64_cpp20`

* Build and run BDE tests:

.. code-block:: shell

   $ bbs_build --target all.t --test run

}}}

* Build and test as usual.
