#!/usr/bin/env python

from __future__ import print_function
import os
import sys


def _get_tools_path():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)), 'lib')
    return path

tools_path = _get_tools_path()
sys.path = [tools_path] + sys.path

import bdemeta.optionsparser
import bdemeta.options


def _format_rule(option, fill_widths):
    template = ""
    index = 0
    while index < len(fill_widths):
        template += "{%s:%s}" % (index, fill_widths[index])
        index += 1

    template += "=  {%s}" % index

    return template.format(
        bdemeta.options.OptionCommand.to_str(option.command),
        option.uplid,
        option.ufid,
        option.key,
        option.value)

if __name__ == "__main__":
    usage = \
        """Usage: cat <opts_file> | bde_opts_format.py

Format the text from stdin in the options file format, which is used by opts
and defs meta-data files, and print the result to stdout.

The formatter aligns each section of the option rules using two spaces as
padding. Comments and blank lines will be left in-place unmodified.

"""

    if len(sys.argv) > 1:
        print(usage, file=sys.stderr)
        sys.exit(1)

    parser = bdemeta.optionsparser.OptionsParser(sys.stdin)
    parser.parse()

    max_field_widths = [2, 0, 0, 0]
    option_field_index = {
        'command': (0, bdemeta.options.OptionCommand.to_str),
        'uplid': (1, str),
        'ufid': (2, str),
        'key': (3, str),
    }

    for rule in parser.option_rules:
        for name in option_field_index:
            attr = getattr(rule, name)
            index = option_field_index[name][0]
            func = option_field_index[name][1]
            max_field_widths[index] = max(max_field_widths[index],
                                          len(func(attr)))

    for line_rep in parser.all_lines:
        line = line_rep[0]
        rule = line_rep[1]

        if rule:
            print(_format_rule(rule, [w + 2 for w in max_field_widths]))
        else:
            print(line)

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
