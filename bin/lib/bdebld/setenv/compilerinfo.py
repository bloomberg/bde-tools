import json
import re
import os

from bdebld.common import mixins
from bdebld.common import logutil

from bdebld.meta import optiontypes
from bdebld.meta import optionsutil


class CompilerInfo(mixins.BasicEqualityMixin, mixins.BasicReprMixin):
    def __init__(self, type_, version, c_path, cxx_path, flags=None,
                 desc=None):
        self.type_ = type_
        self.version = version
        self.c_path = c_path
        self.cxx_path = cxx_path
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
    localconfig_path = os.path.join(os.path.expanduser('~'),
                                    '.bdecompilerconfig')

    path = None

    if (os.path.isfile(localconfig_path) and
            os.access(localconfig_path, os.R_OK)):
        path = localconfig_path
    bde_root = os.environ.get('BDE_ROOT')

    if bde_root:
        defaultconfig_path = os.path.join(bde_root,
                                          'etc', 'bdecompilerconfig')
        if (os.path.isfile(defaultconfig_path) and
                os.access(defaultconfig_path, os.R_OK)):
            path = defaultconfig_path

    if path:
        logutil.warn('using configuration: %s' % path)
        return path

    raise ValueError('Cannot find a compiler configuration file at %s '
                     'or $BDE_ROOT/etc/bdecompilerconfig' % localconfig_path)


def get_compilerinfos(hostname, uplid, file_):
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
        if 'flags' in compiler:
            flags = compiler['flags']
        else:
            flags = None
        info = CompilerInfo(type_, version, c_path, cxx_path, flags)
        infos.append(info)

    return infos


# -----------------------------------------------------------------------------
# Copyright 2015 Bloomberg Finance L.P.
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
