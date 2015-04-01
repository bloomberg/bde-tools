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

# File: substitute.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Substitutes values. 

Recursive substitution can be performed until no substitutions are left.
An infinite recursion check is performed first to prevent infinite
loops in this case.

"""

__version__ = "$Revision: $"
# $Source$

import re

from pykg_config.exceptions import PykgConfigError

##############################################################################
# Exceptions

class InfiniteRecursionError(PykgConfigError):
    """A variable refers to itself, which will cause infinite recursion
    when substitution is performed.

    Attributes:
        variable -- The variable that refers to itself.

    """
    def __init__(self, variable):
        self.variable = variable

    def __str__(self):
        return self.variable


class UndefinedVarError(PykgConfigError):
    """A variable is not defined.

    Attributes:
        variable -- The variable that is not defined.
        pkgfile -- The file with the error. Not always set.

    """
    def __init__(self, variable, pkgfile=None):
        self.variable = variable
        self.pkgfile = pkgfile

    def __str__(self):
        return self.variable


##############################################################################
# Public functions

def substitute(value, replacements, globals={}):
    """Substitutes variables once.

    Variables in the given value are substituted. No recursion is
    performed. replacements is a dictionary of variables.

    """
    for name in get_all_substitutions(value):
        if name in globals:
            value = replace_in_string(value, name, globals[name])
        elif name in replacements:
            value = replace_in_string(value, name, replacements[name])
        else:
            raise UndefinedVarError(name)
    value = collapse_escapes(value)
    return value


##############################################################################
# Private functions

def replace_in_string(value, name, substitution):
    # Replace all instances of name in value with substitution
    to_replace = get_to_replace_re(name)
    return to_replace.sub(substitution, value)


def get_to_replace_re(name):
    # Build the re object that matches a given substition name
    return re.compile('(?<!\$)\$\{%s\}' % name, re.U)


def get_all_substitutions(value):
    found_names = re.findall('(?<!\$)\${(?P<name>[\w.]+)\}', value, flags=re.U)
    names = []
    for name in found_names:
        if name not in names:
            names.append (name)
    return names


def collapse_escapes(value):
    return value.replace('$$', '$')


# vim: tw=79

