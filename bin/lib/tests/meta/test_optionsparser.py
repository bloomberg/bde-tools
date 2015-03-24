import unittest

try:
    from cStringIO import StringIO
except:
    from io import StringIO

from bdebld.meta import optionsparser
from bdebld.meta import options


class TestOptionsParser(unittest.TestCase):
    def setUp(self):
        self.opts_string = """
++ unix-linux-x86_64-3.2.0-gcc-4.7.2 _ KEY1 = VAL1
-- unix-linux-*-3.2.0-gcc dbg KEY2 = VAL2

# COMMENT
-- unix-linux-*-3.2.0-gcc- dbg KEY2 = VAL2
!! * dbg_mt_exc KEY3 = VAL3
>> unix- opt_mt KEY4 = VAL4_1 \
VAL4_2
        """
        self.opts_file = StringIO(self.opts_string)
        self.expected_vals = (
            (1, (options.OptionCommand.ADD,
                 options.Uplid('unix', 'linux', 'x86_64', '3.2.0',
                               'gcc', '4.7.2'),
                 options.Ufid(),
                 'KEY1',
                 'VAL1')),
            (2, (options.OptionCommand.INSERT,
                 options.Uplid('unix', 'linux', '*', '3.2.0', 'gcc'),
                 options.Ufid(['dbg']),
                 'KEY2',
                 'VAL2')),
            (5, (options.OptionCommand.INSERT,
                 options.Uplid('unix', 'linux', '*', '3.2.0', 'gcc'),
                 options.Ufid(['dbg']),
                 'KEY2',
                 'VAL2')),
            (6, (options.OptionCommand.OVERRIDE,
                 options.Uplid(),
                 options.Ufid(['dbg', 'mt', 'exc']),
                 'KEY3',
                 'VAL3')),
            (7, (options.OptionCommand.APPEND,
                 options.Uplid('unix'),
                 options.Ufid(['opt', 'mt']),
                 'KEY4',
                 'VAL4_1 VAL4_2'))
        )

    def test_parse(self):
        parser = optionsparser.OptionsParser(self.opts_file)
        parser.parse()

        lines = self.opts_string.split('\n')
        exp_option_rules = []
        exp_all_lines = []
        for val in self.expected_vals:
            pos = val[0]
            rule = options.OptionRule(*val[1])
            exp_option_rules.append(rule)
            while len(exp_all_lines) < pos:
                exp_all_lines.append((lines[len(exp_all_lines)], None))
            exp_all_lines.append((lines[len(exp_all_lines)], rule))

        exp_all_lines.append(('', None))

        self.assertEqual(exp_option_rules, parser.option_rules)
        self.assertEqual(exp_all_lines, parser.all_lines)


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
