# Copyright (c) 2009-2012, Geoffrey Biggs
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
#    * Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#    * Redistributions in binary form must reproduce the above copyright
#      notice, this list of conditions and the following disclaimer in the
#      documentation and/or other materials provided with the distribution.
#    * Neither the name of the Geoffrey Biggs nor the names of its
#      contributors may be used to endorse or promote products derived from
#      this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# File: pcfile.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Parse pkg-config files.

Contains functions that read and parse metadata files in the format
used by pkg-config.

"""

__version__ = "$Revision: $"
# $Source$

import re

from pykg_config.errorprinter import ErrorPrinter
from pykg_config.exceptions import ParseError
from pykg_config.substitute import substitute
from pykg_config.props import empty_raw_props

# Constants
VARIABLE = 0
PROPERTY = 1
empty_vars = {}

##############################################################################
# Exceptions

class EmptyPackageFileError(ParseError):
    """The given pkg-config file had no lines in it."""
    pass


class MalformedLineError(ParseError):
    """The line is not a correctly-formatted variable or a property.

    Attributes:
        line -- The incorrectly-formatted line.

    """
    def __init__(self, line):
        self.line = line

    def __str__(self):
        return self.line


class MultiplyDefinedValueError(ParseError):
    """A value has been defined more than once.

    Attributes:
        line -- The line containing the duplicate value.

    """
    def __init__(self, line):
        self.line = line

    def __str__(self):
        return self.line


class TrailingContinuationCharError(ParseError):
    """The last line in a file has a trailing continuation character.

    Attributes:
        line -- The line containing the trailing character.

    """
    def __init__(self, line):
        self.line = line

    def __str__(self):
        return self.line


##############################################################################
# Public functions

def read_pc_file(filename, global_variables):
    """Read and parse it into two dictionaries (variables and properties).

    Returns variables and properties.

    """
    ErrorPrinter().set_variable('filename', filename)
    ErrorPrinter().debug_print('Parsing %(filename)')
    pcfile = open(filename, 'r')
    lines = pcfile.readlines()
    if not lines:
        raise EmptyPackageFileError(filename)
    raw_vars, vars, props = parse_pc_file_lines(lines, global_variables)
    pcfile.close()
    return raw_vars, vars, props


##############################################################################
# Private functions

def parse_pc_file_lines(lines, globals):
    # Parse all lines from a pkg-config file, building vars and props
    # dictionaries.
    raw_vars = {}
    vars = {}
    props = empty_raw_props.copy()
    seen_props = []
    for line in merge_lines(lines, '\\'):
        raw_vars, vars, props, seen_props = parse_line(strip_comments(line).strip(),
                                                       raw_vars, vars, props,
                                                       seen_props, globals)

    return raw_vars, vars, props


def merge_lines(lines, cont_char):
    # Merge any lines ending with the given character with the following line.
    # Return a list of lines. Raises TrailingContinuationCharError if the
    # final line has the continuation character.
    if lines[-1][-1] == cont_char:
        raise TrailingContinuationCharError(line)
    result = []
    ii = 0
    while ii < len(lines):
        new_line = lines[ii].rstrip()
        if new_line == '':
            ii += 1
            continue
        while new_line[-1] == cont_char:
            # Drop the \n and the continuation char
            new_line = new_line[:-2] + ' '
            ii += 1
            new_line += lines[ii].rstrip()
        result.append(new_line)
        ii += 1
    return result


def parse_line(line, raw_vars, vars, props, seen_props, globals):
    # Parse a single line from the file, adding its value to the props or vars
    # dictionary as appropriate.
    if not line:
        return raw_vars, vars, props, seen_props
    key, value, type = split_pc_file_line(line)
    # Check first if it's one of the known keys.
    if type == VARIABLE:
        # Perform substitution using variables found so far and global
        # variables, then store the result.
        if key in vars:
            raise MultiplyDefinedValueError(key)
        if key in globals:
            ErrorPrinter().debug_print('Adding %s -> %s to vars from globals',
                                       (key, value))
            raw_vars[key] = value.strip ()
            vars[key] = substitute (globals[key], vars, globals)
        else:
            ErrorPrinter().debug_print('Adding %s -> %s to vars', (key, value))
            raw_vars[key] = value.strip ()
            vars[key] = substitute (value.strip(), vars, globals)
    elif type == PROPERTY:
        if key in seen_props:
            raise MultiplyDefinedValueError(key)
        if key.lower() in empty_raw_props:
            if value is None:
                value = empty_raw_props[key.lower()]
            ErrorPrinter().debug_print('Adding %s -> %s to props', (key, value))
            props[key.lower ()] = value
            seen_props.append(key)
        else:
            # As per the original pkg-config, don't raise errors on unknown
            # keys because they may be from future additions to the file
            # format. But log an error
            ErrorPrinter().debug_print('Unknown key/value in %(filename)s:\n%s: %s',
                                       (key, value))
    else:
        # Probably a malformed line. Ignore it.
        pass
    return raw_vars, vars, props, seen_props


def strip_comments(line):
    # Strip comments from a line, returning the uncommented part or a blank
    # string if the whole line was a comment.
    commentStart = line.find('#')
    if commentStart == -1:
        return line
    else:
        return line[:commentStart]


property_re = re.compile('(?P<key>[\w.]+):\s*(?P<value>.+)?', re.U)
variable_re = re.compile('(?P<var>[\w.]+)=\s*(?P<value>.+)?', re.U)
def split_pc_file_line(line):
    # Split a line into key and value, and determine if it is a property or a
    # variable.
    m = property_re.match(line)
    if m is not None:
        return m.group('key'), m.group('value'), PROPERTY

    m = variable_re.match(line)
    if m is not None:
        if m.group('value') is None:
            return m.group('var'), '', VARIABLE
        else:
            return m.group('var'), m.group('value'), VARIABLE

    # Gloss over malformed lines (that's what pkg-config does).
    ErrorPrinter().debug_print('Malformed line: {0}'.format(line))
    return None, None, None


# vim: tw=79

