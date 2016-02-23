import unittest
import os

from bdebuild.common import sysutil


class TestSysutil(unittest.TestCase):

    def test_get_other_compiler(self):
        test_data = (
            (sysutil.CompilerType.C, '/o/bin/gcc', '/o/bin/g++'),
            (sysutil.CompilerType.C, '/o/bin/gcc-4', '/o/bin/g++-4'),
            (sysutil.CompilerType.C, '/o/bin/gcc-4.1', '/o/bin/g++-4.1'),
            (sysutil.CompilerType.C, '/o/bin/gcc-4.1.2', '/o/bin/g++-4.1.2'),
            (sysutil.CompilerType.C, '/o/bin/gcc-blah', None),
            (sysutil.CompilerType.C, '/o/bin/whatisthis', None),
            (sysutil.CompilerType.CXX, '/o/bin/gcc', None),
            (sysutil.CompilerType.CXX, '/o/bin/clang++', '/o/bin/clang'),
            (sysutil.CompilerType.CXX, '/o/bin/CC', '/o/bin/cc'),
            (sysutil.CompilerType.CXX,
             '/o/bin/xlC_r-12.3', '/o/bin/xlc_r-12.3'),
        )

        for row in test_data:
            comp_type = row[0]
            comp_path = row[1]
            exp_other_path = row[2]
            other_path = sysutil.get_other_compiler(comp_path, comp_type)
            self.assertEqual(other_path, exp_other_path)

    def test_repo_root_path(self):
        root_path = sysutil.repo_root_path()

        self.assertTrue(os.path.isdir(os.path.join(root_path, 'etc')))

    def test_match_version_strs(self):
        test_data = (
            ("1.0.0", "1.0.0", "1.0.0", True),
            ("1.0.0", "0.9.9", "1.0.0", True),
            ("1.0.0", "1.0.0", "1.0.1", True),
            ("1.0.0", "0.9.9", "1.0.1", True),
            ("1.0.0", "1.0.1", "1.0.2", False),
            ("1.0.0", "0.9.8", "0.9.9", False),
            ("999.98", "999.97", "999.99", True),
            ("999.98", "999.99", "999.99", False),
            ("111", "110", "112", True),
            ("111", "111", "111", True),
            ("111", "112", "113", False),
            ("111", "99", "99", False),
            ("1.0.0", None, "1.0.0", True),
            ("1.0.0", "1.0.0", None, True),
            ("1.0.0", None, None, True),
            ("1.0.0", None, "0.9.9", False),
            ("1.0.0", "1.1.1", None, False),
        )

        for row in test_data:
            comp_str = row[0]
            match_min_str = row[1]
            match_max_str = row[2]
            exp_result = row[3]
            self.assertEqual(exp_result, sysutil.match_version_strs(
                comp_str, match_min_str, match_max_str))


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
