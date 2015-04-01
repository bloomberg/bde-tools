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

# File: operators.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Comparison operators."""

__version__ = "$Revision: $"
# $Source$

from pykg_config.exceptions import ParseError

##############################################################################
# Exceptions

class BadOperatorError(ParseError):
    """Invalid operator format.

    Attributes:
        operator -- Operator text that triggered the error."""
    def __init__(self, operator):
        self.operator = operator

    def __str__(self):
        return self.operator


##############################################################################
# Constants

LESS_THAN = 0
LESS_THAN_EQUAL = 1
EQUAL = 2
GREATER_THAN_EQUAL = 3
GREATER_THAN = 4
NOT_EQUAL = 5
ALWAYS_MATCH = 6


##############################################################################
# Support functions

def text_to_operator(text):
    if not text:
        return ALWAYS_MATCH
    elif text == '<':
        return LESS_THAN
    elif text == '<=':
        return LESS_THAN_EQUAL
    elif text == '=':
        return EQUAL
    elif text == '>=':
        return GREATER_THAN_EQUAL
    elif text == '>':
        return GREATER_THAN
    elif text == '!=':
        return NOT_EQUAL
    else:
        raise BadOperatorError(text)


def operator_to_text(operator):
    if operator == ALWAYS_MATCH:
        return ' any '
    elif operator == LESS_THAN:
        return '<'
    elif operator == LESS_THAN_EQUAL:
        return '<='
    elif operator == EQUAL:
        return '='
    elif operator == GREATER_THAN_EQUAL:
        return '>='
    elif operator == GREATER_THAN:
        return '>'
    elif operator == NOT_EQUAL:
        return '!='
    else:
        raise BadOperatorError(str(operator))


# vim: tw=79

