"""Utilties used by waf.configure.
"""

import os
import re
import sys

from waflib import Logs
from waflib import Utils
from waflib import Context

from bdebld.meta import options
from bdebld.meta import sysutil

from bdebld.waf import cmdlineutil


def make_ufid(ctx):
    """Create the Ufid representing the current build configuration.

    Args:
        ctx (ConfigurationContext): The waf configuration context.

    Returns:
        An Ufid object.
    """

    opts = ctx.options
    env_ufid = os.getenv('BDE_WAF_UFID')
    ufid_str = None

    if env_ufid:
        if opts.ufid:
            Logs.warn(
                'WARN: The specified UFID, "%s", is different from '
                'the value of the environment variable BDE_WAF_UFID '
                ', "%s", which will take precedence. ' %
                (opts.ufid, env_ufid))
        else:
            Logs.warn(
                'WARN: Using the value of the environment variable '
                'BDE_WAF_UFID, "%s", as the UFID.' % env_ufid)
        ufid_str = env_ufid
    elif opts.ufid:
        ufid_str = opts.ufid

    if ufid_str:
        ufid = options.Ufid.from_str(ufid_str)
        if not options.Ufid.is_valid(ufid.flags):
            ctx.fatal(
                'The UFID, "%s", is invalid.  Each part of a UFID must be '
                'in the following list of valid flags: %s.' %
                (ufid_str, ", ".join(sorted(options.Ufid.VALID_FLAGS.keys()))))
        return ufid

    return cmdlineutil.make_ufid_from_cmdline_options(opts)


def make_uplid(ctx):
    """Create the Uplid representing the current build platform.

    Args:
        ctx (ConfigurationContext): The waf configuration context.

    Returns:
        An Uplid object.
    """
    os_type, os_name, os_ver = sysutil.get_os_info()
    cpu_type, comp_type, comp_ver = get_comp_info(ctx)

    uplid = options.Uplid(os_type, os_name, cpu_type, os_ver,
                          comp_type, comp_ver)

    env_uplid_str = os.getenv('BDE_WAF_UPLID')

    env_uplid_str = os.getenv('BDE_WAF_UPLID')
    if env_uplid_str:
        env_uplid = options.Uplid.from_str(env_uplid_str)

        if uplid != env_uplid:
            Logs.warn(('WARN: The identified UPLID, "%s", is different '
                       'from the environment variable BDE_WAF_UPLID. '
                       'The the value of BDE_WAF_UPLID, "%s", '
                       'is used.') % (uplid, env_uplid))
            uplid = env_uplid

    return uplid


def get_comp_info(ctx):
    """Return the operating system information part of the UPLID.

    Args:
        ctx (ConfigurationContext): The waf configuration context.

    Returns:
        cpu_type, comp_type, compiler_version
    """
    def sanitize_comp_info(cpu_type, comp_type, comp_ver):
        """Correct problematic compiler information.

        waf sets `CXX` to `gcc` for both `clang` and `gcc`. This function
        changes the `cxx_name-cxx_version` combination for `clang` to
        distinctly identify `clang` when invoked as `gcc` and indicate the
        `clang` compiler version that `waf` correctly extracts into
        `CC_VERSION`.
        """

        if comp_type != 'gcc':
            return cpu_type, comp_type, comp_ver

        cmd = ctx.env.CXX + ['-dM', '-E', '-']
        env = ctx.env.env or None

        try:
            p = Utils.subprocess.Popen(
                cmd,
                stdin=Utils.subprocess.PIPE,
                stdout=Utils.subprocess.PIPE,
                stderr=Utils.subprocess.PIPE,
                env=env)
            p.stdin.write('\n'.encode())
            out = p.communicate()[0]
        except Exception:
            ctx.conf.fatal('Could not determine the compiler version %r' % cmd)

        if not isinstance(out, str):
            out = out.decode(sys.stdout.encoding or 'iso8859-1')

        if out.find("__clang__ 1") < 0:
            return cpu_type, comp_type, comp_ver

        return cpu_type, 'clang', '.'.join(ctx.env.CC_VERSION)

    def get_linux_comp_info(ctx):
        cpu_type = os.uname()[4]
        return cpu_type, ctx.env.CXX_NAME, '.'.join(ctx.env.CC_VERSION)

    def get_aix_comp_info(ctx):
        cpu_type = ctx.cmd_and_log(['/bin/uname', '-p']).rstrip()
        cxx_name = ctx.env.CXX_NAME
        if cxx_name == 'xlc++':
            cxx_name = 'xlc'

        return cpu_type, cxx_name, '.'.join(ctx.env.CC_VERSION)

    def get_sunos_comp_info(ctx):
        cpu_type = ctx.cmd_and_log(['/bin/uname', '-p']).rstrip()
        cxx_name = ctx.env.CXX_NAME
        if cxx_name == 'sun':
            cxx_name = 'cc'

        return cpu_type, cxx_name, '.'.join(ctx.env.CC_VERSION)

    def get_darwin_comp_info(ctx):
        cpu_type = os.uname()[4]

        return cpu_type, ctx.env.CXX_NAME, '.'.join(ctx.env.CC_VERSION)

    def get_windows_comp_info(ctx):
        env = dict(ctx.environ)
        env.update(PATH=';'.join(ctx.env['PATH']))
        err = ctx.cmd_and_log(ctx.env['CXX'], output=Context.STDERR, env=env)

        m = re.search(r'Compiler Version ([0-9]+\.[0-9]+).*? for (\S*)', err)
        if m:
            compiler = 'cl'
            compilerversion = m.group(1)
            model = m.group(2)
            if model == '80x86':
                cpu_type = 'x86'
            elif model == 'x64':
                cpu_type = 'amd64'
            else:
                cpu_type = model

        return cpu_type, compiler, compilerversion

    platform_str = sysutil.unversioned_platform()
    comp_info_getters = {
        'linux': get_linux_comp_info,
        'aix': get_aix_comp_info,
        'sunos': get_sunos_comp_info,
        'darwin': get_darwin_comp_info,
        'win32': get_windows_comp_info
        }

    if platform_str not in comp_info_getters:
        raise ValueError('Unsupported platform %s' % platform_str)

    uplid = sanitize_comp_info(*comp_info_getters[platform_str](ctx))

    return uplid

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
