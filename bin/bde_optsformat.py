#!/usr/bin/env python

from __future__ import print_function
import os
import sys


def _get_tools_path():
    path = os.path.join(os.path.dirname(os.path.realpath(__file__)),
                        'tools', 'waf', 'bde')
    return path

tools_path = _get_tools_path()
sys.path = [tools_path] + sys.path

from bdeoptions import RawOptions


def _format_option(option, fill_widths):
    template = ""
    index = 0
    while index < len(fill_widths):
        template += "{%s:%s}" % (index, fill_widths[index])
        index += 1

    template += "=  {%s}" % index

    modifier = option.modifier if option.modifier else "++"

    return template.format(modifier,
                           option.platform,
                           option.config,
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

    raw_options = RawOptions()
    raw_options.read_handle(sys.stdin)

    max_field_widths = [2, 0, 0, 0]
    option_field_index = {
        'modifier': 0,
        'platform': 1,
        'config': 2,
        'key': 3,
    }

    for option in raw_options.options:
        for name in option_field_index:
            attr = getattr(option, name)
            attr = attr if attr else ''
            index = option_field_index[name]
            max_field_widths[index] = max(max_field_widths[index], len(attr))

    for line_rep in raw_options.all_lines:
        line = line_rep[0]
        option = line_rep[1]

        if option:
            print(_format_option(option, [w + 2 for w in max_field_widths]))
        else:
            print(line)

# ----------------------------------------------------------------------------
# Copyright (C) 2013-2014 Bloomberg Finance L.P.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
# ----------------------------- END-OF-FILE ----------------------------------
