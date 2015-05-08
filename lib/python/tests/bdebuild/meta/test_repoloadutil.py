import unittest
import os

try:
    from cStringIO import StringIO
except:
    from io import StringIO

from bdebuild.meta import optionsparser
from bdebuild.meta import repoloadutil
from bdebuild.meta import repounits


class TestRepoContextLoaderUtil(unittest.TestCase):

    def setUp(self):
        self.repo_root = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos', 'one')

    def test_get_uor_doc(self):
        group_path = os.path.join(self.repo_root, 'groups', 'gr1')
        group = repounits.PackageGroup(group_path)

        doc = repoloadutil.get_uor_doc(group)
        exp_doc = repounits.UorDoc('GRoup 1 (gr1)',
                                   'Provide a test package group.')

        self.assertEqual(doc, exp_doc)

        group_path = os.path.join(self.repo_root, 'groups', 'gr2')
        group = repounits.PackageGroup(group_path)

        doc = repoloadutil.get_uor_doc(group)
        exp_doc = repounits.UorDoc('gr2', 'N/A')

        self.assertEqual(doc, exp_doc)

    def test_load_package(self):
        path = os.path.join(self.repo_root, 'groups', 'gr3', 'gr3p1')
        package = repoloadutil.load_package(
            path, repounits.PackageType.PACKAGE_NORMAL)

        opts_str = """*                   _   OPTS_FILE       = gr3p1.opts

*       _   COMPONENT_BDEBUILD_CFLAGS      = -DGR3P1_OPTS_C
*       _   COMPONENT_BDEBUILD_CXXFLAGS    = -DGR3P1_OPTS_CXX
*       _   COMPONENT_BDEBUILD_LDFLAGS     = -DGR3P1_OPTS_LD

*       _   TESTDRIVER_BDEBUILD_CFLAGS     = -DTEST_GR3P1_OPTS_C
*       _   TESTDRIVER_BDEBUILD_CXXFLAGS   = -DTEST_GR3P1_OPTS_CXX
*       _   TESTDRIVER_BDEBUILD_LDFLAGS    = -DTEST_GR3P1_OPTS_LD
"""
        cap_str = """ !! unix  _  CAPABILITY = ALWAYS
"""

        exp_package = repounits.Package(path,
                                        repounits.PackageType.PACKAGE_NORMAL)
        exp_package.mem = set(['gr3p1_comp1', 'gr3p1_comp2'])
        exp_package.dep = set(['gr3p2'])
        exp_package.opts = self._parse_opts_str(opts_str)
        exp_package.cap = self._parse_opts_str(cap_str)
        exp_package.has_dums = True
        exp_package.components = [
            repounits.Component("gr3p1_comp1"),
            repounits.Component("gr3p1_comp2")
        ]

        self.assertEqual(package, exp_package)

    def test_load_plus_package(self):
        path = os.path.join(self.repo_root, 'groups', 'gr2', 'gr2a+b')
        package = repoloadutil.load_package(
            path, repounits.PackageType.PACKAGE_PLUS)

        exp_package = repounits.Package(path,
                                        repounits.PackageType.PACKAGE_PLUS)
        exp_package.pt_extras = repounits.PlusPackageExtras()
        exp_package.pt_extras.headers = set(['h1.h', 'h2.h', 'subh/h3.h'])
        exp_package.pt_extras.cpp_sources = set(['h1.cpp', 'h2.cpp'])
        exp_package.pt_extras.cpp_tests = set(['test/test1.cpp',
                                               'test/test2.cpp'])
        exp_package.pt_extras.c_tests = set(['test/test3.c'])
        self.assertEqual(package, exp_package)

        path = os.path.join(self.repo_root, 'groups', 'gr2', 'gr2b+c')
        package = repoloadutil.load_package(
            path, repounits.PackageType.PACKAGE_PLUS)
        exp_package = repounits.Package(path,
                                        repounits.PackageType.PACKAGE_PLUS)
        exp_package.pub = set(['h1.h', 'h2.h'])
        exp_package.pt_extras = repounits.PlusPackageExtras()
        exp_package.pt_extras.headers = set(['h1.h', 'h2.h'])
        self.assertEqual(package, exp_package)

    def test_load_component(self):
        path = os.path.join(self.repo_root, 'groups', 'gr3', 'gr3p1')
        component = repoloadutil.load_component('gr3p1_comp1', path)

        exp_component = repounits.Component('gr3p1_comp1',
                                            repounits.ComponentType.CXX,
                                            True)
        self.assertEqual(component, exp_component)

    def test_load_package_group(self):
        opts_str = """*                   _   OPTS_FILE       = gr3.opts

*       _   COMPONENT_BDEBUILD_CFLAGS      = -DGR3_OPTS_C
*       _   COMPONENT_BDEBUILD_CXXFLAGS    = -DGR3_OPTS_CXX
*       _   COMPONENT_BDEBUILD_LDFLAGS     = -DGR3_OPTS_LD

*       _   TESTDRIVER_BDEBUILD_CFLAGS     = -DTEST_GR3_OPTS_C
*       _   TESTDRIVER_BDEBUILD_CXXFLAGS   = -DTEST_GR3_OPTS_CXX
*       _   TESTDRIVER_BDEBUILD_LDFLAGS    = -DTEST_GR3_OPTS_LD
"""
        defs_str = """*                   _   OPTS_FILE       = gr3.defs

*       _   COMPONENT_BDEBUILD_CFLAGS      = -DGR3_C
*       _   COMPONENT_BDEBUILD_CXXFLAGS    = -DGR3_CXX
*       _   COMPONENT_BDEBUILD_LDFLAGS     = -DGR3_LD

*       _   TESTDRIVER_BDEBUILD_CFLAGS     = -DTEST_GR3_C
*       _   TESTDRIVER_BDEBUILD_CXXFLAGS   = -DTEST_GR3_CXX
*       _   TESTDRIVER_BDEBUILD_LDFLAGS    = -DTEST_GR3_LD
"""
        cap_str = """ !! unix  _  CAPABILITY = ALWAYS
"""

        path = os.path.join(self.repo_root, 'groups', 'gr3')
        group = repoloadutil.load_package_group(path)

        exp_group = repounits.PackageGroup(path)
        exp_group.mem = set(['gr3p1', 'gr3p2'])
        exp_group.dep = set(['extlib1', 'gr2', 'gr1'])
        exp_group.opts = self._parse_opts_str(opts_str)
        exp_group.defs = self._parse_opts_str(defs_str)
        exp_group.cap = self._parse_opts_str(cap_str)
        self.assertEqual(group, exp_group)

    def _parse_opts_str(self, str_):
        opts_file = StringIO(str_)
        parser = optionsparser.OptionsParser(opts_file)
        parser.parse()
        return parser.option_rules


if __name__ == '__main__':
    unittest.main()

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
