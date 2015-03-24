"""Miscellaneous utilities
"""

import os
import re
import subprocess
import sys


def shell_command(cmd):
    """Execute and return the output of a shell command.
    """
    kw = {}
    kw['shell'] = isinstance(cmd, str)
    kw['stdout'] = kw['stderr'] = subprocess.PIPE
    (out, err) = subprocess.Popen(cmd, **kw).communicate()
    if not isinstance(out, str):
        out = out.decode(sys.stdout.encoding or 'iso8859-1')
    return out


def find_program(program):
    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    for path in os.environ["PATH"].split(os.pathsep):
        path = path.strip('"')
        exe_file = os.path.join(path, program)
        if is_exe(exe_file):
            return path

    return None


def unversioned_platform():
    """Return the unversioned platform string.

    Possible return values:
        linux, aix, sunos, darwin, win32
    """
    s = sys.platform

    if s == 'powerpc':
        return 'darwin'

    if s == 'win32' or s == 'os2':
        return s

    return re.split('\d+$', s)[0]


class CompilerType:
    C = 0,
    CXX = 1


CXX_C_COMP_MAP = {
    'g++': 'gcc',
    'clang++': 'clang',
    'CC': 'cc',
    'xlC_r': 'xlc_r'
}

C_CXX_COMP_MAP = {}
for k, v in CXX_C_COMP_MAP.items():
    C_CXX_COMP_MAP[v] = k

COMP_VER_RE = re.compile(r'^([^-]+)(-\d+(\.\d+)?(\.\d+)?)?$')


def get_other_compiler(comp_path, comp_type):
    """Return the matching compiler of a particular compiler path.

    The matching compiler of a C compiler is its corresponding C++ compiler and
    vise versa.

    Args:
        comp_path (str): Path to the compiler.
        comp_type (CompilerType): Type of the compiler.

    Returns:
        The path of the matching compiler.
    """
    (dirname, basename) = os.path.split(comp_path)

    m = COMP_VER_RE.match(basename)
    if not m:
        return None

    name = m.group(1)
    tail = m.group(2) if m.group(2) else ''
    comp_map = CXX_C_COMP_MAP if comp_type == CompilerType.CXX else \
        C_CXX_COMP_MAP

    if name not in comp_map:
        return None

    return os.path.join(dirname, comp_map[name] + tail)


def get_os_info():
    """Return the operating system information part of the UPLID.

    Returns:
        os_type, os_name, os_ver
    """

    def get_linux_os_info():
        os_type = 'unix'
        os_name = 'linux'
        os_ver = os.uname()[2]
        # os_ver can contain a '-flavor' part, strip it
        os_ver = os_ver.split('-', 1)[0]

        return os_type, os_name, os_ver

    def get_aix_os_info():
        os_type = 'unix'
        os_name = 'aix'
        uname = os.uname()
        os_ver = '%s.%s' % (uname[3], uname[2])

        return os_type, os_name, os_ver

    def get_sunos_os_info():
        os_type = 'unix'
        os_name = 'sunos'
        uname = os.uname()
        os_ver = uname[2]

        return os_type, os_name, os_ver

    def get_darwin_os_info():
        os_type = 'unix'
        os_name = 'darwin'
        os_ver = os.uname()[2]
        # os_ver can contain a '-flavor' part, strip it
        os_ver = os_ver.split('-', 1)[0]

        return os_type, os_name, os_ver

    def get_windows_os_info():
        os_type = 'windows'
        os_name = 'windows_nt'
        import platform
        uname = platform.uname()
        os_ver = '.'.join(uname[3].split('.')[0:2])

        return os_type, os_name, os_ver

    platform_str = unversioned_platform()
    os_info_getters = {
        'linux': get_linux_os_info,
        'aix': get_aix_os_info,
        'sunos': get_sunos_os_info,
        'darwin': get_darwin_os_info,
        'win32': get_windows_os_info
        }

    if platform_str not in os_info_getters:
        raise ValueError('Unsupported platform %s' % platform_str)

    return os_info_getters[platform_str]()

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
