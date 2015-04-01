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

# File: result.py
# Author: Geoffrey Biggs
# Part of pykg-config.

"""Object that stores the result of a search for one or more packages
and can return specific options from them, such as cflags, libs, etc.
Will search recursively to find all required packages.

"""

__version__ = "$Revision: $"
# $Source$

import sys

from pykg_config.pkgsearcher import PkgSearcher
from pykg_config.errorprinter import ErrorPrinter
from pykg_config.exceptions import PykgConfigError
from pykg_config.packagespeclist import parse_package_spec_list
from pykg_config.options import Options

##############################################################################
# Exceptions

class PackageConflictError(PykgConfigError):
    """A package listed in a conflict list was found.

    Attributes:
        pkgname -- The name of the package with the conflict.
        conflict -- The package causing the conflict.

    """
    def __init__(self, pkgname, conflict):
        self.pkgname = pkgname
        self.conflict = conflict

    def __str__(self):
        return '{0} conflicts with {1}'.format(self.pkgname, self.conflict)


class NoPackagesSpecifiedError(PykgConfigError):
    """No packages were specified in a list of packages to search for."""
    pass

##############################################################################
# Private utility functions

def _filter_duplicates(source):
    # This maintains the order.
    ret = []
    seen = { }
    for it in reversed(source):
         if it not in seen:
              ret.append(it)
              seen[it] = 1
    ret.reverse()
    return ret

##############################################################################
# PkgCfgResult object

class PkgCfgResult:
    def __init__(self, globals):
        # Different platforms may use different flags and extensions
        if sys.platform == 'win32' and Options().get_option('use_msvc_syntax'):
            self.lib_path_flag = '/libpath:'
            self.lib_flag = ''
        else:
            self.lib_path_flag = '-L'
            self.lib_flag = '-l'
        # Can't use a dictionary for the loaded packages list because the
        # ordering must be maintained (when Python 3.1 is standard, switch to
        # collections.OrderedDict).
        self.packages = []
        self.searched_packages = []
        self.searcher = PkgSearcher()
        self.globals = globals

    def __str__(self):
        packages = ['%s-%s' % (pkg[0], pkg[1].properties['version']) \
                    for pkg in self.packages]
        return str(packages)

    def find_packages(self, pkglist, recurse):
        """Find all packages specified in pkglist, which must be a
        textual list of package specifications in the form
        'package operator version' (where operator is a comparison
        operator such as <= or ==).

        """
        self.searched_packages = parse_package_spec_list(pkglist)
        if not self.searched_packages:
            raise NoPackagesSpecifiedError
        self._load_dependencies(self.searched_packages, recurse)

    def dump_package(self):
        for pkg in self.searched_packages:
            print(self._get_loaded_package(pkg.name))

    def get_big_i_flags(self):
        result = []
        for name, pkg in self.packages:
            result += ['-I' + dir for dir in pkg.properties['include_dirs']]
        return self._format_list(_filter_duplicates(result))

    def get_other_i_flags(self):
        result = []
        for name, pkg in self.packages:
            result += pkg.properties['other_cflags']
        return self._format_list(_filter_duplicates(result))

    def get_cflags(self):
        result = []
        for name, pkg in self.packages:
            result += pkg.properties['other_cflags']
            result += ['-I' + dir for dir in pkg.properties['include_dirs']]
        return self._format_list(_filter_duplicates(result))

    def get_l_flags(self):
        result = []
        for name, pkg in self.packages:
            result += [self.lib_flag + lib for lib in pkg.properties['libs']]
            if Options().get_option('private_libs'):
                result += [self.lib_flag + lib \
                                for lib in pkg.properties['private.libs']]
        return self._format_list(_filter_duplicates(result))

    def get_big_l_flags(self):
        result = []
        for name, pkg in self.packages:
            result += [self.lib_path_flag + path \
                        for path in pkg.properties['libpaths']]
            if Options().get_option('private_libs'):
                result += [self.lib_path_flag + path \
                                for path in pkg.properties['private.libpaths']]
        return self._format_list(_filter_duplicates(result))

    def get_other_l_flags(self):
        result = []
        for name, pkg in self.packages:
            result += pkg.properties['otherlibs']
            if Options().get_option('private_libs'):
                result += pkg.properties['private.otherlibs']
        return self._format_list(_filter_duplicates(result))

    def get_all_lib_flags(self):
        result = []
        for name, pkg in self.packages:
            result += pkg.properties['otherlibs']
            if Options().get_option('private_libs'):
                result += pkg.properties['private.otherlibs']
            result += [self.lib_path_flag + path \
                        for path in pkg.properties['libpaths']]
            if Options().get_option('private_libs'):
                result += [self.lib_path_flag + path \
                                for path in pkg.properties['private.libpaths']]
            result += [self.lib_flag + lib for lib in pkg.properties['libs']]
            if Options().get_option('private_libs'):
                result += [self.lib_flag + lib \
                                for lib in pkg.properties['private.libs']]
        return self._format_list(_filter_duplicates(result))

    def get_variable_value(self, variable):
        """Find a variable definition in the list of packages, going through
        the list of packages in the command line order first before trying
        dependencies."""
        for pkg in self.searched_packages:
            loaded_pkg = self._get_loaded_package(pkg.name)
            if loaded_pkg.variables.has_key(variable):
                return loaded_pkg.variables[variable]
        # Not in the searched-for packages, so try the dependencies
        for name, pkg in self.packages:
            if pkg.variables.has_key(variable):
                return pkg.variables[variable]
        return None

    def known_packages_list(self):
        """Get a list of all the packages found on the system."""
        return self.searcher.known_packages_list()

    def have_uninstalled(self):
        for name, pkg in self.packages:
            if pkg.uninstalled:
                return True
        return False

    def get_package_version(self, name):
        pkg = self._get_loaded_package(name)
        if pkg:
            return pkg.properties['version']
        return None

    def get_searched_pkgs_versions(self):
        result = []
        for pkg in self.searched_packages:
            loaded_pkg = self._get_loaded_package(pkg.name)
            result.append(loaded_pkg.properties['version'])
        return result

    def get_searched_pkg_list(self):
        return self.searched_packages

    def _format_list(self, result_list):
        result = ''
        for item in ['{0} '.format(x) for x in result_list]:
            result += item
        return result[:-1] # Strip the last space

    def _load_dependencies(self, dependencies, recurse):
        # Search for and load all packages listed in dependencies,
        # attempting to recursively load all their required packages
        # and checking for conflicts as well.
        # For d in deps:
        for dep in dependencies:
        # 0. Check if this package is already loaded
            if self._get_loaded_package(dep.name):
                continue
        # 1. Search for a package matching the spec
            pkg = self.searcher.search_for_package(dep, self.globals)
        # 2. Check for conflicts
            for conflict in pkg.properties['conflicts']:
                try:
                    ErrorPrinter().debug_print('Searching for conflict %s',
                                               conflict.name)
                    self.searcher.search_for_package(conflict)
                except PackageNotFoundError:
                    # If the conflict was not found, move on to the next
                    ErrorPrinter().debug_print('Conflict not found.')
                    continue
                # Conflict was found - what to do?
                raise PackageConflictError(pkg.name, conflict)
        # 3. Sanity check this package
            pkg.sanity_check()
        # 4. Add this package to the dictionary now to avoid infinite recursion
            self._add_package(dep.name, pkg)
        # 5. Recursively load requireds
            if recurse:
                # requires.private includes requires
                self._load_dependencies(pkg.properties['requires.private'], recurse)

    def _add_package(self, name, newpkg):
        ErrorPrinter().debug_print('Adding %s to list of packages as %s',
                                   (newpkg.filename, name))
        self.packages.append((name, newpkg))

    def _get_loaded_package(self, name):
        for pkg in self.packages:
            if pkg[0] == name:
                return pkg[1]
        return None


# vim: tw=79

