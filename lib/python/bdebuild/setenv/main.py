from __future__ import print_function

import platform
import re
import sys
import os

from bdebuild.common import blderror
from bdebuild.common import sysutil
from bdebuild.common import msvcversions
from bdebuild.meta import optionsutil
from bdebuild.meta import optiontypes
from bdebuild.setenv import compilerinfo
from bdebuild.setenv import cmdline


def main():
    try:
        program()
    except blderror.BldError as e:
        print(e, file=sys.stderr)
        sys.exit(1)
    except IOError as e:
        print(e, file=sys.stderr)
        sys.exit(1)


def program():
    platform_str = sysutil.unversioned_platform()

    if platform_str not in ('win32', 'cygwin', 'linux', 'aix', 'sunos',
                            'darwin'):
        print('Unsupported platform: %s' % platform_str, file=sys.stderr)
        sys.exit(1)

    if platform_str == 'win32' and not sysutil.is_mingw_environment():
        print('This tool is used to configure unix-style environment '
              'variables. On Windows platforms it must be run from a unix '
              'shell environment, either cygwin, or mingw/msys/msysgit')
        sys.exit(1)

    parser = cmdline.get_option_parser()

    options, args = parser.parse_args()

    if len(args) > 1:
        parser.print_help()
        sys.exit(1)

    if len(args) == 0:
        command = 'set'
    else:
        command = args[0]

    if command not in ('set', 'unset', 'list'):
        print('Invalid command: %s' % command, file=sys.stderr)
        parser.print_help()
        sys.exit(1)

    if command == 'unset':
        unset_command()
        sys.exit(0)

    compiler_infos = get_compilerinfos()

    if not compiler_infos:
        print('No valid compilers on this machine.', file=sys.stderr)
        sys.exit(1)

    if command == 'list':
        list_compilers(compiler_infos)
        sys.exit(0)

    # command == 'set'
    info = None
    if options.compiler is None:
        info = compiler_infos[0]
    elif sysutil.is_int_string(options.compiler):
        idx = int(options.compiler)
        if idx < len(compiler_infos):
            info = compiler_infos[idx]
    else:

        for c in compiler_infos:
            if c.key() == options.compiler:
                info = c

    if not info:
        print("Invalid compiler: %s" % options.compiler, file=sys.stderr)
        list_compilers(compiler_infos)
        sys.exit(1)

    print_envs(options, info)


def unset_command():
    print('unset CXX')
    print('unset BDE_WAF_UPLID')
    print('unset BDE_WAF_UFID')
    print('unset BDE_WAF_BUILD_DIR')
    print('unset WAFLOCK')
    print('unset PREFIX')
    print('unset BDE_WAF_COMP_FLAGS')
    print('unset PKG_CONFIG_PATH')


def get_compilerinfos():
    os_type, os_name, cpu_type, os_ver = get_os_info()
    if os_type != 'windows':
        uplid = optiontypes.Uplid(os_type, os_name, cpu_type, os_ver)
        compilerconfig_path = compilerinfo.get_config_path()

        with open(compilerconfig_path, 'r') as f:
            compiler_infos = compilerinfo.get_compilerinfos(platform.node(),
                                                            uplid, f)
        return compiler_infos
    else:
        compiler_infos = []
        for v in msvcversions.versions:
            info = compilerinfo.CompilerInfo(
                'cl', v.compiler_version, None, None, None,
                'cl-%s -- %s (Version %s)' %
                (v.compiler_version, v.product_name, v.product_version))
            compiler_infos.append(info)

        return compiler_infos


def get_os_info():
    platform_str = sysutil.unversioned_platform()
    if platform_str == 'cygwin':
        return sysutil.get_win32_os_info_from_cygwin()
    else:
        return sysutil.get_os_info()


def print_envs(options, info):
    ufid = optionsutil.make_ufid_from_cmdline_options(options)
    os_type, os_name, cpu_type, os_ver = get_os_info()

    uplid = optiontypes.Uplid(os_type, os_name, cpu_type, os_ver,
                              info.type_, info.version)

    print('Using compiler: %s' % info.description(), file=sys.stderr)
    print('Using ufid: %s' % ufid, file=sys.stderr)

    print('export BDE_WAF_UPLID=%s' % uplid)
    print('export BDE_WAF_UFID=%s' % ufid)
    id_str = '%s-%s' % (uplid, ufid)
    print('export BDE_WAF_BUILD_DIR="_build/%s"' % id_str)
    print('export WAFLOCK=".lock-waf-%s"' % id_str)

    if os_type != 'windows':
        print('export CXX=%s' % info.cxx_path)
        print('export CC=%s' % info.c_path)

    if info.flags:
        print('export BDE_WAF_COMP_FLAGS="%s"' % info.flags)
    else:
        print('unset BDE_WAF_COMP_FLAGS')

    if options.install_dir:
        install_dir = options.install_dir
    else:
        install_dir = _determine_installation_location(
            os.environ.get('PREFIX'), uplid)

    if install_dir:
        print('Using install directory: %s' % install_dir, file=sys.stderr)
        PREFIX = os.path.join(install_dir, id_str)
        if sysutil.unversioned_platform() == 'cygwin':
            PREFIX = sysutil.shell_command('cygpath -m "%s"' % PREFIX).rstrip()

        print('export PREFIX="%s"' % PREFIX)
        pkg_path = '%s/lib/pkgconfig' % PREFIX
        extra_pkg_path = os.environ.get('BDE_WAF_EXTRA_PKG_CONFIG_PATH')
        if extra_pkg_path:
            pkg_path += ':' + extra_pkg_path
        print('export PKG_CONFIG_PATH="%s"' % pkg_path)


def list_compilers(compiler_infos):
    print('Avaliable compilers:', file=sys.stderr)

    for idx, c in enumerate(compiler_infos[0:]):
        print(' %d:' % (idx), c.description(),
              '(default)' if idx == 0 else '', file=sys.stderr)
        print('     CXX: %s  CC: %s' % (c.cxx_path, c.c_path), file=sys.stderr)


def _determine_installation_location(prefix, uplid):
    """Return the installation location for BDE was previously encoded.

    Return the installation location encoded in the specified 'prefix' for the
    specified 'uplid', or None if a location cannot be determined.  If 'prefix'
    matches the pattern of a PREFIX environment variable emitted by
    'bde_setwafenv.py' -- i.e., it contains this cpu-architectures portions of
    'uplid' as part of the last element of a directory location -- return the
    installation directory previously used by 'bde_setwafenv.py'.

    Args:
        prefix (str): prefix
    """
    if (prefix is None):
        return None

    partialUplid = uplid.os_type + '-' + uplid.os_name + '-' + \
        uplid.cpu_type + '-' + uplid.os_ver

    pattern = "(.*/){0}(?:\-[\w\.]*)*".format(partialUplid)
    match = re.match(pattern, prefix)
    if (match):
        return match.group(1)
    return None
