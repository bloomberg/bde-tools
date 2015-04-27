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
