import os
import unittest

from bdebld.meta import repocontextloader
from bdebld.meta import repocontext


class TestLoader(unittest.TestCase):

    def setUp(self):
        self.repo_root = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos', 'one')

    def test_loader(self):
        loader = repocontextloader.RepoContextLoader(self.repo_root)
        loader.load()
        repo_context = loader.repo_context

        exp_package_groups = set(['gr1', 'gr2', 'gr3', 'eg1'])
        exp_sa_packages = set(['a_adp1', 'app1'])
        exp_tp_packages = set(['mytplib'])
        exp_normal_packages = set(['gr1p1', 'gr3p1', 'gr3p2', 'gr2a+b',
                                   'gr2b+c'])

        self.assertEqual(repo_context.root_path, self.repo_root)
        self.assertEqual(set(repo_context.package_groups.keys()),
                         exp_package_groups)
        self.assertEqual(set(repo_context.packages.keys()),
                         exp_sa_packages | exp_normal_packages)
        self.assertEqual(set(repo_context.third_party_packages.keys()),
                         exp_tp_packages)


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
