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

# File: version.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Version object.

Stores a version and can compare it with other versions.

"""

__version__ = "$Revision: $"
# $Source$

import re

from pykg_config.errorprinter import ErrorPrinter
from pykg_config.exceptions import ParseError

##############################################################################
# Exceptions

class BadVersionFormatError(ParseError):
    """Generic error parsing a pkg-config file.

    Attributes:
        versionstring -- String containing the badly-formatted version."""
    def __init__(self, versionstring, package = ''):
        self.versionstring = versionstring
        self.package = package

    def __str__(self):
        return '%s: %s' % (self.package, self.versionstring)


##############################################################################
# Version class

class Version:
    def __init__(self, version_string=None):
        if version_string is not None:
            self._parse_version(version_string)
            ErrorPrinter().debug_print('Parsed %s into %s',
                                       (version_string, self.comps))
        else:
            self.raw_string = '0'
            self.comps = [0]

    def __str__(self):
        return self.raw_string

    def __lt__(self, other):
        if self._compare_components(other.comps) == -1:
            return True
        return False

    def __le__(self, other):
        result = self._compare_components(other.comps)
        if result == -1 or result == 0:
            return True
        return False

    def __eq__(self, other):
        if self._compare_components(other.comps) == 0:
            return True
        return False

    def __ne__(self, other):
        if self._compare_components(other.comps) != 0:
            return True
        return False

    def __gt__(self, other):
        if self._compare_components(other.comps) == 1:
            return True
        return False

    def __ge__(self, other):
        result = self._compare_components(other.comps)
        if result == 0 or result == 1:
            return True
        return False

    def is_empty(self):
        if self == Version():
            return True
        return False

    def _parse_version(self, version_string):
        # Parse a version into components.
        self.raw_string = version_string
        self.comps = []
        start = 0
        while start < len(version_string):
            m = re.match(r'[-._~+ ]?(?P<comp>[a-zA-Z0-9%]+)',
                         version_string[start:], re.U)
            if m is None:
                # Stop pulling out components when the start of the string
                # no longer matches
                #raise BadVersionFormatError(version_string)
                # pkg-config apparently ignores poorly-formatted versions
                return
            comp = m.group('comp')
            try:
                comp = int(comp)
            except ValueError:
                pass
            self.comps.append(comp)
            start += m.end()

    def _compare_components(self, other_comps):
        # Loop through the components, comparing each one in turn.
        # When one differs, return how it differs.
        # -1 for less than, 0 for equal, 1 for greater than.
        if self.comps == other_comps:
            return 0
        comp_len = min(len(self.comps), len(other_comps))
        for left, right in zip(self.comps[:comp_len], other_comps[:comp_len]):
            if left < right:
                return -1
            elif left > right:
                return 1
            else:
                continue
        # Have exhausted all comps in the minimal list, so now see if
        # the trailing part of the longer list is all 0 or something else.
        # All 0 means it's still equal, something else means it's greater
        # than.
        if len(self.comps) < len(other_comps):
            remainder = other_comps[comp_len:]
            # If other_comps remainder is not all 0, self is less than.
            result = -1
        elif len(self.comps) == len(other_comps):
            # There is no left over bit, versions must be equal
            return 0
        else:
            remainder = self.comps[comp_len:]
            result = 1
        for comp in remainder:
            try:
                comp = int(comp)
                if comp != 0:
                    return result
            except ValueError:
                return result
        # If got to here, then none of the trailing components were non-zero,
        # so they don't matter and the final result is equal.
        return 0


# vim: tw=79

