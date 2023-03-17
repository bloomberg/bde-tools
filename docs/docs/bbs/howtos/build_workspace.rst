.. _bbs-build-workspace-top:

--------------------------------------
Build Multiple Projects in a Workspace
--------------------------------------
In some use cases it is necessary to build multiple repositories containing
dependant libraries.  In this example we build the libraries in
the ``bde`` and
{{{ internal
``bde-classic``
}}}
{{{ oss
``my_app``
}}} source code repositories as part of a single workspace.

Download Libraries
------------------
{{{ internal
In this example, we are using ``bde`` and ``bde-classic``:

.. code-block:: shell

   $ git clone bbgithub:bde/bde
   $ git clone bbgithub:bde/bde-classic
}}}
{{{ oss
In this example, we are using ``bde`` and ``my_app``:

.. code-block:: shell

   $ git clone https://github.com/bloomberg/bde.git
   $ git clone https://github.com/<user>/my_app.git
}}}

Create workspace CMakeLists.txt
-------------------------------
* Create ``CMakeLists.txt`` file to build both libraries:

.. code-block:: CMake

   # CMakeLists.txt for a workspace
   cmake_minimum_required(VERSION 3.22)
   project(workspace)

   enable_testing()

   add_subdirectory(bde)
{{{ internal
   add_subdirectory(bde-classic)
}}}
{{{ oss
   add_subdirectory(my_app)
}}}

Configure and Build the Workspace 
---------------------------------
Proceed with :doc:`setting up the environment and building<build_bde_basic>` as
usual.
