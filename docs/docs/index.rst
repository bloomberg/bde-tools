================
BDE Build System
================

Welcome
-------
The ``BDE Build System`` (BBS) is a set of CMake modules, tools and configuration files that
simplify development of the libraries and applications that use a
:doc:`BDE-style physical code organization<bbs/reference/bde_repo_layout>`.  Importantly,
the BDE Build System is used to build the
{{{ internal
`BDE libraries <https://bde.bloomberg.com>`_
}}}
{{{ oss
`BDE libraries <https://github.com/bloomberg/bde>`_
}}}
themselves.

Related Sites:

{{{ internal
* `BDE Tools repository <https://bbgithub.dev.bloomberg.com/bde/bde-tools>`_
* `BDE libraries documentation <https://bde.bloomberg.com>`_
* `Core BDE libraries repository <https://bbgithub.dev.bloomberg.com/bde/bde>`_
}}}
{{{ oss
* `BDE Tools repository <https://github.com/bloomberg/bde-tools>`_
* `BDE libraries documentation <https://github.com/bloomberg/bde>`_
* `BDE libraries repository <https://github.com/bloomberg/bde>`_
}}}

This Website
------------
The documentation on this website is organized as follows:

* **How-To** documentation for common build tasks like :doc:`building the BDE libraries<bbs/howtos/build_bde_basic>`.
* **Reference** information for how :doc:`BDE-style code is structured<bbs/reference/bde_repo_layout>`,
  and additional features of the build system.
* **Tools** Reference information for the command line tools like :doc:`bbs_build_env<bbs/tools/bbs_build_env>`
* **CMake Modules** Documentation for the CMake modules that comprise the BDE Build System

Getting Started
---------------
Here are a few good staring points.

* Instructions for how to :doc:`Install and Configure<bbs/general_info/installation>` the build system
* Instructions for how to :doc:`Build the BDE libraries<bbs/howtos/build_bde_basic>`
* A description of the :doc:`BDE-style physical code organization<bbs/reference/bde_repo_layout>`

.. toctree::
   :caption:  Bde Build System
   :maxdepth: 1
   :hidden:

   bbs/general_info/requirements      
   bbs/general_info/installation


.. toctree::
   :caption:  How-To
   :maxdepth: 1
   :hidden:

   bbs/howtos/build_bde_basic
   bbs/howtos/build_single_target
{{{ internal
   bbs/howtos/build_bde_refroot
   bbs/howtos/build_bde_bbcmake
   bbs/howtos/build_bde_bbcmake_env
}}}
   bbs/howtos/build_workspace
   bbs/howtos/create_library
   bbs/howtos/configure_profile
   bbs/howtos/build_instrumented
   bbs/howtos/build_different_compiler
   
.. toctree::
   :caption: Reference
   :maxdepth: 1
   :hidden:
      
   bbs/reference/overview
   bbs/reference/bde_repo_layout
   bbs/reference/bbs_build_configuration
   bbs/reference/code_generation
   bbs/reference/fuzz_testing
   bbs/reference/bbs_compiler_profile

.. toctree::
   :caption: Tools
   :maxdepth: 1
   :hidden:

   bbs/tools/bbs_build_env
   bbs/tools/bbs_build
   bbs/tools/bbs_make_vscode
   bbs/tools/sim_cpp11_features

{{{ internal
.. toctree::
   :caption: CMake Modules API
   :maxdepth: 1
   :hidden:

   bbs/modules/bbs_bdemetadata_utils
   bbs/modules/bbs_target_utils
   bbs/modules/bbs_test_driver_utils

.. toctree::
   :caption: Misc
   :maxdepth: 1
   :hidden:

   bbs/general_info/docs-howto
}}}


