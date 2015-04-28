"""Miscellaneous utilities
"""

import os
import platform
import re
import subprocess
import sys

from bdebuild.common import blderror


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
    """Return the path to a executable file on the PATH.
    """
    def is_exe(fpath):
        return os.path.isfile(fpath) and os.access(fpath, os.X_OK)

    for path in os.environ["PATH"].split(os.pathsep):
        path = path.strip('"')
        exe_file = os.path.join(path, program)
        if is_exe(exe_file):
            return path

    return None


def is_int_string(str_):
    """Is a string a representation of a integer value.
    """
    try:
        int(str_)
        return True
    except ValueError:
        return False


def is_64bit_system():
    """Return whether the system is 64-bit capable.

    We approximate the return value by first checking whether we are
    running the 64-bit python interpreter.  If so, then we are done.
    Otherwise, we match the current machine type with a set of known 64-bit
    machine types.
    """

    if sys.maxsize > 2**32:
        return True

    return platform.machine().lower()  \
        in ('amd64', 'x86_64', 'sun4v', 'ppc64')


def repo_root_path():
    """Return the root path of this tools repository.
    """
    upd = os.path.dirname
    tools_repo_root = upd(upd(upd(upd(upd(os.path.realpath(__file__))))))
    return tools_repo_root


def unversioned_platform():
    """Return the unversioned platform string.

    Possible return values:
        linux, aix, sunos, darwin, win32, cygwin
    """
    s = sys.platform

    if s == 'powerpc':
        return 'darwin'

    if s == 'win32' or s == 'os2':
        return s

    return re.split('\d+$', s)[0]


def is_mingw_environment():
    """Return whether the current platform is win32 mingw.

    Note that mingw returns "win32" as the platform in other context (e.g.
    'unversioned_platform')
    """
    try:
        uname = subprocess.check_output('uname')
    except Exception:
        return False

    return -1 != uname.find('MINGW')


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


def get_win32_os_info_from_cygwin():
    """Get operating system information for windows from cygwin.
    """

    platform_str = unversioned_platform()
    if platform_str != 'cygwin':
        raise blderror.UnsupportedPlatformError(
            'Function can only be called in a cygwin environment.')

    os_type = 'windows'
    os_name = 'windows_nt'
    out = shell_command('echo $(cmd /c ver)')

    m = re.match(r'\s*Microsoft\s+Windows\s+\[Version\s+(\d+\.\d+)[^\]]+\]',
                 out)
    if not m:
        raise blderror.UnsupportedPlatformError(
            'Invalid Windows version string "%s".' % out)
    os_ver = m.group(1)

    # Make the assumption that we are on a X86 system.
    if is_64bit_system():
        cpu_type = 'amd64'
    else:
        cpu_type = 'x86'

    return os_type, os_name, cpu_type, os_ver


def get_os_info():
    """Return the operating system information part of the UPLID.

    Returns:
        os_type, os_name, cpu_type, os_ver
    """

    def get_linux_os_info():
        os_type = 'unix'
        os_name = 'linux'
        uname = os.uname()
        cpu_type = uname[4]
        os_ver = uname[2]
        # os_ver can contain a '-flavor' part, strip it
        os_ver = os_ver.split('-', 1)[0]

        return os_type, os_name, cpu_type, os_ver

    def get_aix_os_info():
        os_type = 'unix'
        os_name = 'aix'
        cpu_type = shell_command(['/bin/uname', '-p']).rstrip()
        uname = os.uname()
        os_ver = '%s.%s' % (uname[3], uname[2])

        return os_type, os_name, cpu_type, os_ver

    def get_sunos_os_info():
        os_type = 'unix'
        os_name = 'sunos'
        cpu_type = shell_command(['/bin/uname', '-p']).rstrip()
        uname = os.uname()
        os_ver = uname[2]

        return os_type, os_name, cpu_type, os_ver

    def get_darwin_os_info():
        os_type = 'unix'
        os_name = 'darwin'
        uname = os.uname()
        cpu_type = uname[4]
        os_ver = uname[2]
        # os_ver can contain a '-flavor' part, strip it
        os_ver = os_ver.split('-', 1)[0]

        return os_type, os_name, cpu_type, os_ver

    def get_windows_os_info():
        os_type = 'windows'
        os_name = 'windows_nt'
        import platform
        uname = platform.uname()
        os_ver = '.'.join(uname[3].split('.')[0:2])

        # Make the assumption that we are on a X86 system.
        if is_64bit_system():
            cpu_type = 'amd64'
        else:
            cpu_type = 'x86'

        return os_type, os_name, cpu_type, os_ver

    platform_str = unversioned_platform()
    os_info_getters = {
        'linux': get_linux_os_info,
        'aix': get_aix_os_info,
        'sunos': get_sunos_os_info,
        'darwin': get_darwin_os_info,
        'win32': get_windows_os_info
        }

    if platform_str not in os_info_getters:
        raise blderror.UnsupportedPlatformError(
            'Unsupported platform %s' % platform_str)

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
