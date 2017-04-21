"""Waf entry point.

Functions - Waf Command
-----------------------
option() - all commands
configure() - waf configure
build() - waf build
"""

from __future__ import print_function

import os
import sys

from waflib import Utils
from waflib import Logs
from waflib import Context

from bdebuild.common import blderror
from bdebuild.common import cmdlineutil
from bdebuild.common import logutil
from bdebuild.common import sysutil
from bdebuild.meta import optionsutil

from bdebuild.waf import configurehelper
from bdebuild.waf import configureutil
from bdebuild.waf import buildhelper
from bdebuild.waf import graphhelper

# Version of bde-tools
BDE_TOOLS_VERSION = "1.3"

def _setup_log(ctx):
    logutil._info_nolog = Logs.info
    logutil._warn_nolog = Logs.warn
    logutil.to_log = ctx.to_log
    logutil.fatal = ctx.fatal
    logutil.msg = ctx.msg
    logutil.start_msg = ctx.start_msg
    logutil.end_msg = ctx.end_msg


def options(ctx):
    _setup_log(ctx)
    # check version numbers here because options() is called before any other
    # command-handling function

    if sys.hexversion < 0x2060000:
        ctx.fatal('Pyhon 2.6 and above is required to build BDE using waf.')

    min_version = getattr(Context.g_module, 'min_bde_tools_version', None)
    max_version = getattr(Context.g_module, 'max_bde_tools_version', None)

    if (min_version and not sysutil.match_version_strs(BDE_TOOLS_VERSION,
                                                       min_version,
                                                       max_version)):
        msg = 'This repo requires BDE Tools version of at least ' + min_version
        if max_version:
            msg += ' and at most ' + max_version

        msg += '. The current version is ' + BDE_TOOLS_VERSION + '.'
        ctx.fatal(msg)

    ctx.load('bdebuild.waf.bdeunittest')

    from waflib.Tools.compiler_c import c_compiler
    c_compiler['win32'] = ['msvc']
    c_compiler['linux'] = ['gcc', 'clang']
    c_compiler['darwin'] = ['clang', 'gcc']
    c_compiler['aix'] = ['xlc', 'gcc']
    c_compiler['sunos'] = ['suncc', 'gcc']

    ctx.load('compiler_c')

    from waflib.Tools.compiler_cxx import cxx_compiler
    cxx_compiler['win32'] = ['msvc']
    cxx_compiler['linux'] = ['g++', 'clang++']
    cxx_compiler['darwin'] = ['clang++', 'g++']
    cxx_compiler['aix'] = ['xlc++', 'g++']
    cxx_compiler['sunos'] = ['sunc++', 'g++']
    ctx.load('compiler_cxx')
    ctx.load('msvs')
    ctx.load('xcode')

    add_cmdline_options(ctx)
    graphhelper.add_cmdline_options(ctx)


def configure(ctx):
    try:
        _configure_impl(ctx)
    except blderror.BldError as e:
        ctx.fatal(str(e))
    except IOError as e:
        ctx.fatal(str(e))


def _configure_impl(ctx):
    _setup_log(ctx)

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
    ctx.load('bdebuild.waf.bdeunittest')
    effective_uplid, actual_uplid = configureutil.make_uplid(ctx)

    # If UFID is not set by bde_setwafenv.py or the --ufid flag, use "cpp11" as
    # the default when appropriate.
    if (not os.getenv('BDE_WAF_UFID') and (ctx.options.ufid is None) and
        (ctx.options.cpp_std is None) and
        (optionsutil.get_default_cpp_std(effective_uplid.comp_type,
                                         effective_uplid.comp_ver) == "11")):
        ufid.flags.add('cpp11')

    # Enable -Werror by default if the compiler is gcc-4.9 and build mode is
    # not 'opt'.
    if ctx.options.werror is None:
        if (effective_uplid.comp_type == 'gcc' and
            effective_uplid.comp_ver >= '4.9' and
                effective_uplid.comp_ver < '5' and 'opt' not in ufid.flags):
            ctx.options.werror = 'cpp'
        else:
            ctx.options.werror = 'none'

    helper = configurehelper.ConfigureHelper(ctx, ufid,
                                             effective_uplid, actual_uplid)
    helper.configure()


def build(ctx):
    try:
        _build_impl(ctx)
    except blderror.CycleError as e:
        ctx.fatal(str(e) +
                  "\nUse 'waf configure --verify' to help find more problems.")
    except blderror.BldError as e:
        ctx.fatal(str(e))


def _build_impl(ctx):
    _setup_log(ctx)
    if ctx.cmd == "msvs" or ctx.cmd == "msvs2008":
        if ctx.options.test:
            ctx.waf_command = 'waf.bat --test=%s' % ctx.options.test

        ctx.projects_dir = ctx.srcnode.make_node('.depproj')
        ctx.projects_dir.mkdir()

    if ctx.cmd == 'graph':
        helper = graphhelper.GraphHelper(ctx)
    else:
        ctx.load('bdebuild.waf.bdeunittest')
        if ctx.options.clang_compilation_database:
            ctx.load('clang_compilation_database')
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
    def print_version(option, opt, value, parser):
        print('BDE Tools version: %s' % BDE_TOOLS_VERSION)
        sys.exit(0)

    ctx.add_option('--bde-tools-version',
                   action='callback', callback=print_version)

    configure_opts = [
        (('verify',),
         {'action': 'store_true',
          'default': False,
          'help': 'perform additional checks to verify repository structure'}),
        (('use-dpkg-install',),
         {'action': 'store_true',
          'default': False,
          'help': "configure install options according to dpkg "
                  "conventions (this options supercedes the options "
                  "'use-flat-include-dir', 'libdir', and 'lib-suffix')"}),
        (('use-flat-include-dir',),
         {'action': 'store_true',
          'default': False,
          'help': 'install all headers into $PREFIX/include '
                  'instead of $PREFIX/include/<package_group>, and '
                  'change .pc files accordingly'}),
        (('libdir',),
         {'type': 'string',
          'default': 'lib',
          'dest': 'libdir',
          'help': 'the name of the directory under $PREFIX where '
                  'library files are installed [default: %default]'}),
        (('bindir',),
         {'type': 'string',
          'default': 'bin',
          'dest': 'bindir',
          'help': 'the name of the directory under $PREFIX where '
                  'binaries are installed [default: %default]'}),
        (('lib-suffix',),
         {'type': 'string',
          'default': '',
          'help': '(deprecated) add a suffix to the names of the package '
                  'group library files being built [default: %default]'}),
        (('debug-opt-keys',),
         {'type': 'string',
          'default': None,
          'help': 'debug rules in the opts files for the specified '
                  '(comma separated) list of opts keys'}),
        (('werror',),
         {'choices': ('none', 'cpp'),
          'default': None,
          'help': 'whether to treat all compiler warning as errors when '
                  'building with clang or gcc (cpp/none). '
                  "none: don't enable -Werror, "
                  'cpp: enable -Werror for .cpp files but not .t.cpp files '
                  '[default value depends on compiler]'})
    ]
    configure_group = ctx.get_option_group('configure options')
    configure_opts = optionsutil.get_ufid_cmdline_options() + configure_opts
    cmdlineutil.add_options(configure_group, configure_opts)

    waf_platform = Utils.unversioned_sys_platform()
    if waf_platform == 'win32':
        win_opts = [
            (('msvc-runtime-type',),
             {'choices': ('static', 'dynamic'),
              'default': 'dynamic',
              'help': 'whether to build using the static or dynamic version '
                      'of the C run-time library on Windows '
                      '[default: %default]'})
        ]
        cmdlineutil.add_options(configure_group, win_opts)

    install_group = ctx.get_option_group(
        'Installation and uninstallation options')
    install_opts = [
        (('install-dep',),
         {'choices': ('yes', 'no'),
          'default': 'yes',
          'help': 'when doing a targeted install, whether to also '
                  'install the dependencies of the targets (yes/no) '
                  '[default: %default]'}),
        (('install-parts',),
         {'choices': ('all', 'lib', 'bin', 'h', 'pc'),
          'default': 'all',
          'help': 'what parts to install (all/h/lib/pc). '
                  'all -- everything, '
                  'lib -- lib files only, '
                  'bin - executable files only, '
                  'h -- header files only, '
                  'pc -- pkg-config files only '
                  '[default: %default]'}),
    ]
    cmdlineutil.add_options(install_group, install_opts)

    build_group = ctx.get_option_group('build and install options')
    build_opts = [
        (('clang-compilation-database',),
         {'action': 'store_true',
          'default': False,
          'help': 'Generate a clang compilation database '
                  '(compile_commands.json) in the build output directory'})
    ]
    cmdlineutil.add_options(build_group, build_opts)

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
