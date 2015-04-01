#!/usr/bin/env python

# Copyright (c) 2009, Geoffrey Biggs
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

# File: pykg-config.py
# Author: Geoffrey Biggs
# Part of pykg-config.

__version__ = "$Revision: $"
# $Source$

from optparse import OptionParser, OptionError
from os import getenv
import sys
import traceback

from pykg_config.errorprinter import ErrorPrinter
from pykg_config.result import PkgCfgResult, NoPackagesSpecifiedError
from pykg_config.options import Options
from pykg_config.version import Version
from pykg_config.pkgsearcher import PackageNotFoundError, NoOpenableFilesError
from pykg_config.substitute import UndefinedVarError

PYKG_CONFIG_VERSION = '1.1.0'
CORRESPONDING_VERSION = '0.26'

def setup_option_parser():
    # Creates an OptionParser instance with all the options needed.
    usage = 'Usage: %prog [options] package_spec_list\n\
Return metainformation about installed libraries.'
    version = CORRESPONDING_VERSION
    parser = OptionParser(usage = usage, version = version)
    parser.add_option('--realversion', dest='realversion',
                      action='store_true', default=False,
                      help='Get the pykg-config version. [Default: %default]')
    parser.add_option('--modversion', dest='modversion', action='store_true',
                      default=False, help='Output version for package')
    parser.add_option('--atleast-pkgconfig-version',
                      dest='atleast_pkgconfig_version', type='string',
                      action='store', default='',
                      help='Require given version of pkg-config')
    parser.add_option('--libs', dest='libs', action='store_true', default=False,
                      help='Output all linker flags')
    parser.add_option('--static', dest='static', action='store_true',
                      default=False,
                      help='Output linker flags for static linking')
    parser.add_option('--short-errors', dest='short_errors',
                      action='store_true', default=False,
                      help='Print short errors')
    parser.add_option('--libs-only-l', dest='libs_only_l', action='store_true',
                      default=False, help='Output -l flags')
    parser.add_option('--libs-only-other', dest='libs_only_other',
                      action='store_true', default=False,
                      help='Output other libs (e.g. -pthread)')
    parser.add_option('--libs-only-L', dest='libs_only_big_l',
                      action='store_true', default=False,
                      help='Output -L flags')
    parser.add_option('--cflags', dest='cflags', action='store_true',
                      default=False,
                      help='Output all pre-processor and compiler flags')
    parser.add_option('--cflags-only-I', dest='cflags_only_big_i',
                      action='store_true', default=False,
                      help='Output -I flags'),
    parser.add_option('--cflags-only-other', dest='cflags_only_other',
                      action='store_true', default=False,
                      help='Output cflags not covered by --cflags-only-I')
    parser.add_option('--variable', dest='variable', type='string',
                      action='store', default=False,
                      help='Get the value of a variable'),
    parser.add_option('--define-variable', dest='define_variable',
                      type='string', action='append',
                      help='Set the value of a variable'),
    parser.add_option('--exists', dest='exists', action='store_true',
                      default=False, help='Return 0 if the module(s) exist')
    parser.add_option('--uninstalled', dest='uninstalled', action='store_true',
                      default=False,
                      help='Return 0 if the uninstalled version of one or more \
modules or their dependencies will be used')
    parser.add_option('--atleast-version', dest='atleast_version',
                      type='string', action='store', default=False,
                      help='Return 0 if the module is at least the given \
version')
    parser.add_option('--exact-version', dest='exact_version', type='string',
                      action='store', default=False,
                      help='Return 0 if the module is exactly the given \
version')
    parser.add_option('--max-version', dest='max_version', type='string',
                      action='store', default=False,
                      help='Return 0 if the module is no newer than the given \
version')
    parser.add_option('--list-all', dest='list_all', action='store_true',
                      default=False, help='List all known packages')
    parser.add_option('--debug', dest='debug', action='store_true',
                      default=False, help='Show verbose debug information')
    parser.add_option('--print-errors', dest='print_errors',
                      action='store_true', default=False,
                      help='Show verbose information about missing or \
conflicting packages')
    parser.add_option('--silence-errors', dest='silence_errors',
                      action='store_true', default=False,
                      help="Don't show verbose information about missing or \
conflicting packages")
    parser.add_option('--errors-to-stdout', dest='errors_to_stdout',
                      action='store_true', default=False,
                      help='Print errors from --print-errors to stdout')
    parser.add_option('--dump-package', dest='dump_package',
                      action='store_true', default=False,
                      help='Print the parsed package information and exit.')
    parser.add_option('--normalise-paths', dest='normalise_paths',
                      action='store_true', default=False,
                      help="Normalise paths to use the correct slash for \
your platform. [Default: %default]")
    if sys.platform == 'win32':
        parser.add_option('--dont-define-prefix', dest='dont_define_prefix',
                          action='store_true', default=False,
                          help="Don't try to override the value of prefix for \
each .pc file found with a guestimated value based on the location of the .pc \
file.")
        parser.add_option('--prefix-variable', dest='prefix_variable',
                          type='string', action='store', default='prefix',
                          help='Set the name of the variable that pkg-config \
automatically sets when defining the prefix.')
        parser.add_option('--msvc-syntax', dest='msvc_syntax',
                          action='store_true', default=False,
                          help='Output linker flags in the Microsoft compiler \
(cl) format')
        parser.add_option('--no-msvc-syntax', dest='msvc_syntax',
                          action='store_false',
                          help='Do not output linker flags in the Microsoft \
compiler (cl) format')

    # Options that change default depending on platform
    if sys.platform == 'win32':
        full_compatibility = False
    else:
        full_compatibility = True
    parser.add_option('--full-compatibility', dest='full_compatibility',
                      default=full_compatibility, action='store_true',
                      help='Enable full-compatibility mode. \
[Default: %default]')
    parser.add_option('--less-compatibility', dest='full_compatibility',
                      action='store_false',
                      help='Disable full-compatibility mode. \
[Default: %default]')

    return parser


def main(argv):
    parser = setup_option_parser()
    try:
        options, args = parser.parse_args()
    except OptionError as e:
        print('OptionError: ' + str (e))
        sys.exit(1)

    if options.realversion:
        print('{0} (Equivalent to {1}'.format(PYKG_CONFIG_VERSION,
                                              CORRESPONDING_VERSION))
        sys.exit(0)

    global_variables = {}

    zip_name = 'python{0}{1}.zip'.format(sys.version_info[0],
                                          sys.version_info[1])
    for path in sys.path:
        if path.endswith('64/' + zip_name):
            Options().set_option('is_64bit', True)
            break

    if getenv('PKG_CONFIG_SYSROOT_DIR'):
        global_variables['pc_sysrootdir'] = getenv('PKG_CONFIG_SYSROOT_DIR')
    if getenv('PKG_CONFIG_TOP_BUILD_DIR'):
        global_variables['pc_topbuilddir'] = getenv('PKG_CONFIG_TOP_BUILD_DIR')
    if getenv('PKG_CONFIG_DISABLE_UNINSTALLED'):
        Options().set_option('prefer_uninstalled', False)
    if getenv('PKG_CONFIG_ALLOW_SYSTEM_LIBS'):
        Options().set_option('forbidden_libdirs', [])
    else:
        if Options().get_option('is_64bit'):
            Options().set_option('forbidden_libdirs', ['/usr/lib64'])
        else:
            Options().set_option('forbidden_libdirs', ['/usr/lib'])
    if getenv('PKG_CONFIG_ALLOW_SYSTEM_CFLAGS'):
        Options().set_option('forbidden_cflags', [])
    else:
        forbidden = []
        if sys.platform != 'win32':
            forbidden.append('/usr/include')
        if getenv('C_INCLUDE_PATH'):
            forbidden.append(getenv('C_INCLUDE_PATH'))
        if getenv('CPLUS_INCLUDE_PATH'):
            forbidden.append(getenv('CPLUS_INCLUDE_PATH'))
        Options().set_option('forbidden_cflags', forbidden)

    if options.full_compatibility:
        Options().set_option('full_compatibility', True)
    else:
        Options().set_option('full_compatibility', False)

    if options.atleast_pkgconfig_version:
        other_version = Version(options.atleast_pkgconfig_version)
        if other_version > get_pkg_config_version():
            sys.exit(1)
        else:
            sys.exit(0)
    if options.static:
        Options().set_option('private_libs', True)
    if options.short_errors:
        Options().set_option('short_errors', True)
    if options.define_variable:
        for var_def in options.define_variable:
            sub_strings = var_def.split('=')
            if len(sub_strings) != 2:
                print('Bad argument format for define-variable: {1}'.format(var_def))
                sys.exit(1)
            global_variables[sub_strings[0]] = sub_strings[1]
    if options.debug:
        Options().set_option('debug', True)
    if options.errors_to_stdout:
        Options().set_option('error_dest', sys.stdout)
    if sys.platform == 'win32':
        if options.dont_define_prefix:
            Options().set_option('dont_define_prefix', True)
        else:
            Options().set_option('dont_define_prefix', False)
        if options.prefix_variable:
            Options().set_option('prefix_variable', options.prefix_variable)
        if options.msvc_syntax:
            Options().set_option('use_msvc_syntax', True)
        else:
            Options().set_option('use_msvc_syntax', False)
    if options.normalise_paths:
        Options().set_option('normalise_paths', True)
    else:
        Options().set_option('normalise_paths', False)

    if options.modversion or options.libs or options.libs_only_l or \
            options.libs_only_big_l or options.libs_only_other or \
            options.cflags or options.cflags_only_big_i or \
            options.cflags_only_other or options.list_all:
        if options.silence_errors:
            Options().set_option('print_errors', False)
        else:
            Options().set_option('print_errors', True)
    else:
        if options.print_errors:
            Options().set_option('print_errors', True)
        else:
            Options().set_option('print_errors', False)

    if options.list_all:
        Options().set_option('command', 'list-all')
        try:
            result = PkgCfgResult(global_variables)
            all_packages, errors = result.known_packages_list()
        except:
            ErrorPrinter().error('Exception searching for packages:')
            traceback.print_exc()
            sys.exit(1)
        if all_packages:
            max_width = max([(len(p), p) for p, n, d in all_packages])
            for package, name, description in all_packages:
                print('{0:{3}}{1} - {2}'.format(package, name, description, max_width[0] + 1))
        for e in errors:
            ErrorPrinter().error(e)
        sys.exit(0)

    try:
        Options().set_option('command', 'search')
        search = ' '.join(args)
        Options().set_option('search_string', search)
        result = PkgCfgResult(global_variables)
        result.find_packages(search, True)
    except NoOpenableFilesError as e:
        ErrorPrinter().verbose_error(str(e))
        sys.exit(1)
    except PackageNotFoundError as e:
        if not Options().get_option('short_errors'):
            ErrorPrinter().verbose_error('''Package {0} was not found in the \
pkg-config search path.
Perhaps you should add the directory containing `{0}.pc'
to the PKG_CONFIG_PATH environment variable'''.format(e.pkgname))
        ErrorPrinter().verbose_error(str(e))
        sys.exit(1)
    except NoPackagesSpecifiedError:
        Options().get_option('error_dest').write(
            'Must specify package names on the command line\n')
        sys.exit(1)
    except UndefinedVarError as e:
        ErrorPrinter().error("Variable '{0}' not defined in '{1}'".format(
            e.variable, e.pkgfile))
        sys.exit(1)
    except:
        print('Exception searching for packages')
        traceback.print_exc()
        sys.exit(1)

    if options.dump_package:
        result.dump_package()
        sys.exit(0)

    if options.exists:
        # Even if the packages don't meet the requirements, they exist, which
        # is good enough for the exists option.
        sys.exit(0)
    if options.uninstalled:
        # Check if any packages loaded (both searched-for and dependencies)
        # are uninstalled.
        if result.have_uninstalled():
            sys.exit(0)
        sys.exit(1)

    if options.modversion:
        for l in result.get_searched_pkgs_versions():
            print(l)
    found_version = \
        result.get_package_version(result.get_searched_pkg_list()[0].name)
    if options.atleast_version:
        if found_version < Version(options.atleast_version):
            sys.exit(1)
        sys.exit(0)
    if options.exact_version:
        if found_version != Version(options.exact_version):
            sys.exit(1)
        sys.exit(0)
    if options.max_version:
        if found_version > Version(options.max_version):
            sys.exit(1)
        sys.exit(0)

    if options.variable:
        value = result.get_variable_value(options.variable)
        if value == None:
            print('')
        else:
            print(value)
    if options.cflags_only_big_i:
        print(result.get_big_i_flags())
    if options.cflags_only_other:
        print(result.get_other_i_flags())
    if options.cflags:
        print(result.get_cflags())
    if options.libs_only_l:
        print(result.get_l_flags())
    if options.libs_only_big_l:
        print(result.get_big_l_flags())
    if options.libs_only_other:
        print(result.get_other_l_flags())
    if options.libs:
        print(result.get_all_lib_flags())


def get_pkg_config_version():
    return Version(CORRESPONDING_VERSION)


if __name__ == '__main__':
    main(sys.argv)

# vim: tw=79

