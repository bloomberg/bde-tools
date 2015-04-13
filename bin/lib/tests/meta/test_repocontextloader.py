import os
import unittest

from collections import defaultdict

from bdebld.meta import repocontextloader
from bdebld.meta import repounits


class TestLoader(unittest.TestCase):

    def setUp(self):
        self.repo_root = os.path.join(
            os.path.dirname(os.path.realpath(__file__)), 'repos', 'one')

    def test_loader(self):
        loader = repocontextloader.RepoContextLoader(self.repo_root)
        loader.load()
        repo_context = loader.repo_context

        units = defaultdict(set)
        for unit in repo_context.units.values():
            units[unit.type_].add(unit.name)

        exp_units = {
            repounits.UnitType.PACKAGE_NORMAL: set(
                ['gr1p1', 'gr3p1', 'gr3p2']),
            repounits.UnitType.PACKAGE_PLUS: set(['gr2a+b', 'gr2b+c']),
            repounits.UnitType.PACKAGE_APPLICATION: set(['app1']),
            repounits.UnitType.PACKAGE_STAND_ALONE: set(['a_adp1']),
            repounits.UnitType.THIRD_PARTY_DIR: set(['mytplib']),
            repounits.UnitType.GROUP: set(['gr1', 'gr2', 'gr3', 'eg1'])
        }

        self.assertEqual(dict(units), exp_units)


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
