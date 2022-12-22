-----------------------------
Add a Custom Compiler Profile
-----------------------------

A user can add new profile to the ``~/.bbs_build_profiles``.

The entry for the BDE flexible gcc compiler series profile:

.. code-block:: json

   [
       {
           "uplid": "unix-linux",
            "profiles": [
                {
                    "name":        "gcc-13.0.0.beta",
                    "c_path":      "/usr/local/gcc-13/bin/gcc",
                    "cxx_path":    "/usr/local/gcc-13/bin/g++",
                    "toolchain":   "gcc-default",
                    "description": "Experimental gcc-13 compiler"
                }
            ]
       }
   ]

Note that the toolchain is picked up from the collection of the BBS toolchains
based on the UPLID.

The entry for the hardcoded compiler profile looks similar, but contains and
additional section that describes the profile properties and help tools to
limit user ability to  create invalid build configurations:

.. code-block:: json

   [
       {
           "uplid": "unix-linux",
            "profiles": [
                {
                    "name":      "gcc-9-instrumented",
                    "c_path":    "/usr/local/gcc-13/bin/gcc",
                    "cxx_path":  "/usr/local/gcc-13/bin/g++",
                    "toolchain": "/usr/local/gcc-12/toolchains/test_cpp23.cmake",
                    "properties": {
                        "noexc": false,
                        "bitness": 64,
                        "standard": "cpp23",
                        "sanitizer": false,
                        "assert_level": "default",
                        "review_level": "default"
                    }
                }
            ]
       }
   ]

Json attributes
---------------
TBD

.. csv-table::
   :header: "Property", "Description"
   :widths: 40, 60
   :align: left

   "name", "Name used to select this profile. Should be distinct from other names."
   "c_path", "Path to the C compiler"
   "cxx_path", "Path to the C++ compiler"
   "toolchain", "Relative or absolute path to the CMake toolchain"
   "description", "Human readable profile description"
   "properties", "Array describing toolchains fixed parameters. TBD"

