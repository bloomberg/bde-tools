"""Configure the available compilers.
"""

from __future__ import print_function

import json
import re
import os
import sys

from bdebuild.common import blderror
from bdebuild.common import mixins

from bdebuild.meta import optiontypes
from bdebuild.meta import optionsutil


class CompilerInfo(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    """Information pertaining to a compiler.

    Attributes:
        type_ (str): Type of the compiler.
        version (str): Version number of the compiler.
        c_path (str): Path to the C compiler executable.
        cxx_path (str): Path to the C++ compiler executable.
        toolchain (str): Path to the cmake toolchain file.
        flags (str, optional): Arguments to pass to the compiler.
        desc (str, optional): Custom description, by default, the description()
            method returns type_ + '-' + version.
    """
    def __init__(self, type_, version, c_path, cxx_path, toolchain=None,
                 flags=None, desc=None):
        self.type_ = type_
        self.version = version
        self.c_path = c_path
        self.cxx_path = cxx_path
        self.toolchain = toolchain
        self.flags = flags
        self.desc = desc

    def key(self):
        return self.type_ + '-' + self.version

    def description(self):
        if self.desc:
            return self.desc
        else:
            return self.key()


def get_config_path():
    """Return the path to the compiler configuration file.

    This is either ~/.bdecompilerconfig if it exists, or
    $BDE_ROOT/bdecompilerconfig.

    Returns:
       Path to the config file.

    Raises:
       MissingFileError if no valid configuration file is found.
    """
    localconfig_path = os.path.join(os.path.expanduser('~'),
                                    '.bdecompilerconfig')

    path = None

    if (os.path.isfile(localconfig_path) and
            os.access(localconfig_path, os.R_OK)):
        path = localconfig_path
    bde_root = os.environ.get('BDE_ROOT')

    if not path and bde_root:
        defaultconfig_path = os.path.join(bde_root,
                                          'etc', 'bdecompilerconfig')
        if (os.path.isfile(defaultconfig_path) and
                os.access(defaultconfig_path, os.R_OK)):
            path = defaultconfig_path

    if not path:
        raise blderror.MissingFileError(
            'Cannot find a compiler configuration file at %s '
            'or $BDE_ROOT/etc/bdecompilerconfig (BDE_ROOT is %s)' %
            (localconfig_path, bde_root))

    if path:
        print('Using configuration: %s' % path, file=sys.stderr)
        return path


def get_compilerinfos(hostname, uplid, file_):
    """Get the list of applicable compilers from a compiler config file.

    Args:
        hostname (str): Hostname of the machine to be matched.
        uplid (str): UPLID of the machine to be matched.
        file_ (File): The compiler configuration file.

    Returns:
        list of matched CompilerInfo objects.
    """

    loaded_value = json.load(file_)
    matched_obj = None
    for obj in loaded_value:
        if 'hostname' in obj:
            m = re.match(obj['hostname'], hostname)
            if not m:
                continue

        uplid_mask = optiontypes.Uplid.from_str(obj['uplid'])
        if not optionsutil.match_uplid(uplid, uplid_mask):
            continue

        matched_obj = obj
        break

    if not matched_obj:
        return None

    infos = []

    for compiler in matched_obj['compilers']:
        type_ = compiler['type']
        version = compiler['version']
        c_path = compiler['c_path']
        cxx_path = compiler['cxx_path']
        if 'toolchain' in compiler:
            toolchain = compiler['toolchain']
        else:
            toolchain = None

        if 'flags' in compiler:
            flags = compiler['flags']
        else:
            flags = None
        info = CompilerInfo(type_, version, c_path, cxx_path, toolchain, flags)
        infos.append(info)

    return infos


# -----------------------------------------------------------------------------
# Copyright 2018 Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------- END-OF-FILE -----------------------------------
