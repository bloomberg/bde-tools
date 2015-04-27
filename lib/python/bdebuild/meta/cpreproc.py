"""Simple C preprocessor.
"""

import os
import re


class CPreProc(object):
    """This is a simple C preprocessor.

    This can be the includes of a source file. Note that in this
    implementation, macros are not evaluated.  Other potential implementations
    (potentially based on the one from waf) will be more conforming.
    """

    INCLUDE_RE = re.compile(r'\s*#include\s*<([^>]+)>\s*(//)?.*$')

    def __init__(self, defines=None):
        self.defines = defines

    def get_includes(self, file_path):
        includes = []
        with open(file_path) as f:
            lines = [l.rstrip('\n') for l in f.readlines()]

        for line in lines:
            m = self.INCLUDE_RE.match(line)
            if m:
                includes.append(m.group(1))

        return includes


def get_component_digraph(package):
    """Return a directed graph of the components in a package.

    Args:
       package (Package or PackageBuildConfig): A package.
    """
    components = package.components
    c_hs = set(c.header() for c in components)
    h_c_map = {}
    preproc = CPreProc()
    for comp in components:
        h_c_map[comp.header()] = comp.name

    dgraph = {}
    for comp in components:
        h_path = os.path.join(package.path, comp.header())
        includes = preproc.get_includes(h_path)
        cpp_path = os.path.join(package.path, comp.source())
        includes.extend(preproc.get_includes(cpp_path))
        dep_c_hs = set(includes) & c_hs
        dep_c_names = set(h_c_map[h] for h in dep_c_hs)
        dgraph[comp.name] = dep_c_names - set([comp.name])
    return dgraph

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
