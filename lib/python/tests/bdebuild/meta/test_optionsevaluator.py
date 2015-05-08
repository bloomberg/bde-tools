import unittest

try:
    from cStringIO import StringIO
except:
    from io import StringIO

from bdebuild.meta import optionsevaluator
from bdebuild.meta import optionsparser
from bdebuild.meta import optiontypes
from bdebuild.common import sysutil


class TestOptionsEvaluator(unittest.TestCase):

    def test_match_rule(self):
        rule = optiontypes.OptionRule(
            optiontypes.OptionCommand.ADD,
            optiontypes.Uplid.from_str('unix-linux-'),
            optiontypes.Ufid.from_str('dbg'), 'KEY', 'VAL')

        evaluator1 = optionsevaluator.OptionsEvaluator(
            optiontypes.Uplid.from_str('unix-linux-x86-3.2.0-gcc-4.7.2'),
            optiontypes.Ufid.from_str('dbg_mt_exc'))
        self.assertTrue(evaluator1._match_rule(rule))

        evaluator2 = optionsevaluator.OptionsEvaluator(
            optiontypes.Uplid.from_str('unix-linux-x86-3.2.0-gcc-4.7.2'),
            optiontypes.Ufid.from_str('opt_mt_exc'))
        self.assertFalse(evaluator2._match_rule(rule))

        evaluator3 = optionsevaluator.OptionsEvaluator(
            optiontypes.Uplid.from_str('unix-aix-ppc-5.10-gcc-4.7.2'),
            optiontypes.Ufid.from_str('dbg_mt_exc'))
        self.assertFalse(evaluator3._match_rule(rule))

    def test_evaluate(self):
        opts_string = """
!! unix- _   K1 = V1
!! unix- dbg K2 = V2 $(K1)
unix- dbg K2 = V3
!! unix- opt K2 = V4
++ unix- _ K1 = V5
>> unix- _ K1 = V6
<< unix- _ K1 = V7
-- unix- _ K1 = V8
!! unix- _ XLC_INTERNAL_PREFIX1 = IGNORED
!! unix- _ BDE_COMPILER_FLAG = gcc
!! windows- _ BDE_COMPILER_FLAG = msvc
!! unix-*-*-*-def _ K3 = DEF_MATCH
!! unix-*-*-*-clang _ K4 = DEF_MATCH
!! unix- _ K5 =
++ unix- _ K5 = K5_VAL
        """
        opts_file = StringIO(opts_string)
        parser = optionsparser.OptionsParser(opts_file)
        parser.parse()

        ev = optionsevaluator.OptionsEvaluator(
            optiontypes.Uplid.from_str('unix-linux-x86-3.2.0-gcc-4.7.2'),
            optiontypes.Ufid.from_str('dbg_mt_exc'))

        # ev.store_option_rules(parser.option_rules, ['K1', 'K2'])
        # ev.evaluate(['K1', 'K2'])
        ev.store_option_rules(parser.option_rules)
        ev.evaluate()

        expected_results = {
            'K1': 'V8 V7V1 V5V6',
            'K2': 'V2 V8 V7V1 V5V6 V3',
            'K3': 'DEF_MATCH',
            'K5': 'K5_VAL',
            'BDE_COMPILER_FLAG': 'gcc'
        }
        self.assertEqual(ev.results, expected_results)

    def test_evaluate_shell_command(self):
        if sysutil.unversioned_platform() != 'linux':
            # This test runs shell commands, so only run it on Linux for now.
            pass

        opts_string = """
!! unix- _ K1 = a \\"`echo 123`\\" b
!! unix- _ K2 = $(shell echo 123)
        """
        opts_file = StringIO(opts_string)
        parser = optionsparser.OptionsParser(opts_file)
        parser.parse()

        ev = optionsevaluator.OptionsEvaluator(
            optiontypes.Uplid.from_str('unix-linux-x86-3.2.0-gcc-4.7.2'),
            optiontypes.Ufid.from_str('dbg_mt_exc'))

        # ev.store_option_rules(parser.option_rules, ['K1', 'K2'])
        # ev.evaluate(['K1', 'K2'])
        ev.store_option_rules(parser.option_rules)
        ev.evaluate()

        expected_results = {
            'K2': '123',
            'K1': 'a "123" b'
        }
        self.assertEqual(ev.results, expected_results)

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
