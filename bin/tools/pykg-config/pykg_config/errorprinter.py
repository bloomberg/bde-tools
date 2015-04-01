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

# File: errorprinter.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Error printing singleton.

Prints strings given dependent on options set in Options(). Variables can be
set that will be replaced during string printing.

"""

__version__ = "$Revision: $"
# $Source$

from pykg_config.options import Options

class ErrorPrinter(object):
    def __new__(cls, *p, **k):
        if not '_the_instance' in cls.__dict__:
            cls._the_instance = object.__new__(cls)
        return cls._the_instance

    def set_variable(self, var, value):
        if not hasattr(self, 'vars'):
            self.vars = {}
        self.vars[var] = value

    def debug_print(self, line, args=None):
        if not Options().get_option('debug'):
            return
        if hasattr(self, 'vars'):
            for var in self.vars:
                line = line.replace('%(' + var + ')', self.vars[var])
        if args is not None:
            line = line % args
        Options().get_option('error_dest').write(line + '\n')

    def error(self, line, args=None):
        if hasattr(self, 'vars'):
            for var in self.vars:
                line = line.replace('%(' + var + ')', self.vars[var])
        if args is not None:
            line = line % args
        Options().get_option('error_dest').write(line + '\n')

    def verbose_error(self, line, args=None):
        if not Options().get_option('print_errors'):
            return
        self.error(line, args)


# vim: tw=79

