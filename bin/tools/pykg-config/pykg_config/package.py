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

# File: package.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Package class for pykg-config.

Stores information read from a pkg-config file.

"""

__version__ = "$Revision: $"
# $Source$

from copy import deepcopy
from os.path import abspath, dirname, join, normpath
import re
import shlex
import sys

from pykg_config.errorprinter import ErrorPrinter
from pykg_config.exceptions import ParseError
from pykg_config.pcfile import read_pc_file
from pykg_config.substitute import substitute
from pykg_config.props import *
from pykg_config.options import Options
from pykg_config.packagespeclist import parse_package_spec_list
from pykg_config.version import BadVersionFormatError, Version

##############################################################################
# Package class

class Package:
    """This class stores the information gleaned from a pkg-config
    file, allowing quick access to it.

    """

    def __init__(self, filename=None, globals={}):
        # Different platforms may use different flags and extensions
        if sys.platform == 'win32' and Options().get_option('use_msvc_syntax'):
            self.lib_suffix = '.lib'
        else:
            self.lib_suffix = ''

        # Parse a file if one was given
        if filename is not None:
            self.load_from_pc_file(filename, globals)
            if filename.endswith('-uninstalled'):
                self.uninstalled = True
            else:
                self.uninstalled = False
        else:
            self.clear()

    def __str__(self):
        result = self.filename + '\nProperties:\n'
        for key in self.properties:
            if key == 'requires' or key == 'requires.private' or \
                    key == 'conflicts':
                result += '%s:\t%s\n' % \
                            (key, [str(a) for a in self.properties[key]])
            else:
                result += '%s:\t%s\n' % (key, self.properties[key])
        result += 'Variables:\n'
        for key in self.variables:
            result += '%s:\t%s\n' % (key, self.variables[key])
        return result

    @property
    def variables(self):
        """Variables used by the package properties."""
        return self._vars

    @variables.setter
    def variables(self, new_vars):
        self._vars = new_vars

    @property
    def properties(self):
        """Properties of the package."""
        return self._props

    @properties.setter
    def properties(self, new_props):
        self._props = new_props

    @property
    def filename(self):
        """File name of the pkg-config file this package was loaded from."""
        return self._filename

    def clear(self):
        """Clear all package data."""
        self._props = deepcopy(empty_processed_props)
        self._vars = {}
        self.raw_props = deepcopy(empty_raw_props)
        self.raw_vars = {}
        self.filename = ''

    def get_raw_property(self, prop):
        """Get a property value in its raw format, as it appears in the
        file.

        """
        return self.raw_props[prop]

    def get_raw_variable(self, var):
        """Get a variable in its raw format, as it appears in the file."""
        return self.raw_vars[var]

    def sanity_check(self):
        return True

    def load_from_pc_file(self, filename, global_variables):
        """Load data from a package config file and process it."""
        self.raw_vars, self.variables, \
                self.raw_props = read_pc_file(filename, global_variables)
        self._filename = filename
        self._process_props(global_variables)

    def _process_props(self, global_variables):
        # Processing of file data
        props = self.raw_props

        # May need to reset the prefix variable
        if sys.platform == 'win32' and \
                not Options().get_option('dont_define_prefix'):
            # Use the location of the .pc file to guess a suitable value for
            # the prefix variable. Start by checking if the absolute .pc 
            # location ends with '\lib\pkgconfig'.
            abs_loc = dirname(abspath(self.filename))
            if Options().get_option('normalise_paths'):
                abs_loc = normpath(abs_loc)
            else:
                # If not normalising paths, then all paths should be in /
                # format for consistency
                abs_loc = abs_loc.replace('\\', '/')
            if abs_loc.endswith('\\lib\\pkgconfig'):
                self.variables[Options().get_option('prefix_variable')] = \
                        abs_loc.rstrip('\\lib\\pkgconfig')
                ErrorPrinter().debug_print('Replaced {0} with \
{1}'.format(Options().get_option('prefix_variable'),
            self.variables[Options().get_option('prefix_variable')]))

        # Perform substitutions
        for key in props:
            props[key] = substitute(props[key], self.variables,
                    global_variables)

        # Parse the data
        self.properties = deepcopy(empty_processed_props)
        self.properties['name'] = props['name']
        if props['description']:
            self.properties['description'] = props['description']
        if props['version']:
            try:
                self.properties['version'] = Version(props['version'])
            except BadVersionFormatError as e:
                raise BadVersionFormatError(e.versionstring, props['name'])
        self.properties['requires'] = \
                parse_package_spec_list(props['requires'])
        self.properties['requires.private'] = \
            parse_package_spec_list(props['requires.private']) + \
            self.properties['requires']
        self.properties['conflicts'] = \
                parse_package_spec_list(props['conflicts'])
        self._parse_cflags(props['cflags'])
        self._parse_libs(props['libs'])
        self._parse_libs(props['libs.private'], dest='private.')

    def _parse_cflags(self, value):
        flags = shlex.split(value, posix=False)
        for flag in flags:
            if flag.startswith('-I'):
                if flag[2:] not in \
                        Options().get_option('forbidden_cflags'):
                    # Prepend pc_sysrootdir if necessary
                    pc_sysrootdir = Options().get_option('pc_sysrootdir')
                    if pc_sysrootdir:
                        include_dir = join(pc_sysrootdir, flag[2:].strip())
                    else:
                        include_dir = flag[2:].strip()
                    if Options().get_option('full_compatibility') and \
                            include_dir:
                        # Drop everything after the first space when trying
                        # to be fully compatible (sucky behaviour on Win32).
                        include_dir = include_dir.split()[0]
                    if sys.platform == 'win32':
                        if Options().get_option('normalise_paths'):
                            include_dir = normpath(include_dir)
                        else:
                            include_dir = include_dir.replace('\\', '/')
                    self.properties['include_dirs'].append(include_dir)
            else:
                self.properties['other_cflags'].append(flag.strip())


    def _parse_libs(self, value, dest=''):
        # Parse lib flags
        libs = shlex.split(value)
        skip_next = False
        for ii, lib in enumerate(libs):
            if skip_next:
                # Possibly skip an entry that was eaten by a -framework
                skip_next = False
                continue
            if lib.startswith('-l'):
                self.properties[dest + 'libs'].append(lib[2:].strip() + \
                        self.lib_suffix)
            elif lib.startswith('-L'):
                if lib[2:] not in \
                        Options().get_option('forbidden_libdirs'):
                    # Prepend pc_sysrootdir if necessary
                    pc_sysrootdir = Options().get_option('pc_sysrootdir')
                    if pc_sysrootdir:
                        libpath = join(pc_sysrootdir, lib[2:].strip())
                    else:
                        libpath = lib[2:].strip()
                    if Options().get_option('full_compatibility'):
                        # Drop everything after the first space when trying
                        # to be fully compatible (sucky behaviour on Win32).
                        libpath = libpath.split()[0]
                    if sys.platform == 'win32':
                        if Options().get_option('normalise_paths'):
                            libpath = normpath(libpath)
                        else:
                            libpath = libpath.replace('\\', '/')
                    self.properties[dest + 'libpaths'].append(libpath)
            elif lib.startswith('-framework'):
                self.properties[dest + 'otherlibs']. \
                        append(libs[ii + 1].strip() + self.lib_suffix)
                skip_next = True
            else:
                self.properties[dest + 'otherlibs'].append(lib.strip() + \
                        self.lib_suffix)


# vim: tw=79

