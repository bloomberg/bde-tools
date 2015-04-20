import unittest

from bdebld.common import blderror
from bdebld.meta import graphutil


class TestGraph(unittest.TestCase):

    def setUp(self):
        self.group_dep = {
            'bde': ['bsl'],
            'bst': ['bsl'],
            'bce': ['bde', 'bsl'],
            'bbe': ['bsl', 'bde'],
            'bte': ['bsl', 'bde', 'bce'],
            'bae': ['bce', 'bde', 'bsl']
        }

    def test_find_external_nodes(self):
        external_nodes = graphutil.find_external_nodes(self.group_dep)
        exp_external_nodes = set(['bsl'])
        self.assertEqual(external_nodes, exp_external_nodes)

    def test_levelize(self):
        levels = graphutil.levelize(self.group_dep)
        exp_levels = [
            set(['bsl']),
            set(['bde', 'bst']),
            set(['bce', 'bbe']),
            set(['bte', 'bae'])
        ]

        self.assertEqual(levels, exp_levels)

        graph1 = {
            'a': ['b'],
            'b': ['c'],
            'c': ['b']
        }
        try:
            levels = graphutil.levelize(graph1)
            self.AssertFalse(True)
        except blderror.CycleError:
            # print(e.message)
            pass

    def test_find_cycles(self):
        graph1 = {
            'a': ['b', 'd'],
            'b': ['c'],
            'c': ['d'],
            'd': ['b'],
            'e': ['f', 'd'],
            'f': ['g'],
            'g': ['f']
        }

        graph2 = {
            'a': ['c'],
            'c': ['b'],
            'b': ['a', 'e'],
            'd': ['b'],
            'e': ['d'],
            'z': ['z']
        }

        graph3 = {
            'a': ['b'],
            'b': ['c'],
            'd': ['b']
        }

        cds = graphutil.find_cycles(graph1)
        exp_cds = [
            ['b', 'c', 'd'],
            ['f', 'g']
        ]
        self.assertEqual(cds, exp_cds)

        cds = graphutil.find_cycles(graph2)
        exp_cds = [
            ['a', 'c', 'b', 'e', 'd'],
            ['z']
        ]
        self.assertEqual(cds, exp_cds)

        cds = graphutil.find_cycles(graph3)
        self.assertEqual([], cds)
        cds = graphutil.find_cycles(self.group_dep)
        self.assertEqual([], cds)


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
