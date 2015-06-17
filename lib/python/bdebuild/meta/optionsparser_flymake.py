"""Parse options rules.
"""

import re

from bdebuild.common import blderror
from bdebuild.meta import optiontypes


def parse_option_rules_file(file_path):
    """Parse the option rules file.

    Args:
        file_path (str): Path to the options file.

    Returns:
        list of OptionRules

    Raises:
        IOError: Error accessing the file.
        InvalidOptionFileError: Invalid option file.
    """

    with open(file_path) as f:
        parser = OptionsParser(f)
        try:
            parser.parse()
        except blderror.InvalidOptionRuleError as e:
            raise blderror.InvalidOptionFileError(file_path, e)
        return parser.option_rules


class OptionsParser(object):
    """Parser for option rules.

    This object parses option rules from a specified file.

    Attributes:
        option_rules (list of OptionRule): Parsed options rules
        all_lines (list of (str, OptionRule)): List of line and associated
            option rule, which may be None for a particular line.
    """
    _OPT_LINE_RE = re.compile(r'''^\s*(?P<command>!!|--|\+\+|>>|<<)?
                                 \s* (?P<uplid>\S+)
                                 \s+ (?P<ufid>\S+)
                                 \s+ (?P<key>\S+)
                                 \s*=\s* (?P<value>.*?)
                                 (?P<cont>\\)?
                                 $''',
                              re.VERBOSE)

    _OPT_COMMENT_OR_EMTPY_RE = re.compile(r'^\s*([#].*)?$')

    _OPT_CONTINUE_RE = re.compile(r'^(?P<value>.*?)(?P<cont>\\)?$')

    def __init__(self, opts_file):
        """Initialize the object with an options file.

        Args:
            opts_file (File): The file handle from which to read option rules.
        """
        self.opts_file = opts_file
        self.option_rules = []
        self.all_lines = []

    def parse(self):
        """Parse the options file specified on construction.

        Raises:
           InvalidOptionRuleError: The option rule is invalid.
        """
        continuation = False
        got_line = False

        line_num = 0
        for line in self.opts_file:
            line_num += 1
            line = line.rstrip('\n')
            if not continuation:
                rule = optiontypes.OptionRule()
                if self._OPT_COMMENT_OR_EMTPY_RE.match(line):
                    self.all_lines.append((line.rstrip(), None))
                    got_line = False
                else:
                    m = self._OPT_LINE_RE.match(line)
                    if m:
                        got_line = True
                        if m.group('command'):
                            rule.command = optiontypes.OptionCommand.from_str(
                                m.group('command'))
                        else:
                            rule.command = optiontypes.OptionCommand.ADD

                        try:
                            rule.uplid = optiontypes.Uplid.from_str(
                                m.group('uplid'))
                        except blderror.InvalidUplidError:
                            raise blderror.InvalidOptionRuleError(
                                line_num, line, "invalid UPLID")
                        rule.ufid = optiontypes.Ufid.from_str(m.group('ufid'))
                        rule.key = m.group('key')
                        rule.value = m.group('value')
                        continuation = not m.group('cont') is None
                    else:
                        raise blderror.InvalidOptionRuleError(
                            line_num, line, "invalid format")
            else:
                # The previous line continues.

                m = self._OPT_CONTINUE_RE.match(line)
                assert(m)
                assert(got_line)

                rule.value += m.group('value')
                continuation = not m.group('cont') is None

            if got_line and not continuation:
                rule.value = rule.value.strip()
                self.option_rules.append(rule)
                self.all_lines.append((line, rule))

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
