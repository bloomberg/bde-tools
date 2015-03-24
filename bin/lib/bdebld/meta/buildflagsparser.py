"""Parse the build flags from a build command.
"""

import re


class BuildFlagsParser(object):
    """Parser that to identify the different parts of a build command.
    """

    def __init__(self, shlib_marker, stlib_marker, lib_re,
                 libpath_re, includepath_re, define_opt):
        """Initialize the parser.

        Args:
            shlib_marker (str): Marker to indicate start of shared libraries.
            stlib_marker (str): Marker to indicate start of static libraries.
            lib_re (str): Regular expression to get the name of the library in
                a -l rule.  E.g., for gcc this is -l([^ =]+).
            libpath_re (str): Regular expression to get the library path in a
                -L rule.  E.g., for gcc this is -L([^ =]+).
            includepath_re (str): Regular expression to get the include path in
                a -I rule.  E.g., for gcc this is -I([^ =]+).
            define_opt (str): Compiler option to define macro definitions.
        """
        self.shlib_marker = shlib_marker
        self.stlib_marker = stlib_marker
        self.lib_re = re.compile(lib_re)
        self.libpath_re = re.compile(libpath_re)
        self.includepath_re = re.compile(includepath_re)
        self.define_opt = define_opt

    def get_export_cflags(self, cflags):
        """Return a list of compiler flags meant to be exported.

        Args:
            cflags (list of str): Flags to be passed to the compiler (C or
                CXX).

        Returns:
            list of export flags
        """

        # Only macro definitions are required to be exported
        export_flags = []
        for flag in cflags:
            st = flag[:2]
            if st == '-D' or st == self.define_opt:
                export_flags.append(flag)

        return export_flags

    def partition_cflags(self, cflags):
        """Sort the flags passed to the compiler into separate components.

        Args:
            cflags (list of str): Flags to be passed to the compiler (C or
                CXX).

        Returns:
            include_paths, flags
        """

        include_paths = []
        flags = []

        for flag in cflags:
            m = self.includepath_re.match(flag)
            if m:
                include_paths.append(m.group(1))
                continue

            flags.append(flag)

        return include_paths, flags

    def partition_linkflags(self, linkflags):
        """Sort the flags passed to the linker into separate components.

        The linkflags values in BDE opts files contains all of the arguments
        that is passed to the linker.  More distinctions are required for build
        tools such as waf.

        Args:
            linkflags (list of str): Link flags pass to the linker.

        Returns:
            stlibs, libs, lib_paths, flags

            stlibs (list of str): Static library names.
            lib (list of str): Shared library names.
            lib_paths (list of str): Library paths.
            flags (list of str): Other flags.

        """

        stlibs = []
        libs = []
        lib_paths = []
        flags = []

        # default to shlibs
        isshlib_flag = True

        for flag in linkflags:
            if flag == self.shlib_marker:
                isshlib_flag = True
                continue

            if flag == self.stlib_marker:
                isshlib_flag = False
                continue

            m = self.libpath_re.match(flag)
            if m:
                lib_paths.append(m.group(1))
                continue

            m = self.lib_re.match(flag)
            if m:
                lib = m.group(1)
                if isshlib_flag:
                    libs.append(lib)
                else:
                    stlibs.append(lib)
                continue

            # In our default opts files, the link line variables contains
            # compiler warning flags, which are superfluous, that unnecessarily
            # increases the length of the link line.  We workaround the
            # problem by removing flags starting with '-W' from the link
            # command line.
            if not flag.startswith('-W') or flag.startswith('-Wl,'):
                flags.append(flag)

        return stlibs, libs, lib_paths, flags

# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE -----------------------------------
