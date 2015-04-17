"""Waf entry point.

Functions - Waf Command
-----------------------
option() - all commands
configure() - waf configure
build() - waf build
"""

import sys

from waflib import Utils
from waflib import Logs

from bdebld.meta import optionsutil
from bdebld.common import cmdlineutil
from bdebld.common import sysutil

from bdebld.waf import configurehelper
from bdebld.waf import configureutil
from bdebld.waf import buildhelper
from bdebld.waf import graphhelper


def options(ctx):
    # check version numbers here because options() is called before any other
    # command-handling function
    if sys.hexversion < 0x2060000:
        ctx.fatal('Pyhon 2.6 and above is required to build BDE using waf.')

    ctx.load('bdebld.waf.bdeunittest')

    from waflib.Tools.compiler_c import c_compiler
    c_compiler['win32'] = ['msvc']
    c_compiler['linux'] = ['gcc', 'clang']
    c_compiler['darwin'] = ['gcc', 'clang']
    c_compiler['aix'] = ['xlc', 'gcc']
    c_compiler['sunos'] = ['suncc', 'gcc']

    ctx.load('compiler_c')

    from waflib.Tools.compiler_cxx import cxx_compiler
    cxx_compiler['win32'] = ['msvc']
    cxx_compiler['linux'] = ['g++', 'clang++']
    cxx_compiler['darwin'] = ['g++', 'clang++']
    cxx_compiler['aix'] = ['xlc++', 'g++']
    cxx_compiler['sunos'] = ['sunc++', 'g++']
    ctx.load('compiler_cxx')

    ctx.load('msvs')
    ctx.load('xcode')

    add_cmdline_options(ctx)
    graphhelper.add_cmdline_options(ctx)


def configure(ctx):
    ctx.load('bdebld.waf.bdeunittest')

    ufid = configureutil.make_ufid(ctx)

    waf_platform = Utils.unversioned_sys_platform()
    if waf_platform == 'win32':
        if '64' in ufid.flags:
            ctx.options.msvc_targets = 'x64'
        else:
            ctx.options.msvc_targets = 'x86'
        msvc_version = configureutil.get_msvc_version_from_env()
        if msvc_version:
            ctx.options.msvc_version = 'msvc %s' % msvc_version
    else:
        if 'CXX' in ctx.environ and 'CC' not in ctx.environ:
            ctx.environ['CC'] = sysutil.get_other_compiler(
                ctx.environ['CXX'], sysutil.CompilerType.CXX)
        elif 'CC' in ctx.environ and 'CXX' not in ctx.environ:
            ctx.environ['CXX'] = sysutil.get_other_compiler(
                ctx.environ['CC'], sysutil.CompilerType.C)

    ctx.load('compiler_c')
    ctx.load('compiler_cxx')
    cc_ver = ctx.env.CC_VERSION
    cc_name = ctx.env.COMPILER_CC
    cxx_ver = ctx.env.CC_VERSION
    cxx_name = ctx.env.COMPILER_CXX

    if cxx_name in sysutil.CXX_C_COMP_MAP:
        exp_c_name = sysutil.CXX_C_COMP_MAP[cxx_name]
        if exp_c_name != cc_name:
            ctx.fatal('C compiler and C++ compiler must match. '
                      'Expected c compiler: %s' % exp_c_name)
        if cc_ver != cxx_ver:
            ctx.fatal('C compiler and C++ compiler must be the same version. '
                      'C compiler version: %s, '
                      'C++ compiler version: %s' % (cc_ver, cxx_ver))

    effective_uplid, actual_uplid = configureutil.make_uplid(ctx)
    helper = configurehelper.ConfigureHelper(ctx, ufid,
                                             effective_uplid, actual_uplid)
    helper.configure()


def build(ctx):
    if ctx.cmd == "msvs" or ctx.cmd == "msvs2008":
        if ctx.options.test:
            ctx.waf_command = 'waf.bat --test=%s' % ctx.options.test

        ctx.projects_dir = ctx.srcnode.make_node('.depproj')
        ctx.projects_dir.mkdir()

    if ctx.cmd == 'graph':
        helper = graphhelper.GraphHelper(ctx)
        helper.draw()
        return

    if ctx.cmd == 'build':
        Logs.info('Waf: Using %d jobs (change with -j)' % ctx.options.jobs)

    helper = buildhelper.BuildHelper(ctx)
    helper.build()


def add_cmdline_options(ctx):
    """Add custom command-line options to an option context.

    Args:
        ctx (OptionContext): The option context.

    Returns:
        None
    """

    configure_opts = [
        (('debug-opt-keys',),
         {'type': 'string',
          'default': None,
          'help': 'debug rules in the opts files for the specified '
                  '(comma separated) list of opts keys'}),
        (('verify',),
         {'action': 'store_true',
          'default': False,
          'help': 'Perform additional checks to verify '
                  'repository structure.'}),
        (('use-dpkg-install',),
         {'type': 'choice',
          'choices': ('yes', 'no'),
          'default': 'no',
          'help': "Whether to configure install options according to dpkg "
                  "conventions (yes/no). This options supercedes the options "
                  "'lib-suffix', 'install-flat-include', and "
                  "'install-lib-dir'. [default: %default]"}),
        (('lib-suffix',),
         {'type': 'string',
          'default': '',
          'help': '(deprecated) add a suffix to the names of the package '
                  'group library files being built'}),
        (('install-flat-include',),
         {'action': 'store_true',
          'default': False,
          'help': '(deprecated) install all headers into $PREFIX/include '
                  'instead of $PREFIX/include/<package_group>'}),
        (('install-lib-dir',),
         {'type': 'string',
          'default': 'lib',
          'help': '(deprecated) the name of the directory under $PREFIX where '
                  'library files are installed [default: %default]'}),
    ]
    configure_opts = optionsutil.get_ufid_cmdline_options() + configure_opts
    configure_group = ctx.get_option_group('configure options')

    cmdlineutil.add_options(configure_group, configure_opts)

    # Set the upper bound of the default number of jobs to 24
    jobs = ctx.parser.get_option('-j').default
    if jobs > 24:
        jobs = 24
        ctx.parser.remove_option('-j')
        ctx.parser.add_option('-j', '--jobs',
                              dest='jobs',
                              default=jobs,
                              type='int',
                              help='amount of parallel jobs (%r)' % jobs)

    build_opts = ctx.get_option_group(
        'Installation and uninstallation options')
    build_opts.add_option('--install-dep', type='choice',
                          choices=('yes', 'no'),
                          default='yes',
                          help='When doing a targeted install, wither to also '
                          'install the dependencies of the targets (yes/no) '
                          '[default: %default]',
                          dest='install_dep')

    build_opts.add_option('--install-h', type='choice',
                          choices=('yes', 'no'),
                          default='yes',
                          help='Install header files (yes/no) '
                          '[default: %default]',
                          dest='install_h')

    build_opts.add_option('--install-pc', type='choice',
                          choices=('yes', 'no'),
                          default='yes',
                          help='Install pkgconfig files (yes/no) '
                          '[default: %default]',
                          dest='install_pc')

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
