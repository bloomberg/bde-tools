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

# File: options.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Singleton containing option values."""

__version__ = "$Revision: $"
# $Source$

import sys

from pykg_config.exceptions import PykgConfigError

##############################################################################
# Exceptions

class NoSuchOptionError(PykgConfigError):
    """The requested option has not been set.

    Attributes:
        option -- The option that doesn't exist."""
    def __init__(self, option):
        self.option = option

    def __str__(self):
        return self.option


##############################################################################
# Options singleton class

class Options(object):
    def __new__(cls, *p, **k):
        if not '_the_instance' in cls.__dict__:
            cls._the_instance = object.__new__(cls)
        return cls._the_instance

    def init_options(self):
        self.options = {'use_msvc_syntax': True,
                        'dont_define_prefix': False,
                        'prefix_variable': 'prefix',
                        'verbose': False,
                        'pc_path': '',
                        'uninstalled_only': False,
                        'prefer_uninstalled': True,
                        'pc_sysrootdir': '',
                        'pc_topbuilddir': '',
                        'print_errors': True,
                        'short_errors': False,
                        'error_dest': sys.stderr,
                        'debug': False,
                        'search_string': '',
                        'private_libs': False,
                        'forbidden_libdirs': [],
                        'forbidden_cflags': [],
                        'is_64bit': False,
                        'full_compatibility': False,
                        'normalise_paths': True}

    def set_option(self, option, value):
        if not hasattr(self, 'options'):
            self.init_options()
        self.options[option] = value

    def get_option(self, option):
        if not hasattr(self, 'options'):
            self.init_options()
        if not option in self.options:
            raise NoSuchOptionError(option)
        return self.options[option]


# vim: tw=79

